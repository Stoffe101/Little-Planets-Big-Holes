class_name PropField
extends Node3D
## Streamed surface dressing: ground cover, ferns, pebbles, shrubs, trees, boulders, crystal
## formations and landmarks (standing stones on mountain shoulders, cairns at cave mouths).
##
## The sphere is divided into a cube-sphere grid of ~28 m cells. Cells near the player are
## built under a per-frame time budget and freed again when the player moves on:
##   * "near" layer (tufts, ferns, pebbles) within NEAR_RANGE,
##   * "far" layer (shrubs, trees, boulders, crystals, landmarks) within FAR_RANGE.
## Everything in a cell is derived from (seed, cell, kind, index), so a cell always rebuilds
## identically and crystal flags stay valid. Props are placed on the ORIGINAL surface; where the
## terrain is loaded the real (dug) ground is checked first, and cells built before their terrain
## loaded are re-checked once it does, so nothing floats over an old excavation.
##
## Densities are per 1000 m^2 in the planet's `props` block; regions multiply them
## (`regions[].props`). Design rules: docs/ART_DIRECTION.md, "Environment".

const NEAR_RANGE := 72.0
const FAR_RANGE := 230.0
const CELL_TARGET := 28.0            ## metres per cell edge (approximately)
const BUILD_BUDGET_USEC := 2500      ## main-thread time per frame spent building cells
const OUTPOST_CLEARANCE := 10.5      ## metres around the lander kept clear (matches World.PROTECT_RADIUS)
const NEAR_KINDS := ["tuft", "fern", "pebble"]
const FAR_KINDS := ["shrub", "tree", "boulder"]
const KIND_ID := {"tuft": 1, "fern": 2, "shrub": 3, "tree": 4, "boulder": 5, "pebble": 6, "crystal": 11}

var world: World
var planet: Planet
var geo: Geology
var prop_count := 0
var formation_count := 0
var landmark_count := 0
var cells_built := 0
var _cfg: Dictionary = {}
var _foliage: Array[Color] = []
var _rocks: Array[Color] = []
var _meshes: Dictionary = {}          ## kind -> Array[ArrayMesh]
var _n := 8                           ## cells per cube face edge
var _centers: Array[Vector3] = []     ## cell index -> centre direction
var _cell_area := PackedFloat32Array()
var _cells: Dictionary = {}           ## cell index -> {near, far, items: Array, nodes_near, nodes_far, verified}
var _queue: Array = []                ## [cell, layer]
var _landmarks_by_cell: Dictionary = {}   ## cell index -> Array of landmark specs
var _max_mult: Dictionary = {}        ## kind -> highest regional multiplier
var _scan_timer := 0.0
var _rng := RandomNumberGenerator.new()
var _focus := Vector3.ZERO
var enabled := true
var _relay_dirs: Array[Vector3] = []
const RELAY_CLEARANCE := 8.5             ## keeps the mast and the relay-travel arrival spot clear


func setup(w: World) -> void:
	world = w
	planet = w.planet
	geo = planet.geology
	_cfg = planet.config.get("props", {})
	for c: Variant in _cfg.get("foliage", ["#6f8f5a", "#5f8468", "#8f9a5e"]):
		_foliage.append(Color(str(c)))
	for c: Variant in _cfg.get("rock", ["#8d9097", "#978f86"]):
		_rocks.append(Color(str(c)))
	for r: Dictionary in planet.config.get("relays", []):
		_relay_dirs.append(Vector3(r["dir"][0], r["dir"][1], r["dir"][2]).normalized())
	_build_grid()
	_build_meshes()
	_plan_landmarks()
	for kind: String in NEAR_KINDS + FAR_KINDS + ["crystal"]:
		var m := 1.0
		for r in geo.regions:
			var rp: Dictionary = (r["cfg"] as Dictionary).get("props", {})
			m = maxf(m, float(rp.get(kind, 1.0)))
		_max_mult[kind] = m
	if DisplayServer.get_name() == "headless" and not OS.get_cmdline_user_args().has("--props"):
		# Headless runs (tests, tools) still get props around the arrival point, built at once.
		pass
	_focus = w.player.global_position if w.player != null else geo.spawn_position()
	update_now()


# ------------------------------------------------------------------ grid

