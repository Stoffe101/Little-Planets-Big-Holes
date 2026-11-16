class_name DigSystem
extends Node
## The single entry point for every terrain modification.
##
## Tools, cannons and robots never touch the voxel data directly: they build a dig command
## (`dig_sphere` / `dig_capsule`) and this system validates it against material hardness,
## applies it to the VoxelTerrain, and reports what was excavated. Keeping edits behind one
## narrow command API is what will let co-op replicate terrain later (send the command, every
## peer applies it deterministically).

signal dug(result: Dictionary)

const SAMPLE_COUNT := 56
const BLOCK_RATIO := 0.72          ## if this much of the bite is too hard, the tool bounces off

var planet: Planet
var _samples := PackedVector3Array()
var _remainder: Dictionary = {}    ## material index -> fractional units carried to the next dig
var last_dig_usec := 0             ## instrumentation: duration of the most recent dig
var last_survey_usec := 0          ## ... of which surveying the bite (material samples)
var last_edit_usec := 0            ## ... of which the voxel edit itself
var total_digs := 0
var total_dig_usec := 0


func _init() -> void:
	# Deterministic, well distributed points inside the unit ball (golden-spiral shells).
	var golden := PI * (3.0 - sqrt(5.0))
	for i in SAMPLE_COUNT:
		var t := (float(i) + 0.5) / float(SAMPLE_COUNT)
		var y := 1.0 - 2.0 * t
		var rr := sqrt(maxf(0.0, 1.0 - y * y))
		var th := golden * float(i)
		var shell := pow(fmod(float(i) * 0.6180339, 1.0) * 0.85 + 0.15, 1.0 / 3.0)
		_samples.append(Vector3(cos(th) * rr, y, sin(th) * rr) * shell)


func setup(p: Planet) -> void:
	planet = p
	_remainder.clear()


## Surveys what a spherical bite would contain without modifying anything.
## Returns {solid, hard, counts: {mat: n}, dominant, dominant_hard}.
func survey(center: Vector3, radius: float, power: int) -> Dictionary:
	var geo := planet.geology
	var counts: Dictionary = {}
	var solid := 0
	var hard := 0
	var hard_counts: Dictionary = {}
	for s in _samples:
		var p := center + s * radius
		if planet.sdf_at(p) >= 0.0:
			continue
		var m := geo.material_at(p)
		solid += 1
		if geo.hardness_of(m) > power:
			hard += 1
			hard_counts[m] = int(hard_counts.get(m, 0)) + 1
		else:
			counts[m] = int(counts.get(m, 0)) + 1
	return {"solid": solid, "hard": hard, "counts": counts, "dominant": _dominant(counts), "dominant_hard": _dominant(hard_counts)}


static func _dominant(counts: Dictionary) -> int:
	var best := -1
	var best_n := 0
	for m: int in counts:
		if int(counts[m]) > best_n:
			best_n = int(counts[m])
			best = m
	return best


## True if every voxel in the box (world metres) is loaded at full resolution. Edits are only
## possible there (VoxelLodTerrain keeps full-resolution voxels near the viewer only).
func _editable(lo: Vector3, hi: Vector3) -> bool:
	var inv := planet.geology.inv_voxel
	var a := (lo * inv).floor() - Vector3.ONE * 2.0
	var b := (hi * inv).ceil() + Vector3.ONE * 2.0
	return planet.voxel_tool.is_area_editable(AABB(a, b - a))


