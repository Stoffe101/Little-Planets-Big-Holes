class_name RobotManager
extends Node3D
## Helper bots ("Scoopy"): hovering drones that collect loose chunks the player left behind
## and haul them to the Depot, selling them automatically. They never dig, so the player
## still drives the excavation - bots just remove the walking-back-and-forth.
##
## Bots hover (no ground pathfinding), steer along the planet's curve and stay out of rock by
## sampling the voxel SDF, so they cannot get permanently stuck on rough terrain.

enum State { IDLE, SEEK, RETURN, UNLOAD }

const HOVER_HEIGHT := 2.4
const GRAB_DISTANCE := 0.9
const SEEK_TIMEOUT := 14.0
const PLAYER_AVOID := 3.0          ## don't snatch chunks right at the player's feet

var world: World
var bots: Array[Dictionary] = []
var _time := 0.0
var earned_total := 0


func setup(w: World) -> void:
	world = w
	GameState.gear_changed.connect(_on_gear_changed)
	_sync_count()


func _on_gear_changed(id: String) -> void:
	if id == "robot" or id == "":
		_sync_count()


func _sync_count() -> void:
	var want := int(GameState.gear_value("robot"))
	while bots.size() < want:
		_spawn(bots.size())
	while bots.size() > want:
		var b: Dictionary = bots.pop_back()
		(b["node"] as Node3D).queue_free()


func _dock() -> Vector3:
	if world.base != null:
		return world.base.get("dock_position")
	return world.planet.geology.spawn_position() + world.planet.geology.landing_dir * 2.0


func _hopper() -> Vector3:
	if world.base != null:
		return world.base.call("hopper_position")
	return _dock()


func _spawn(index: int) -> void:
	var node := Node3D.new()
	node.name = "Scoopy_%d" % index
	add_child(node)
	# Scoopy: a compact hover drone in the outpost's livery. Bevelled hull, a visor strip that
	# reads as a face without being a cartoon, two cargo arms and one downward thruster.
	var stripe: Color = [Pal.AMBER, Pal.TEAL, Pal.STEEL_BLUE][index % 3]
	var kit := MeshKit.new().paint()
	kit.block(Vector3(0, 0.02, 0), Vector3(0.62, 0.36, 0.56), Pal.HULL, 0.11)
	kit.block(Vector3(0, 0.02, 0), Vector3(0.628, 0.06, 0.566), stripe, 0.02)
	kit.cast()
	kit.block(Vector3(0, -0.17, 0), Vector3(0.46, 0.1, 0.42), Pal.GRAPHITE, 0.04)
	kit.rubber()
	kit.block(Vector3(0, 0.07, 0.275), Vector3(0.4, 0.13, 0.03), Pal.CHARCOAL, 0.012)
	kit.surf(0.25).set_emission(1.6)
	for sx: float in [-1.0, 1.0]:
		kit.block(Vector3(0.09 * sx, 0.075, 0.292), Vector3(0.07, 0.05, 0.008), Pal.TEAL, 0.004)
	kit.set_emission(0.0)
	kit.bare()
	kit.tube(Vector3(0.14, 0.2, -0.1), Vector3(0.17, 0.44, -0.13), 0.01, 0.007, Pal.STEEL_DARK, 5)
	kit.surf(0.25).set_emission(1.8)
	kit.sphere(Vector3(0.17, 0.45, -0.13), 0.022, stripe, Vector3.ONE, 6, 4)
	kit.set_emission(0.0)
	# cargo arms with small scoops
	for sx2: float in [-1.0, 1.0]:
		kit.bare()
		kit.tube(Vector3(0.3 * sx2, -0.08, 0.1), Vector3(0.4 * sx2, -0.3, 0.24), 0.022, 0.018, Pal.STEEL_DARK, 6)
		kit.paint()
		kit.hbox(Transform3D(Basis.from_euler(Vector3(0.5, 0, 0)), Vector3(0.4 * sx2, -0.36, 0.28)), Vector3(0.14, 0.03, 0.18), Pal.AMBER, 0.01)
	# thruster nozzle
	kit.cast()
	kit.lathe(PackedVector2Array([Vector2(0.12, -0.22), Vector2(0.17, -0.34), Vector2(0.15, -0.34), Vector2(0.1, -0.24)]), Transform3D.IDENTITY, Pal.STEEL_DARK, 12)
	node.add_child(kit.instance())
	var glow := MeshKit.new().surf(0.3)
	glow.emission = 2.0
	glow.lathe(PackedVector2Array([Vector2(0.0, -0.36), Vector2(0.11, -0.3), Vector2(0.0, -0.28)]), Transform3D.IDENTITY, Pal.TEAL, 10, true)
	var glow_node := glow.instance(MeshKit.material(), false)
	glow_node.name = "Glow"
	node.add_child(glow_node)
	var cargo := MeshInstance3D.new()
	cargo.name = "Cargo"
	cargo.material_override = MeshKit.material()
	cargo.position = Vector3(0, -0.42, 0.3)
	cargo.scale = Vector3.ONE * 0.2
	cargo.visible = false
	node.add_child(cargo)
	var light := OmniLight3D.new()
	light.light_color = Pal.TEAL
	light.light_energy = 0.35
	light.omni_range = 3.0
	light.position = Vector3(0, -0.4, 0)
	node.add_child(light)
	var start := _dock() + world.planet.up_at(_dock()) * (0.6 * index)
	node.global_position = start
	bots.append({"node": node, "state": State.IDLE, "pos": start, "vel": Vector3.ZERO, "target": {}, "cargo": {},
		"load": 0, "timer": 0.0, "idle": randf() * 2.0, "phase": randf() * TAU, "facing": Vector3.FORWARD})


