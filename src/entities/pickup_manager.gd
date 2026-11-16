class_name PickupManager
extends Node3D
## Loose resource chunks: pop out of digs, tumble under planet gravity (collision is resolved
## against the voxel SDF - no rigid bodies), then get magnetised into the player's backpack,
## slurped by the vacuum, or carried off by helper bots.

signal collected(material_index: int, units: int, world_pos: Vector3)
signal spawned(material_index: int, units: int)

enum State { FLYING, RESTING, ATTRACT, CLAIMED }

const MAX_ACTIVE := 360
const COLLECT_DISTANCE := 0.55
const SPAWN_GRACE := 0.28          ## seconds before a fresh chunk can be magnetised (so you see it pop)

var planet: Planet
var player: Player
var items: Array[Dictionary] = []
var _meshes: Dictionary = {}       ## material index -> ArrayMesh
var _pool: Array[MeshInstance3D] = []
var _tick := 0
var magnet_enabled := true


func setup(p: Planet, pl: Player) -> void:
	planet = p
	player = pl


func count() -> int:
	return items.size()


func total_units() -> int:
	var n := 0
	for it in items:
		n += int(it["units"])
	return n


func clear() -> void:
	for it in items:
		_release(it["node"])
	items.clear()


# ------------------------------------------------------------------ meshes

func _mesh_for(mat: int) -> ArrayMesh:
	if _meshes.has(mat):
		return _meshes[mat]
	var def := GameData.materials[mat]
	var c1: Color = def["color_c"]
	var c2: Color = def["color2_c"]
	var kit := MeshKit.new()
	# Chunks are small faceted pieces of the real thing: dull clods and stones, ore as host
	# rock carrying bright nuggets, crystals as glossy shards. Value reads from finish, not glow.
	match str(def["category"]):
		"soil":
			kit.matte()
			kit.rock(Transform3D(Basis.from_scale(Vector3(1.0, 0.8, 0.9)), Vector3.ZERO), 1.0, c1, mat * 7 + 1, 0.18, false)
			kit.rock(Transform3D.IDENTITY.translated(Vector3(0.6, 0.25, 0.1)), 0.55, c2, mat * 7 + 2, 0.18, false)
		"rock":
			kit.matte()
			kit.rock(Transform3D(Basis.from_scale(Vector3(1.1, 0.85, 0.95)), Vector3.ZERO), 1.05, c1, mat * 7 + 1, 0.26, false)
			kit.rock(Transform3D.IDENTITY.translated(Vector3(0.55, 0.3, 0.2)), 0.5, c2, mat * 7 + 2, 0.26, false)
		"ore":
			kit.matte()
			kit.rock(Transform3D(Basis.from_scale(Vector3(1.05, 0.85, 0.95)), Vector3.ZERO), 0.95, Pal.ROCK_DARK, mat * 7 + 1, 0.24, false)
			kit.surf(0.32, 0.8)
			kit.emission = float(def.get("emission", 0.0)) * 0.5
			kit.rock(Transform3D.IDENTITY.translated(Vector3(0.42, 0.32, 0.25)), 0.62, c1, mat * 7 + 2, 0.2, false)
			kit.rock(Transform3D.IDENTITY.translated(Vector3(-0.45, 0.2, -0.3)), 0.5, c2, mat * 7 + 3, 0.2, false)
			kit.rock(Transform3D.IDENTITY.translated(Vector3(0.05, -0.3, 0.55)), 0.4, c1, mat * 7 + 4, 0.2, false)
		_:
			kit.gloss()
			kit.emission = clampf(float(def.get("emission", 0.0)) * 0.6, 0.02, 0.4)
			kit.crystal(Vector3(0, -0.8, 0), Vector3(0, 1.3, 0), 0.5, c1, 6, 0.75)
			kit.crystal(Vector3(0.2, -0.6, 0.1), Vector3(0.9, 0.7, 0.3), 0.3, c2, 6, 0.7)
			kit.crystal(Vector3(-0.2, -0.6, -0.1), Vector3(-0.7, 0.6, -0.4), 0.26, c1.lightened(0.15), 6, 0.7)
	var mesh := kit.commit()
	_meshes[mat] = mesh
	return mesh


func _acquire() -> MeshInstance3D:
	if not _pool.is_empty():
		var n: MeshInstance3D = _pool.pop_back()
		n.visible = true
		return n
	var mi := MeshInstance3D.new()
	mi.material_override = MeshKit.material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func _release(node: MeshInstance3D) -> void:
	node.visible = false
	_pool.append(node)


# ------------------------------------------------------------------ spawning