## Excavates a sphere. `power` is the tool's strength (compared with material hardness).
## opts: {"yield_mult": float, "ore_yield": float (bonus fraction for ore/crystal), "source": String}
## Result: {ok, blocked, empty, center, radius, volume, yields: {mat_index: int units},
##          dominant, hard_material, hit_hard}
func dig_sphere(center: Vector3, radius: float, power: int, opts: Dictionary = {}) -> Dictionary:
	var t0 := Time.get_ticks_usec()
	var result := {"ok": false, "blocked": false, "empty": false, "center": center, "radius": radius,
		"volume": 0.0, "yields": {}, "dominant": -1, "hard_material": -1, "hit_hard": false}
	if planet == null or not planet.is_loaded:
		result["empty"] = true
		return result
	if not _editable(center - Vector3.ONE * radius, center + Vector3.ONE * radius):
		result["empty"] = true
		result["unloaded"] = true
		return result
	var ts := Time.get_ticks_usec()
	var sv := survey(center, radius, power)
	last_survey_usec = Time.get_ticks_usec() - ts
	var solid: int = sv["solid"]
	var hard: int = sv["hard"]
	result["dominant"] = sv["dominant"]
	result["hard_material"] = sv["dominant_hard"]
	result["hit_hard"] = hard > 0
	if solid == 0:
		result["empty"] = true
		return result
	if hard == solid or float(hard) / float(solid) > BLOCK_RATIO:
		result["blocked"] = true
		GameState.add_stat("blocked_digs")
		dug.emit(result)
		return result

	var inv := planet.geology.inv_voxel
	var vt := planet.voxel_tool
	vt.mode = VoxelTool.MODE_REMOVE
	var te := Time.get_ticks_usec()
	if hard == 0:
		vt.do_sphere(center * inv, radius * inv)
	else:
		_selective_sphere(center, radius, power)
	last_edit_usec = Time.get_ticks_usec() - te

	var sphere_volume := 4.0 / 3.0 * PI * radius * radius * radius
	_finish(result, sv["counts"], sphere_volume / float(SAMPLE_COUNT), opts)
	result["volume"] = sphere_volume * float(solid - hard) / float(SAMPLE_COUNT)
	_record(result, center, t0)
	return result


## Excavates a capsule from `a` to `b` (trenches and bored tunnels).
func dig_capsule(a: Vector3, b: Vector3, radius: float, power: int, opts: Dictionary = {}) -> Dictionary:
	var t0 := Time.get_ticks_usec()
	var length := a.distance_to(b)
	var steps := maxi(1, int(ceil(length / maxf(radius * 0.9, 0.2))))
	var result := {"ok": false, "blocked": false, "empty": false, "center": (a + b) * 0.5, "radius": radius,
		"volume": 0.0, "yields": {}, "dominant": -1, "hard_material": -1, "hit_hard": false}
	if planet == null or not planet.is_loaded:
		result["empty"] = true
		return result
	var lo := Vector3(minf(a.x, b.x), minf(a.y, b.y), minf(a.z, b.z)) - Vector3.ONE * radius
	var hi := Vector3(maxf(a.x, b.x), maxf(a.y, b.y), maxf(a.z, b.z)) + Vector3.ONE * radius
	if not _editable(lo, hi):
		result["empty"] = true
		result["unloaded"] = true
		return result
	var counts: Dictionary = {}
	var hard_counts: Dictionary = {}
	var solid := 0
	var hard := 0
	for i in steps + 1:
		var sv := survey(a.lerp(b, float(i) / float(steps)), radius, power)
		solid += int(sv["solid"])
		hard += int(sv["hard"])
		for m: int in sv["counts"]:
			counts[m] = int(counts.get(m, 0)) + int(sv["counts"][m])
		if int(sv["dominant_hard"]) >= 0:
			hard_counts[sv["dominant_hard"]] = int(hard_counts.get(sv["dominant_hard"], 0)) + int(sv["hard"])
	result["dominant"] = _dominant(counts)
	result["hard_material"] = _dominant(hard_counts)
	result["hit_hard"] = hard > 0
	if solid == 0:
		result["empty"] = true
		return result
	if hard == solid or float(hard) / float(solid) > BLOCK_RATIO:
		result["blocked"] = true
		GameState.add_stat("blocked_digs")
		dug.emit(result)
		return result
	var inv := planet.geology.inv_voxel
	var vt := planet.voxel_tool
	vt.mode = VoxelTool.MODE_REMOVE
	if hard == 0:
		vt.do_path(PackedVector3Array([a * inv, b * inv]), PackedFloat32Array([radius * inv, radius * inv]))
	else:
		for i in steps + 1:
			_selective_sphere(a.lerp(b, float(i) / float(steps)), radius, power)
	# Overlapping survey spheres over-count the capsule; normalise by its true volume.
	var cap_volume := PI * radius * radius * length + 4.0 / 3.0 * PI * radius * radius * radius
	var per_sample := cap_volume / float((steps + 1) * SAMPLE_COUNT)
	_finish(result, counts, per_sample, opts)
	result["volume"] = per_sample * float(solid - hard)
	_record(result, result["center"], t0)
	return result