func _face_basis(face: int) -> Basis:
	var axis := [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.BACK, Vector3.FORWARD][face] as Vector3
	var t1 := axis.cross(Vector3.FORWARD if absf(axis.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	var t2 := axis.cross(t1).normalized()
	return Basis(t1, t2, axis)


func _face_dir(face: int, u: float, v: float) -> Vector3:
	var b := _face_basis(face)
	return (b.z + b.x * u + b.y * v).normalized()


func _build_grid() -> void:
	_n = maxi(4, int(ceil(PI * 0.5 * geo.radius / CELL_TARGET)))
	_centers.clear()
	_cell_area.clear()
	for face in 6:
		for iv in _n:
			for iu in _n:
				var u0 := -1.0 + 2.0 * float(iu) / float(_n)
				var v0 := -1.0 + 2.0 * float(iv) / float(_n)
				var u1 := u0 + 2.0 / float(_n)
				var v1 := v0 + 2.0 / float(_n)
				_centers.append(_face_dir(face, (u0 + u1) * 0.5, (v0 + v1) * 0.5))
				var a := _face_dir(face, u0, v0) * geo.radius
				var b := _face_dir(face, u1, v0) * geo.radius
				var c := _face_dir(face, u0, v1) * geo.radius
				_cell_area.append((b - a).cross(c - a).length())


func cell_of(dir: Vector3) -> int:
	var d := dir.normalized()
	var ax := absf(d.x); var ay := absf(d.y); var az := absf(d.z)
	var face := 0
	if ax >= ay and ax >= az:
		face = 0 if d.x > 0.0 else 1
	elif ay >= az:
		face = 2 if d.y > 0.0 else 3
	else:
		face = 4 if d.z > 0.0 else 5
	var b := _face_basis(face)
	var k := 1.0 / d.dot(b.z)
	var u := d.dot(b.x) * k
	var v := d.dot(b.y) * k
	var iu := clampi(int(floor((u + 1.0) * 0.5 * float(_n))), 0, _n - 1)
	var iv := clampi(int(floor((v + 1.0) * 0.5 * float(_n))), 0, _n - 1)
	return face * _n * _n + iv * _n + iu


func _cell_uv(cell: int) -> Array:
	var face := cell / (_n * _n)
	var rem := cell % (_n * _n)
	var iv := rem / _n
	var iu := rem % _n
	return [face, -1.0 + 2.0 * float(iu) / float(_n), -1.0 + 2.0 * float(iv) / float(_n), 2.0 / float(_n)]


# ------------------------------------------------------------------ streaming

func _process(delta: float) -> void:
	if world == null or world.player == null or not enabled:
		return
	_scan_timer -= delta
	if _scan_timer <= 0.0:
		_scan_timer = 0.4
		_focus = world.player.global_position
		_rescan()
	_build_some(BUILD_BUDGET_USEC)


## Rebuilds the wanted-cell list around the focus and builds everything immediately
## (used at setup and by tests/tools after teleporting).
func update_now(focus: Variant = null) -> void:
	if focus != null:
		_focus = focus
	_rescan()
	_build_some(1 << 30)


func _rescan() -> void:
	var fdir := _focus.normalized()
	var cos_near := cos((NEAR_RANGE + CELL_TARGET) / geo.radius)
	var cos_far := cos((FAR_RANGE + CELL_TARGET) / geo.radius)
	var cos_drop_near := cos((NEAR_RANGE + CELL_TARGET * 2.5) / geo.radius)
	var cos_drop_far := cos((FAR_RANGE + CELL_TARGET * 2.5) / geo.radius)
	var want: Array = []
	for i in _centers.size():
		var d := _centers[i].dot(fdir)
		var c: Dictionary = _cells.get(i, {})
		if d > cos_far and not bool(c.get("far", false)):
			want.append([i, "far", d])
		if d > cos_near and not bool(c.get("near", false)):
			want.append([i, "near", d])
		if not c.is_empty():
			if bool(c.get("near", false)) and d < cos_drop_near:
				_free_layer(i, "near")
			if bool(c.get("far", false)) and d < cos_drop_far:
				_free_layer(i, "far")
			if bool(c.get("verify", false)) and d > cos_near and planet.is_area_ready(_centers[i] * geo.surface_radius(_centers[i]), 4.0):
				_verify_cell(i)
	want.sort_custom(func(a: Array, b: Array) -> bool: return float(a[2]) > float(b[2]))
	_queue = want


func _build_some(budget_usec: int) -> void:
	var t0 := Time.get_ticks_usec()
	while not _queue.is_empty() and Time.get_ticks_usec() - t0 < budget_usec:
		var job: Array = _queue.pop_front()
		_build_layer(int(job[0]), str(job[1]))


# ------------------------------------------------------------------ placement

func _item(kind: int, cell: int, index: int) -> void:
	_rng.seed = (geo.seed_value * 73856093) ^ (kind * 19349663) ^ (cell * 83492791) ^ (index * 2654435761)


## Regional multiplier for a prop kind at a direction.
func _mult(kind: String, dir: Vector3) -> float:
	var m := 1.0
	for r in geo.regions:
		var rp: Dictionary = (r["cfg"] as Dictionary).get("props", {})
		if rp.has(kind):
			var w := smoothstep(float(r["cos_out"]), float(r["cos_in"]), dir.dot(r["dir"]))
			m += w * (float(rp[kind]) - 1.0)
	return maxf(m, 0.0)


## Surface transform for a direction, or null if the spot is unusable (inside the outpost,
## too steep, or - where the terrain is loaded - already dug out).
func _site(dir: Vector3, max_slope: float, spin: float) -> Variant:
	var ang := acos(clampf(dir.dot(geo.landing_dir), -1.0, 1.0))
	if ang * geo.radius < OUTPOST_CLEARANCE:
		return null
	for rd in _relay_dirs:
		if dir.dot(rd) > cos(RELAY_CLEARANCE / geo.radius):
			return null
	var r := geo.surface_radius(dir)
	var p := dir * r
	if planet.is_loaded_at(p) and (planet.sdf_at(p - dir * 0.6) >= 0.0 or planet.sdf_at(p + dir * 0.7) < 0.0):
		return null
	var t1 := dir.cross(Vector3(0.3, 1, 0.2)).normalized()
	var t2 := dir.cross(t1).normalized()
	var e := 1.5 / geo.radius
	var h0 := geo.height_at(dir)
	var gx := (geo.height_at((dir + t1 * e).normalized()) - h0) / 1.5
	var gz := (geo.height_at((dir + t2 * e).normalized()) - h0) / 1.5
	if sqrt(gx * gx + gz * gz) > max_slope:
		return null
	var n := (dir - t1 * gx * 0.7 - t2 * gz * 0.7).normalized()
	var x := n.cross(Vector3(0.21, 0.34, 0.91)).normalized().rotated(n, spin)
	return Transform3D(Basis(x, n, x.cross(n).normalized()), p)


func _upright(site: Transform3D, spin: float, sink := 0.12) -> Transform3D:
	var dir := site.origin.normalized()
	var x := dir.cross(Vector3(0.21, 0.34, 0.91)).normalized().rotated(dir, spin)
	return Transform3D(Basis(x, dir, x.cross(dir).normalized()), site.origin - dir * sink)


func _random_in_cell(cell: int) -> Vector3:
	var uv := _cell_uv(cell)
	return _face_dir(int(uv[0]), float(uv[1]) + _rng.randf() * float(uv[3]), float(uv[2]) + _rng.randf() * float(uv[3]))


func _build_layer(cell: int, layer: String) -> void:
	if not _cells.has(cell):
		_cells[cell] = {"near": false, "far": false, "items": [], "nodes_near": [], "nodes_far": [], "verify": false}
	var c: Dictionary = _cells[cell]
	if bool(c[layer]):
		return
	c[layer] = true
	cells_built += 1
	var area := _cell_area[cell]
	var centre := _centers[cell]
	var verified := planet.is_area_ready(centre * geo.surface_radius(centre), 3.0)
	if not verified:
		c["verify"] = true
	var kinds: Array = NEAR_KINDS if layer == "near" else FAR_KINDS
	var batches: Dictionary = {}       # "kind/variant" -> {xforms, items}
	for kind: String in kinds:
		var density := float(_cfg.get(kind, 0.0)) / 1000.0
		if density <= 0.0:
			continue
		var max_m := float(_max_mult.get(kind, 1.0))
		var candidates := int(round(density * area * max_m))
		var variants: Array = _meshes.get(kind, [])
		if variants.is_empty():
			continue
		for i in candidates:
			_item(KIND_ID[kind], cell, i)
			var dir := _random_in_cell(cell)
			var keep := _rng.randf()
			var scale := _rng.randf_range(0.8, 1.6)
			var spin := _rng.randf() * TAU
			var v := _rng.randi() % variants.size()
			if keep * max_m > _mult(kind, dir):
				continue
			if kind == "tuft" and _rng.randf() < smoothstep(0.42, 0.7, geo.tint_at(dir).x) * 0.85:
				continue          # open lawns where the tint is high
			if kind == "fern" and geo.tint_at(dir).y < 0.5:
				continue          # ferns gather in meadow patches
			var site: Variant = _site(dir, 1.2 if kind == "pebble" else (0.45 if kind == "tree" else 0.8), spin)
			if site == null:
				continue
			var xf: Transform3D = site
			var body_r := 0.0
			var body_h := 0.0
			match kind:
				"tree":
					xf = _upright(xf, spin)
					scale = _rng.randf_range(0.85, 1.35)
					body_r = 0.14; body_h = 2.6
				"boulder":
					scale = _rng.randf_range(0.6, 2.2)
					xf.origin -= xf.basis.y * 0.08 * scale
					body_r = 0.46; body_h = 0.5
				"pebble":
					scale = _rng.randf_range(0.7, 1.8)
			var key := "%s/%d" % [kind, v]
			if not batches.has(key):
				batches[key] = {"mesh": variants[v], "kind": kind, "xforms": [], "bodies": []}
			var t := Transform3D(xf.basis.scaled(Vector3.ONE * scale), xf.origin)
			(batches[key]["xforms"] as Array).append(t)
			var body: StaticBody3D = null
			if body_r > 0.0:
				body = _make_body(xf, body_r * scale, body_h * scale)
			(batches[key]["bodies"] as Array).append(body)
	var nodes: Array = c["nodes_" + layer]
	for key: String in batches:
		var bt: Dictionary = batches[key]
		var xforms: Array = bt["xforms"]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = bt["mesh"]
		mm.instance_count = xforms.size()
		for i in xforms.size():
			mm.set_instance_transform(i, xforms[i])
			(c["items"] as Array).append({"mm": mm, "i": i, "pos": (xforms[i] as Transform3D).origin, "body": (bt["bodies"] as Array)[i], "layer": layer})
			prop_count += 1
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		var kind2 := str(bt["kind"])
		mmi.material_override = MeshKit.sway_material() if kind2 in ["tuft", "fern", "tree"] else MeshKit.material()
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if kind2 in ["shrub", "tree", "boulder"] else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if kind2 in ["tuft", "pebble", "fern"]:
			mmi.visibility_range_end = NEAR_RANGE + 10.0
			mmi.visibility_range_end_margin = 8.0
			mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		add_child(mmi)
		nodes.append(mmi)
	for b: Dictionary in batches.values():
		for body: Variant in b["bodies"]:
			if body != null:
				nodes.append(body)
	if layer == "far":
		_build_crystals(cell, nodes)
		for spec: Dictionary in _landmarks_by_cell.get(cell, []):
			var lm := _build_landmark(spec)
			if lm != null:
				nodes.append(lm)
				(c["items"] as Array).append({"mm": null, "i": -1, "pos": lm.global_position, "body": lm, "layer": "far", "landmark": true})


func _make_body(xf: Transform3D, radius: float, height: float) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 4
	body.collision_mask = 0
	var shape := CapsuleShape3D.new()
	shape.radius = radius
	shape.height = maxf(height, radius * 2.0)
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position = Vector3(0, height * 0.5, 0)
	body.add_child(col)
	add_child(body)
	body.global_transform = Transform3D(xf.basis.orthonormalized(), xf.origin)
	return body


func _free_layer(cell: int, layer: String) -> void:
	var c: Dictionary = _cells.get(cell, {})
	if c.is_empty() or not bool(c[layer]):
		return
	c[layer] = false
	for n: Variant in c["nodes_" + layer]:
		if is_instance_valid(n):
			if n is Formation:
				formation_count -= 1
			(n as Node).queue_free()
	(c["nodes_" + layer] as Array).clear()
	var keep: Array = []
	for it: Dictionary in c["items"]:
		if str(it["layer"]) == layer:
			if it.has("landmark"):
				landmark_count -= 1
			else:
				prop_count -= 1
		else:
			keep.append(it)
	c["items"] = keep
	if not bool(c["near"]) and not bool(c["far"]):
		_cells.erase(cell)


## Hides props of a cell that was built before its terrain loaded and turns out to stand over
## an excavation (or inside a cave mouth).
func _verify_cell(cell: int) -> void:
	var c: Dictionary = _cells[cell]
	c["verify"] = false
	for it: Dictionary in c["items"]:
		var p: Vector3 = it["pos"]
		var up := p.normalized()
		if planet.sdf_at(p - up * 0.6) >= 0.0 or planet.sdf_at(p + up * 0.7) < 0.0:
			_remove_item(it)


func _remove_item(it: Dictionary) -> void:
	if it.get("gone", false):
		return
	it["gone"] = true
	if it["mm"] != null:
		(it["mm"] as MultiMesh).set_instance_transform(int(it["i"]), Transform3D(Basis.from_scale(Vector3.ZERO), it["pos"]))
	if it["body"] != null and is_instance_valid(it["body"]):
		(it["body"] as Node).queue_free()
		it["body"] = null


# ------------------------------------------------------------------ meshes

## Tree silhouettes 4 and 5: a short tree with a round, clustered crown, and a tall spire of
## stacked, shrinking canopy tiers. Same faceted canopy language as the others.
func _odd_tree(v: int, col: Color) -> ArrayMesh:
	var kit := MeshKit.new().matte()
	if v == 4:
		var lean := Vector3(-0.12, 0, 0.16)
		kit.tube(Vector3.ZERO, lean + Vector3(0, 1.5, 0), 0.15, 0.1, Pal.BARK, 7)
		kit.tube(lean + Vector3(0, 1.2, 0), lean + Vector3(-0.45, 1.75, 0.2), 0.06, 0.04, Pal.BARK, 5)
		kit.sway = 0.01
		var c := lean + Vector3(0, 2.05, 0)
		kit.rock(Transform3D(Basis.from_scale(Vector3(1.0, 0.78, 1.0)), c), 0.95, col.darkened(0.06), 71, 0.18, false)
		kit.rock(Transform3D(Basis.from_scale(Vector3(1.0, 0.75, 1.0)), c + Vector3(0.62, -0.18, 0.2)), 0.62, col, 73, 0.18, false)
		kit.rock(Transform3D(Basis.from_scale(Vector3(1.0, 0.75, 1.0)), c + Vector3(-0.55, -0.1, -0.3)), 0.58, col.lightened(0.06), 79, 0.18, false)
		kit.rock(Transform3D(Basis.from_scale(Vector3(1.0, 0.8, 1.0)), c + Vector3(0.05, 0.55, 0.05)), 0.55, col.lightened(0.1), 83, 0.18, false)
	else:
		kit.tube(Vector3.ZERO, Vector3(0.05, 4.6, 0.03), 0.12, 0.05, Pal.BARK, 7)
		kit.sway = 0.01
		for k in 4:
			var y := 1.9 + float(k) * 0.85
			var r := 1.0 - float(k) * 0.2
			kit.rock(Transform3D(Basis.from_scale(Vector3(1.0, 0.28, 1.0)), Vector3(0.05 * float(k % 2), y, 0.0)), r, col.lightened(0.04 * float(k)), 89 + k, 0.13, false)
	kit.sway = 0.0
	return kit.commit()


func _foliage_color(i: int) -> Color:
	return _foliage[i % _foliage.size()]


func _rock_color(i: int) -> Color:
	return _rocks[i % _rocks.size()]


func _build_meshes() -> void:
	# ground-cover blades in the ground's own colours
	var tufts: Array = []
	for v in 3:
		var kit := MeshKit.new().matte()
		kit.sway = 0.22
		var base_col := _foliage_color(v).darkened(0.08)
		var blades := 5 + v
		for b in blades:
			var a := TAU * float(b) / float(blades) + float(v) * 0.7
			var lean := Vector3(cos(a), 0, sin(a))
			var h := 0.2 + 0.11 * float((b * 7 + v) % 4) / 3.0
			kit.leaf(lean * 0.015, lean * (0.05 + 0.03 * float(b % 2)) + Vector3(0, h, 0), 0.022, base_col.lightened(0.1 * float(b % 3) / 2.0), lean)
		tufts.append(kit.commit())
	_meshes["tuft"] = tufts
	# low rosettes; one variant carries a small muted bud
	var accent := Color(str(_cfg.get("accent", "#c98a6a")))
	var ferns: Array = []
	for v in 3:
		var kit := MeshKit.new().matte()
		kit.sway = 0.1
		var col := _foliage_color(v + 1).darkened(0.14)
		var leaves := 6 + v
		for l in leaves:
			var a := TAU * float(l) / float(leaves) + float(v)
			var out := Vector3(cos(a), 0, sin(a))
			kit.leaf(out * 0.03 + Vector3(0, 0.02, 0), out * (0.26 + 0.07 * float(l % 2)) + Vector3(0, 0.1 + 0.05 * float(l % 3), 0), 0.11, col.lightened(0.07 * float(l % 2)), Vector3.UP)
		if v == 2:
			kit.sway = 0.14
			kit.tube(Vector3(0, 0.02, 0), Vector3(0.01, 0.3, 0.0), 0.008, 0.006, col.darkened(0.1), 4)
			kit.sphere(Vector3(0.01, 0.32, 0.0), 0.035, accent, Vector3(1, 1.25, 1), 6, 4)
		ferns.append(kit.commit())
	_meshes["fern"] = ferns
	# faceted low shrubs
	var shrubs: Array = []
	for v in 3:
		var kit := MeshKit.new().matte()
		var col := _foliage_color(v).darkened(0.2)
		kit.rock(Transform3D(Basis.from_scale(Vector3(1.0, 0.72, 1.0)), Vector3(0, 0.3, 0)), 0.4, col, 31 + v, 0.16, false)
		kit.rock(Transform3D(Basis.from_scale(Vector3(1.0, 0.7, 1.0)), Vector3(0.34, 0.2, 0.1)), 0.27, col.lightened(0.05), 47 + v, 0.16, false)
		if v > 0:
			kit.rock(Transform3D(Basis.from_scale(Vector3(1.0, 0.7, 1.0)), Vector3(-0.28, 0.18, -0.16)), 0.25, col.darkened(0.05), 59 + v, 0.16, false)
		shrubs.append(kit.commit())
	_meshes["shrub"] = shrubs
	# trees: four slender ones with flat, layered canopies, plus two other silhouettes so a grove
	# does not read as one tree copied (a low round-crowned one and a tall tiered spire)
	var canopy: Array = _cfg.get("tree_canopy", ["#5f8a6e", "#74935c"])
	var trees: Array = []
	if float(_cfg.get("tree", 0.0)) > 0.0:
		for v in 6:
			if v >= 4:
				trees.append(_odd_tree(v, Color(str(canopy[v % canopy.size()]))))
				continue
			var kit := MeshKit.new().matte()
			var col := Color(str(canopy[v % canopy.size()]))
			var tall := v >= 2
			var h := 3.6 if tall else 2.5
			var bend := Vector3(0.22 if v % 2 == 0 else -0.18, 0, 0.1)
			kit.tube(Vector3.ZERO, bend + Vector3(0, h * 0.55, 0), 0.11, 0.075, Pal.BARK, 7)
			kit.tube(bend + Vector3(0, h * 0.55, 0), bend * 0.4 + Vector3(0, h, 0), 0.075, 0.045, Pal.BARK.lightened(0.05), 7)
			kit.tube(bend * 0.9 + Vector3(0, h * 0.62, 0), bend * 0.9 + Vector3(0.55, h * 0.84, 0.25), 0.04, 0.025, Pal.BARK, 5)
			kit.sway = 0.01
			var top := bend * 0.4 + Vector3(0, h, 0)
			kit.rock(Transform3D(Basis.from_scale(Vector3(1.0, 0.3, 1.0)), top + Vector3(0, 0.1, 0)), 1.05, col, 11 + v, 0.14, false)
			kit.rock(Transform3D(Basis.from_scale(Vector3(1.0, 0.3, 1.0)), top + Vector3(0.25, 0.5, 0.1)), 0.7, col.lightened(0.06), 23 + v, 0.14, false)
			kit.rock(Transform3D(Basis.from_scale(Vector3(1.0, 0.32, 1.0)), bend * 0.9 + Vector3(0.62, h * 0.86, 0.28)), 0.52, col.darkened(0.05), 37 + v, 0.14, false)
			if tall:
				kit.rock(Transform3D(Basis.from_scale(Vector3(1.0, 0.32, 1.0)), top + Vector3(-0.2, 0.86, -0.1)), 0.42, col.lightened(0.1), 41 + v, 0.14, false)
			kit.sway = 0.0
			trees.append(kit.commit())
	_meshes["tree"] = trees
	# faceted boulders
	var boulders: Array = []
	for v in 4:
		var kit := MeshKit.new().matte()
		var c := _rock_color(v)
		kit.rock(Transform3D(Basis.from_euler(Vector3(0.1, 0.5 * v, 0.05)) * Basis.from_scale(Vector3(1.15, 0.8, 0.95)), Vector3(0, 0.22, 0)), 0.55, c, 101 + v * 7, 0.24)
		if v % 2 == 1:
			kit.rock(Transform3D(Basis.from_euler(Vector3(0.2, 1.3, 0.1)), Vector3(0.52, 0.1, 0.2)), 0.28, c.darkened(0.05), 131 + v, 0.24)
		if v >= 2:
			kit.rock(Transform3D(Basis.from_euler(Vector3(0.0, 2.1, 0.15)), Vector3(-0.45, 0.08, -0.28)), 0.24, c.lightened(0.04), 151 + v, 0.24)
		boulders.append(kit.commit())
	_meshes["boulder"] = boulders
	var pebbles: Array = []
	for v in 2:
		var kit := MeshKit.new().matte()
		kit.rock(Transform3D(Basis.from_scale(Vector3(1.2, 0.7, 1.0)), Vector3(0, 0.03, 0)), 0.1, _rock_color(v), 201 + v, 0.22)
		kit.rock(Transform3D(Basis.from_scale(Vector3(1.0, 0.7, 1.1)), Vector3(0.2, 0.02, 0.09)), 0.065, _rock_color(v + 1).lightened(0.05), 211 + v, 0.22)
		if v == 1:
			kit.rock(Transform3D(Basis.from_scale(Vector3(1.1, 0.7, 0.9)), Vector3(-0.12, 0.015, -0.16)), 0.05, _rock_color(v).darkened(0.06), 223, 0.22)
		pebbles.append(kit.commit())
	_meshes["pebble"] = pebbles


# ------------------------------------------------------------------ crystals

func _build_crystals(cell: int, nodes: Array) -> void:
	var mat_id := str(planet.config.get("surface_crystal", ""))
	var density := float(_cfg.get("crystal", 0.0)) / 1000.0
	if mat_id == "" or density <= 0.0:
		return
	var mat := GameData.mat_index(mat_id)
	var colors: Array = _cfg.get("crystal_colors", [])
	var max_m := float(_max_mult.get("crystal", 1.0))
	var candidates := int(round(density * _cell_area[cell] * max_m))
	for i in candidates:
		_item(KIND_ID["crystal"], cell, i)
		var dir := _random_in_cell(cell)
		var keep := _rng.randf()
		var size := _rng.randf_range(0.6, 1.5)
		var seed_i := _rng.randi()
		var spin := _rng.randf() * TAU
		if keep * max_m > _mult("crystal", dir):
			continue
		var key := "%s/crystal_c%d_%d" % [geo.id, cell, i]
		if GameState.has_flag(key):
			continue
		var site: Variant = _site(dir, 1.1, spin)
		if site == null:
			continue
		var f := Formation.new()
		f.flag_key = key
		f.setup(mat, int(round(2.0 + size * 2.5)), size, colors, seed_i, false)
		add_child(f)
		f.global_transform = site
		nodes.append(f)
		formation_count += 1


# ------------------------------------------------------------------ landmarks

## Purposeful geology: a ring of standing stones (or basalt columns) on the shoulder of every
## tall dome, and a pair of cairns beside every natural cave mouth.
func _plan_landmarks() -> void:
	var style := str(_cfg.get("landmark", "stones"))
	var idx := 0
	for f in geo.features:
		if str(f["type"]) != "dome" or float(f["height"]) < 18.0:
			continue
		var top: Vector3 = f["dir"]
		var width := acos(clampf(float(f["c0"]), -1.0, 1.0))
		_item(7, 0, idx)
		var bearing := _rng.randf() * TAU
		var t1 := top.cross(Vector3(0.3, 1, 0.2)).normalized()
		var dir := (top * cos(width * 0.55) + t1.rotated(top, bearing) * sin(width * 0.55)).normalized()
		var tt1 := dir.cross(Vector3(0.3, 1, 0.2)).normalized()
		var tt2 := dir.cross(tt1).normalized()
		var n := 5 if style == "stones" else 9
		for j in n:
			_item(9, idx, j)
			var a := TAU * float(j) / float(n) + _rng.randf_range(-0.3, 0.3)
			var dist := (_rng.randf_range(1.6, 3.2) if style == "stones" else _rng.randf_range(0.4, 2.2)) / geo.radius
			var d2 := (dir + (tt1 * cos(a) + tt2 * sin(a)) * dist).normalized()
			var spec := {"kind": style, "dir": d2, "spin": _rng.randf() * TAU,
				"tall": _rng.randf_range(1.6, 3.4) if style == "stones" else _rng.randf_range(0.9, 3.6),
				"tilt": Vector3(_rng.randf_range(-0.12, 0.12), 0, _rng.randf_range(-0.12, 0.12)), "seed": _rng.randi(), "j": j}
			_add_landmark_spec(spec)
		idx += 1
	for c in geo.cavities:
		var mouth: Vector3 = c["entrance"]
		if mouth == Vector3.ZERO:
			continue
		var cdir := mouth.normalized()
		var side := cdir.cross(c["dir"] as Vector3).normalized()
		for s: float in [-1.0, 1.0]:
			_item(8, 0, idx)
			_add_landmark_spec({"kind": "cairn", "dir": (cdir + side * s * (3.6 / geo.radius)).normalized(), "spin": _rng.randf() * TAU, "seed": _rng.randi(), "j": idx})
			idx += 1


func _add_landmark_spec(spec: Dictionary) -> void:
	var cell := cell_of(spec["dir"])
	if not _landmarks_by_cell.has(cell):
		_landmarks_by_cell[cell] = []
	(_landmarks_by_cell[cell] as Array).append(spec)


func _build_landmark(spec: Dictionary) -> Node3D:
	var site: Variant = _site(spec["dir"], 1.6, float(spec["spin"]))
	if site == null:
		return null
	var kit := MeshKit.new().matte()
	var kind := str(spec["kind"])
	var girth := 0.4
	var tall := 1.0
	var rng := RandomNumberGenerator.new()
	rng.seed = int(spec["seed"])
	if kind == "stones":
		tall = float(spec["tall"])
		girth = tall * 0.24
		kit.rock(Transform3D(Basis.from_euler(spec["tilt"]) * Basis.from_scale(Vector3(1.0, tall / (girth * 2.0), 0.75)), Vector3(0, tall * 0.42, 0)), girth, _rock_color(int(spec["j"])), int(spec["seed"]), 0.2)
	elif kind == "columns":
		tall = float(spec["tall"])
		girth = 0.42
		var prof := PackedVector2Array([Vector2(girth, -0.4), Vector2(girth, tall), Vector2(girth * 0.82, tall + 0.07), Vector2(0.0, tall + 0.1)])
		kit.lathe(prof, Transform3D(Basis.from_euler((spec["tilt"] as Vector3) * 0.4), Vector3.ZERO), _rock_color(int(spec["j"])).darkened(0.12), 6, false, true)
	else:
		var y := 0.0
		for k in 3:
			var r := 0.42 - 0.11 * float(k)
			kit.rock(Transform3D(Basis.from_euler(Vector3(0, rng.randf() * TAU, 0)) * Basis.from_scale(Vector3(1.15, 0.62, 1.0)), Vector3(rng.randf_range(-0.05, 0.05), y + r * 0.45, rng.randf_range(-0.05, 0.05))), r, _rock_color(k + int(spec["j"])), rng.randi(), 0.18)
			y += r * 0.86
		tall = y
	var mi := kit.instance(MeshKit.material(), true)
	add_child(mi)
	mi.global_transform = _upright(site, float(spec["spin"]), 0.3 if kind != "cairn" else 0.05)
	var body := StaticBody3D.new()
	body.collision_layer = 4
	body.collision_mask = 0
	var shape := CapsuleShape3D.new()
	shape.radius = girth * 0.8
	shape.height = maxf(tall, shape.radius * 2.0)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = Vector3(0, tall * 0.5, 0)
	body.add_child(cs)
	mi.add_child(body)
	landmark_count += 1
	return mi


# ------------------------------------------------------------------ digging interaction

## Uproots every prop whose base was inside the excavated sphere.
func on_dig(pos: Vector3, radius: float) -> void:
	var reach := radius + 0.4
	var removed := 0
	var cos_cell := cos((reach + CELL_TARGET) / geo.radius)
	var d := pos.normalized()
	for cell: int in _cells:
		if _centers[cell].dot(d) < cos_cell:
			continue
		for it: Dictionary in _cells[cell]["items"]:
			if it.get("gone", false):
				continue
			if (it["pos"] as Vector3).distance_to(pos) < reach:
				if it.has("landmark"):
					if is_instance_valid(it["body"]):
						world.fx.dig_burst(it["pos"], planet.up_at(it["pos"]), Pal.ROCK, 1.2, true)
						(it["body"] as Node).queue_free()
					it["gone"] = true
					landmark_count -= 1
				else:
					_remove_item(it)
					prop_count -= 1
				removed += 1
	if removed > 0 and not _foliage.is_empty():
		world.fx.dig_burst(pos, planet.up_at(pos), _foliage[0].darkened(0.1), 0.4, false)
	for child in get_children():
		if child is Formation and (child as Formation).global_position.distance_to(pos) < radius:
			# ground dug away beneath a crystal: let it settle onto the new floor
			var f := child as Formation
			var up := planet.up_at(f.global_position)
			f.global_position = planet.ground_point(up, f.global_position.length() + 0.5)


## Every live (not uprooted) item in the built cells: {pos, mm, i, body, layer[, landmark]}.
## With `landmarks_only`, just the landmark stones / cairns.
func live_items(landmarks_only := false) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for cell: int in _cells:
		for it: Dictionary in _cells[cell]["items"]:
			if it.get("gone", false) or (landmarks_only and not it.has("landmark")):
				continue
			out.append(it)
	return out


## Live props within `radius` of `pos` (tests and tools).
func props_near(pos: Vector3, radius: float) -> int:
	var n := 0
	for cell: int in _cells:
		for it: Dictionary in _cells[cell]["items"]:
			if not it.get("gone", false) and (it["pos"] as Vector3).distance_to(pos) < radius:
				n += 1
	return n