func spawn(mat: int, units: int, pos: Vector3, vel: Vector3) -> void:
	if units <= 0:
		return
	if items.size() >= MAX_ACTIVE:
		# Fold into an existing chunk of the same material instead of dropping loot.
		for it in items:
			if int(it["mat"]) == mat and int(it["state"]) != State.CLAIMED:
				it["units"] = int(it["units"]) + units
				_apply_scale(it)
				return
		var old: Dictionary = items.pop_front()
		_release(old["node"])
	var node := _acquire()
	node.mesh = _mesh_for(mat)
	var it := {"node": node, "mat": mat, "units": units, "pos": pos, "vel": vel, "state": State.FLYING,
		"age": 0.0, "spin": Vector3(randf_range(-6, 6), randf_range(-6, 6), randf_range(-6, 6)),
		"retry": 0.0, "bob": randf() * TAU}
	node.global_position = pos
	node.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
	node.reset_physics_interpolation()
	_apply_scale(it)
	items.append(it)
	spawned.emit(mat, units)


func _apply_scale(it: Dictionary) -> void:
	var s := clampf(0.13 + 0.045 * sqrt(float(it["units"])), 0.14, 0.42)
	(it["node"] as MeshInstance3D).scale = Vector3.ONE * s
	it["size"] = s


## Turns dig yields into a handful of chunks bursting out of `center` towards `toward`.
func burst(yields: Dictionary, center: Vector3, toward: Vector3, spread_radius: float, max_chunks := 7) -> void:
	if yields.is_empty():
		return
	var up := planet.up_at(center)
	var pieces: Array = []      # [mat, units]
	for m: int in yields:
		var units := int(yields[m])
		var n := clampi(int(ceil(float(units) / 3.0)), 1, 4)
		var each := units / n
		var extra := units % n
		for i in n:
			pieces.append([m, each + (1 if i < extra else 0)])
	# Too many chunks: merge the smallest piles of the same material.
	while pieces.size() > max_chunks:
		pieces.sort_custom(func(a: Array, b: Array) -> bool: return int(a[1]) < int(b[1]))
		var small: Array = pieces.pop_front()
		var merged := false
		for p: Array in pieces:
			if int(p[0]) == int(small[0]):
				p[1] = int(p[1]) + int(small[1])
				merged = true
				break
		if not merged:
			pieces[0][1] = int(pieces[0][1])   # different material: keep it as its own chunk
			pieces.append(small)
			break
	for p: Array in pieces:
		if int(p[1]) <= 0:
			continue
		var rnd := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1))
		var pos := center + rnd * spread_radius * 0.35
		var vel := toward * randf_range(1.5, 3.2) + up * randf_range(3.0, 5.5) + rnd * 1.6
		spawn(int(p[0]), int(p[1]), pos, vel)


# ------------------------------------------------------------------ simulation

func _physics_process(delta: float) -> void:
	if planet == null or not planet.is_loaded:
		return
	_tick += 1
	var has_player := player != null and is_instance_valid(player)
	var chest := Vector3.ZERO
	var radius := 0.0
	var can_take := false
	if has_player:
		chest = player.global_position + player.up * 0.9
		radius = float(GameState.gear_value("magnet"))
		can_take = magnet_enabled and not GameState.is_full()
	var r2 := radius * radius
	var i := items.size() - 1
	while i >= 0:
		var it := items[i]
		var node: MeshInstance3D = it["node"]
		var state: int = it["state"]
		var pos: Vector3 = it["pos"]
		it["age"] = float(it["age"]) + delta
		if float(it["retry"]) > 0.0:
			it["retry"] = float(it["retry"]) - delta
		match state:
			State.FLYING:
				var vel: Vector3 = it["vel"]
				vel += planet.gravity_at(pos) * delta
				var next := pos + vel * delta
				if planet.sdf_at(next) < 0.0:
					var n := _sdf_normal(next)
					vel = vel.bounce(n) * 0.36
					next = pos
					if vel.length() < 1.4:
						it["state"] = State.RESTING
						vel = Vector3.ZERO
				it["vel"] = vel
				it["pos"] = next
				pos = next
				node.rotation += (it["spin"] as Vector3) * delta
				if pos.length() > planet.geology.max_surface_radius() + 60.0:
					# flung into space: bring it home
					it["pos"] = planet.ground_point(planet.up_at(pos)) + planet.up_at(pos) * 0.5
					it["vel"] = Vector3.ZERO
			State.RESTING:
				# Occasionally check the ground is still there (it may have been dug away).
				if (_tick + i) % 20 == 0:
					if planet.sdf_at(pos - planet.up_at(pos) * 0.45) >= 0.0:
						it["state"] = State.FLYING
				it["bob"] = float(it["bob"]) + delta * 2.2
			State.ATTRACT:
				if not has_player:
					it["state"] = State.FLYING
				else:
					var to := chest - pos
					var d := to.length()
					var speed := minf(7.0 + float(it["age"]) * 3.0 + (10.0 / maxf(d, 0.5)) * 6.0, 46.0)
					var vel2: Vector3 = (it["vel"] as Vector3).lerp(to / maxf(d, 0.001) * speed, clampf(delta * 9.0, 0.0, 1.0))
					it["vel"] = vel2
					pos += vel2 * delta
					it["pos"] = pos
					node.rotation += (it["spin"] as Vector3) * delta * 1.6
					if d < COLLECT_DISTANCE or to.dot(vel2) < 0.0 and d < 1.2:
						if _try_collect(it):
							_release(node)
							items.remove_at(i)
							i -= 1
							continue
			State.CLAIMED:
				pass
		# magnet
		if can_take and (state == State.RESTING or state == State.FLYING) and float(it["age"]) > SPAWN_GRACE and float(it["retry"]) <= 0.0:
			if pos.distance_squared_to(chest) < r2:
				it["state"] = State.ATTRACT
				it["age"] = 0.0
		if state != State.CLAIMED:
			var visual := pos
			if state == State.RESTING:
				visual += planet.up_at(pos) * (float(it["size"]) * 0.6 + sin(float(it["bob"])) * 0.035)
			node.global_position = visual
		i -= 1