func capacity() -> int:
	return int(GameState.gear_value("robot_cargo"))


func speed() -> float:
	return float(GameState.gear_value("robot_speed"))


func _physics_process(delta: float) -> void:
	if world == null or world.planet == null or not world.planet.is_loaded:
		return
	_time += delta
	for b in bots:
		_tick(b, delta)


func _tick(b: Dictionary, delta: float) -> void:
	var planet := world.planet
	var pos: Vector3 = b["pos"]
	var state: int = b["state"]
	var goal := pos
	var hover := HOVER_HEIGHT
	match state:
		State.IDLE:
			goal = _dock() + planet.up_at(_dock()) * (0.4 + 0.6 * bots.find(b))
			hover = 0.0
			b["idle"] = float(b["idle"]) - delta
			if float(b["idle"]) <= 0.0:
				b["idle"] = 1.2
				if int(b["load"]) > 0 and int(b["load"]) >= capacity():
					b["state"] = State.RETURN
				else:
					var avoid := world.player.global_position if world.player != null else Vector3.ZERO
					var it: Dictionary = world.pickups.claim_nearest(pos, 400.0, avoid, PLAYER_AVOID)
					if not it.is_empty():
						b["target"] = it
						b["state"] = State.SEEK
						b["timer"] = SEEK_TIMEOUT
					elif int(b["load"]) > 0:
						b["state"] = State.RETURN
		State.SEEK:
			var it2: Dictionary = b["target"]
			if it2.is_empty() or not world.pickups.items.has(it2):
				b["target"] = {}
				b["state"] = State.IDLE
				b["idle"] = 0.1
			else:
				var tp: Vector3 = it2["pos"]
				goal = tp
				# hover over to it, then dip down once roughly above
				var lateral := (tp - pos) - planet.up_at(pos) * (tp - pos).dot(planet.up_at(pos))
				hover = HOVER_HEIGHT if lateral.length() > 1.6 else 0.35
				b["timer"] = float(b["timer"]) - delta
				if pos.distance_to(tp) < GRAB_DISTANCE:
					var got: Array = world.pickups.take(it2)
					if int(got[0]) >= 0:
						var cargo: Dictionary = b["cargo"]
						cargo[int(got[0])] = int(cargo.get(int(got[0]), 0)) + int(got[1])
						b["load"] = int(b["load"]) + int(got[1])
						_show_cargo(b, int(got[0]))
						Audio.play_at("collect", pos, -8.0, 1.3, 0.1)
					b["target"] = {}
					b["state"] = State.RETURN if int(b["load"]) >= capacity() else State.IDLE
					b["idle"] = 0.05
				elif float(b["timer"]) <= 0.0:
					# could not reach it (probably inside a sealed tunnel): give it back
					world.pickups.unclaim(it2)
					it2["retry"] = 20.0
					b["target"] = {}
					b["state"] = State.IDLE
					b["idle"] = 1.0
		State.RETURN:
			goal = _hopper()
			var lateral2 := (goal - pos) - planet.up_at(pos) * (goal - pos).dot(planet.up_at(pos))
			hover = HOVER_HEIGHT if lateral2.length() > 2.0 else 0.6
			if pos.distance_to(goal) < 1.6:
				b["state"] = State.UNLOAD
				b["timer"] = 0.5
		State.UNLOAD:
			goal = _hopper()
			hover = 0.6
			b["timer"] = float(b["timer"]) - delta
			if float(b["timer"]) <= 0.0:
				var total := 0
				var cargo2: Dictionary = b["cargo"]
				for m: int in cargo2:
					total += GameState.sell_units(GameData.mat_id(m), int(cargo2[m]), false)
				if total > 0:
					earned_total += total
					GameState.add_stat("robot_earned", total)
					if world.base != null:
						world.base.call("feed_hopper", total, 0.0)
				b["cargo"] = {}
				b["load"] = 0
				(b["node"] as Node3D).get_node("Cargo").visible = false
				b["state"] = State.IDLE
				b["idle"] = 0.4
	_move(b, goal, hover, delta)