## Removes a sphere but leaves voxels of too-hard material untouched, so tough ore veins
## end up standing proud of the softer ground that was dug away around them.
func _selective_sphere(center: Vector3, radius: float, power: int) -> void:
	var geo := planet.geology
	var inv := geo.inv_voxel
	var vt := planet.voxel_tool
	var cv := center * inv
	var rv := radius * inv
	var minp := Vector3i((cv - Vector3.ONE * (rv + 2.0)).floor())
	var size := int(ceil(rv * 2.0 + 4.0))
	if size % 2 == 1:
		size += 1
	var mask := 1 << VoxelBuffer.CHANNEL_SDF
	var before := VoxelBuffer.new()
	before.create(size, size, size)
	vt.copy(minp, before, mask)
	vt.mode = VoxelTool.MODE_REMOVE
	vt.do_sphere(cv, rv)
	var after := VoxelBuffer.new()
	after.create(size, size, size)
	vt.copy(minp, after, mask)
	var ch := VoxelBuffer.CHANNEL_SDF
	var changed := false
	var reach := (rv + 1.8) * (rv + 1.8)
	for z in range(0, size, 2):
		for y in range(0, size, 2):
			for x in range(0, size, 2):
				var cell := Vector3(minp) + Vector3(x + 1, y + 1, z + 1)
				if cell.distance_squared_to(cv) > reach:
					continue
				# Only cells that held ground before the bite matter.
				if before.get_voxel_f(x, y, z, ch) >= 0.0 and before.get_voxel_f(x + 1, y + 1, z + 1, ch) >= 0.0 \
						and before.get_voxel_f(x + 1, y, z, ch) >= 0.0 and before.get_voxel_f(x, y + 1, z + 1, ch) >= 0.0:
					continue
				if geo.hardness_of(geo.material_at(cell * geo.voxel_size)) <= power:
					continue
				for dz in 2:
					for dy in 2:
						for dx in 2:
							after.set_voxel_f(before.get_voxel_f(x + dx, y + dy, z + dz, ch), x + dx, y + dy, z + dz, ch)
				changed = true
	if changed:
		vt.paste(minp, after, mask)


func _finish(result: Dictionary, counts: Dictionary, volume_per_sample: float, opts: Dictionary) -> void:
	var yield_mult := float(opts.get("yield_mult", 1.0))
	var ore_bonus := float(opts.get("ore_yield", 0.0))
	var yields: Dictionary = {}
	for m: int in counts:
		var def := GameData.materials[m]
		var units := float(counts[m]) * volume_per_sample * float(def["yield"]) * yield_mult
		if str(def["category"]) in ["ore", "crystal", "exotic"]:
			units *= 1.0 + ore_bonus
		units += float(_remainder.get(m, 0.0))
		var whole := int(floor(units))
		_remainder[m] = units - float(whole)
		if whole > 0:
			yields[m] = whole
	result["yields"] = yields
	result["ok"] = true


func _record(result: Dictionary, center: Vector3, t0: int) -> void:
	last_dig_usec = Time.get_ticks_usec() - t0
	total_digs += 1
	total_dig_usec += last_dig_usec
	GameState.stats["digs"] = int(GameState.stats.get("digs", 0)) + 1
	GameState.stats["volume_dug"] = float(GameState.stats.get("volume_dug", 0.0)) + float(result["volume"])
	GameState.set_stat_max("max_depth", planet.geology.depth_at(center))
	GameState.check_objectives()
	dug.emit(result)


func average_dig_ms() -> float:
	return float(total_dig_usec) / 1000.0 / float(maxi(total_digs, 1))