func _sdf_normal(p: Vector3) -> Vector3:
	var e := planet.geology.voxel_size
	var n := Vector3(
		planet.sdf_at(p + Vector3(e, 0, 0)) - planet.sdf_at(p - Vector3(e, 0, 0)),
		planet.sdf_at(p + Vector3(0, e, 0)) - planet.sdf_at(p - Vector3(0, e, 0)),
		planet.sdf_at(p + Vector3(0, 0, e)) - planet.sdf_at(p - Vector3(0, 0, e)))
	if n.length() < 0.0001:
		return planet.up_at(p)
	return n.normalized()


func _try_collect(it: Dictionary) -> bool:
	var mat: int = it["mat"]
	var units: int = it["units"]
	var accepted := GameState.add_to_inventory(GameData.mat_id(mat), units)
	if accepted <= 0:
		it["state"] = State.FLYING
		it["retry"] = 1.5
		it["vel"] = Vector3.ZERO
		return false
	collected.emit(mat, accepted, it["pos"])
	if accepted < units:
		it["units"] = units - accepted
		_apply_scale(it)
		it["state"] = State.FLYING
		it["retry"] = 1.5
		it["vel"] = Vector3.ZERO
		return false
	return true


# ------------------------------------------------------------------ vacuum & robots

## Pulls every chunk inside a cone towards the player. Returns how many are being pulled.
func vacuum(origin: Vector3, dir: Vector3, max_range: float, cone_deg: float) -> int:
	if GameState.is_full():
		return 0
	var cos_cone := cos(deg_to_rad(cone_deg))
	var n := 0
	for it in items:
		var st: int = it["state"]
		if st == State.CLAIMED or float(it["retry"]) > 0.0:
			continue
		var to: Vector3 = (it["pos"] as Vector3) - origin
		var d := to.length()
		if d > max_range:
			continue
		if d > 1.5 and to.dot(dir) / d < cos_cone:
			continue
		if st != State.ATTRACT:
			it["state"] = State.ATTRACT
			it["age"] = 0.4
		n += 1
	return n


## Nearest free chunk for a helper bot, or {} if none. The chunk is marked as claimed.
func claim_nearest(pos: Vector3, max_dist: float, avoid: Vector3, avoid_radius: float) -> Dictionary:
	var best: Dictionary = {}
	var best_d := max_dist * max_dist
	for it in items:
		var st: int = it["state"]
		if st != State.RESTING:
			continue
		var p: Vector3 = it["pos"]
		if p.distance_squared_to(avoid) < avoid_radius * avoid_radius:
			continue
		var d := p.distance_squared_to(pos)
		if d < best_d:
			best_d = d
			best = it
	if not best.is_empty():
		best["state"] = State.CLAIMED
	return best


func unclaim(it: Dictionary) -> void:
	if items.has(it) and int(it["state"]) == State.CLAIMED:
		it["state"] = State.RESTING


## Removes a claimed chunk from the world and returns [material index, units].
func take(it: Dictionary) -> Array:
	var idx := items.find(it)
	if idx < 0:
		return [-1, 0]
	_release(it["node"])
	items.remove_at(idx)
	return [int(it["mat"]), int(it["units"])]