func _show_cargo(b: Dictionary, mat: int) -> void:
	var cargo := (b["node"] as Node3D).get_node("Cargo") as MeshInstance3D
	cargo.mesh = world.pickups._mesh_for(mat)
	cargo.visible = true


## Hover steering: follow the planet's curve towards `goal`, keeping `hover` metres of clearance.
func _move(b: Dictionary, goal: Vector3, hover: float, delta: float) -> void:
	var planet := world.planet
	var pos: Vector3 = b["pos"]
	var up := planet.up_at(pos)
	var to := goal - pos
	var lateral := to - up * to.dot(up)
	var want := Vector3.ZERO
	if lateral.length() > 0.3:
		want = lateral.normalized() * speed() * clampf(lateral.length() / 3.0, 0.25, 1.0)
	# altitude: target radius is the goal's radius plus hover, but never inside the ground
	var ground_r := _ground_radius(pos)
	var target_r := maxf(goal.length() + hover, ground_r + (0.5 if hover < 1.0 and lateral.length() < 1.6 else 1.4))
	if hover <= 0.0 and lateral.length() < 1.0:
		target_r = goal.length()
	var dr := target_r - pos.length()
	want += up * clampf(dr * 3.0, -speed(), speed())
	var vel: Vector3 = (b["vel"] as Vector3).lerp(want, clampf(delta * 4.0, 0.0, 1.0))
	var next := pos + vel * delta
	# never fly into rock: if the next spot is solid, slide upwards instead
	if planet.sdf_at(next) < 0.0:
		next = pos + up * speed() * delta
		vel = up * speed() * 0.5
	b["vel"] = vel
	b["pos"] = next
	var node: Node3D = b["node"]
	var bob := sin(_time * 3.0 + float(b["phase"])) * 0.08
	node.global_position = next + up * bob
	var facing: Vector3 = b["facing"]
	if lateral.length() > 0.5:
		facing = facing.slerp(lateral.normalized(), clampf(delta * 5.0, 0.0, 1.0)) if facing.dot(lateral.normalized()) > -0.99 else lateral.normalized()
	facing = (facing - up * facing.dot(up))
	if facing.length() < 0.01:
		facing = up.cross(Vector3.RIGHT)
	facing = facing.normalized()
	b["facing"] = facing
	var right := up.cross(facing).normalized()
	node.global_basis = Basis(right, up, facing).rotated(right, clampf(vel.dot(facing) * 0.03, -0.3, 0.3))
	var glow := node.get_node("Glow") as Node3D
	glow.scale = Vector3.ONE * (0.8 + 0.5 * clampf(vel.length() / speed(), 0.0, 1.0) + 0.1 * sin(_time * 20.0))


## Radius of the ground directly below `pos` (a few SDF samples downwards).
func _ground_radius(pos: Vector3) -> float:
	var planet := world.planet
	var up := planet.up_at(pos)
	var r := pos.length()
	var d := 0.0
	while d < 12.0:
		if planet.sdf_at(up * (r - d)) < 0.0:
			return r - d
		d += 0.75
	return r - 12.0
