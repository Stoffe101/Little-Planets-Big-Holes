class_name AutoBorer
extends Node3D
## The Auto-Borer: a deployable tripod rig that sinks a real shaft straight down through the
## voxel terrain (via DigSystem, like every other edit) and lifts the spoil to the surface as
## loose chunks for you or the helper bots to collect. Unlocked by the Fossilised Drill Bit;
## its gear level sets how deep it can go and how hard a rock it can cut.
##
## It only works where the terrain is loaded at full resolution - wander more than ~60 m away
## and it pauses until you come back. One rig per planet; G deploys it at your feet (or packs it
## up when you stand next to it). State is kept in GameState.flags, so it survives saves.

signal state_changed(state: String)

const STEP := 0.5                ## metres per bite
const BITE_RADIUS := 1.15
const INTERVAL := 0.45           ## seconds between bites
const PACK_DISTANCE := 5.0

var world: World
var deployed := false
var pos := Vector3.ZERO          ## where the rig stands (surface point)
var up := Vector3.UP
var depth := 0.0                 ## how far down the shaft is
var state := "idle"              ## idle / running / paused / stalled / done
var stall_reason := ""
var _timer := 0.0
var _spin := 0.0
var _rig: Node3D
var _head: Node3D
var _string: Node3D
var _lamp_mat: ShaderMaterial
var _lamp_col := Color(0, 0, 0, 0)


func setup(w: World) -> void:
	world = w
	var saved: Variant = GameState.flags.get(_key(), null)
	if saved is Dictionary:
		var d: Dictionary = saved
		var p: Array = d.get("pos", [])
		if p.size() == 3:
			_place(Vector3(float(p[0]), float(p[1]), float(p[2])))
			depth = float(d.get("depth", 0.0))
			state = str(d.get("state", "running"))
			_update_visual()


func _key() -> String:
	return "borer/%s" % world.planet_id


static func max_depth() -> float:
	return float(GameState.gear_value("borer"))


static func power() -> int:
	return 2 + GameState.gear_level("borer")


func _save() -> void:
	if deployed:
		GameState.flags[_key()] = {"pos": [pos.x, pos.y, pos.z], "depth": depth, "state": state}
	else:
		GameState.flags.erase(_key())


## G: deploy at the player's feet, or pack up when standing next to the rig.
func toggle() -> void:
	if GameState.gear_level("borer") <= 0:
		world.message.emit("No Auto-Borer yet - the Outfitter can build one once you know how", "hint")
		return
	var p := world.player.global_position
	if deployed:
		if p.distance_to(pos) < PACK_DISTANCE:
			pack_up()
		else:
			world.message.emit("Your Auto-Borer is %d m away, %d m down" % [int(world.nav.surface_distance(p, pos)), int(depth)], "hint")
		return
	var ground := world.planet.ground_point(world.player.up, p.length() + 0.5)
	var spot := ground + world.player.up * 0.02 - world.player.camera.global_basis.z.slide(world.player.up).normalized() * 2.2
	spot = world.planet.ground_point(spot.normalized(), spot.length() + 1.5)
	if world.is_protected(spot - spot.normalized() * 1.0):
		world.message.emit("Not on shielded ground - set the borer up away from the outpost", "hint")
		return
	if not world.planet.is_area_ready(spot, 3.0):
		world.message.emit("The ground here is still being surveyed", "hint")
		return
	deploy(spot)


func deploy(at: Vector3) -> void:
	_place(at)
	depth = 0.0
	state = "running"
	stall_reason = ""
	_save()
	_update_visual()
	Audio.play_at("equip", at, -2.0, 0.8)
	world.message.emit("Auto-Borer set up: it will sink a shaft to %d m" % int(max_depth()), "hint")
	state_changed.emit(state)


func pack_up() -> void:
	if not deployed:
		return
	deployed = false
	state = "idle"
	if _rig != null:
		_rig.queue_free()
		_rig = null
	_save()
	Audio.play("equip", -4.0, 1.2)
	world.message.emit("Auto-Borer packed up", "hint")
	state_changed.emit(state)


func _place(at: Vector3) -> void:
	deployed = true
	pos = at
	up = world.planet.up_at(at)
	if _rig != null:
		_rig.queue_free()
	_build_rig()


func _process(delta: float) -> void:
	if not deployed or world == null or not world.is_ready:
		return
	_spin += delta * (9.0 if state == "running" else 0.0)
	if _head != null:
		_head.rotation.y = _spin
	if state in ["stalled", "done"]:
		return
	# the rig only works inside the streamed, editable area
	var bite := pos - up * (depth + STEP + 0.4)
	var ready := world.planet.is_area_ready(bite, BITE_RADIUS + 1.0)
	var want := "running" if ready else "paused"
	if want != state:
		state = want
		_update_visual()
		state_changed.emit(state)
	if state != "running":
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = INTERVAL
	_bite()


## One step down the shaft. Returns the DigSystem result.
func _bite() -> Dictionary:
	var center := pos - up * (depth + STEP)
	var res := world.dig.dig_sphere(center, BITE_RADIUS, power())
	if bool(res.get("unloaded", false)):
		return res
	if bool(res.get("blocked", false)):
		state = "stalled"
		var hm := int(res.get("hard_material", -1))
		stall_reason = str(GameData.materials[hm]["name"]) if hm >= 0 else "rock"
		world.message.emit("Auto-Borer stalled at %d m: %s is too hard for it" % [int(depth), stall_reason], "hint")
		_update_visual()
		state_changed.emit(state)
		_save()
		return res
	depth += STEP
	if bool(res.get("ok", false)):
		var mouth := pos + up * 1.1
		world.pickups.burst(res["yields"], mouth, up, 0.9, 3)
		world.on_dig(res, center)
		GameState.add_stat("borer_metres", STEP)
		Audio.play_at("dig_stone" if depth > 8.0 else "dig_soft", pos, -10.0, 0.8)
	if depth >= max_depth():
		depth = max_depth()
		state = "done"
		world.message.emit("Auto-Borer reached %d m - the shaft is open" % int(depth), "hint")
		state_changed.emit(state)
	_update_visual()
	_save()
	return res


# ------------------------------------------------------------------ model

func _build_rig() -> void:
	_rig = Node3D.new()
	_rig.name = "AutoBorer"
	add_child(_rig)
	var x := up.cross(Vector3(0.3, 0.1, 0.9)).normalized()
	_rig.global_transform = Transform3D(Basis(x, up, x.cross(up).normalized()), pos)
	var kit := MeshKit.new()
	# three splayed legs on round feet
	for k in 3:
		var a := TAU * float(k) / 3.0
		var foot := Vector3(cos(a), 0.0, sin(a)) * 1.55
		kit.cast()
		kit.tube(foot, Vector3(0, 2.6, 0), 0.06, 0.045, Pal.BRONZE, 8)
		kit.rubber()
		kit.disc(Transform3D(Basis.IDENTITY, foot - Vector3(0, 0.05, 0)), 0.2, 0.0, 0.08, Pal.BRONZE, 10)
		kit.bare()
		kit.tube(foot * 0.55 + Vector3(0, 1.2, 0), foot * 0.2 + Vector3(0, 2.2, 0), 0.03, 0.03, Pal.COPPER, 6)
	# crown block and enamel winch drum
	kit.cast()
	kit.turned(Vector3(0, 2.55, 0), Vector3(0, 2.8, 0), PackedVector2Array([Vector2(0.3, 0.0), Vector2(0.3, 0.25)]), Pal.BRONZE, 14)
	kit.paint()
	kit.turned(Vector3(-0.45, 2.95, 0), Vector3(0.45, 2.95, 0), PackedVector2Array([Vector2(0.28, 0.0), Vector2(0.28, 0.9)]), Pal.ENAMEL, 16)
	kit.cast()
	for sx: float in [-0.46, 0.46]:
		kit.turned(Vector3(sx, 2.95, 0), Vector3(sx + signf(sx) * 0.05, 2.95, 0), PackedVector2Array([Vector2(0.32, 0.0), Vector2(0.32, 0.05)]), Pal.BRONZE, 16)
	kit.gloss()
	kit.turned(Vector3(-0.2, 2.95, 0), Vector3(0.2, 2.95, 0), PackedVector2Array([Vector2(0.282, 0.0), Vector2(0.282, 0.4)]), Pal.CREAM, 16)
	# motor housing with a round vent
	kit.paint()
	kit.turned(Vector3(0, 2.8, -0.45), Vector3(0, 2.8, -0.95), PackedVector2Array([Vector2(0.22, 0.0), Vector2(0.22, 0.45), Vector2(0.16, 0.5)]), Pal.ENAMEL_SHADE, 14)
	# collar where the string enters the ground
	kit.cast()
	kit.disc(Transform3D(Basis.IDENTITY, Vector3(0, 0.02, 0)), 0.55, 0.2, 0.1, Pal.BRONZE, 16)
	_rig.add_child(kit.instance())
	var lamp := MeshKit.new().surf(0.3)
	lamp.set_emission(1.0)
	lamp.sphere(Vector3(0, 3.3, 0), 0.08, Color.WHITE, Vector3.ONE, 8, 5)
	_lamp_mat = MeshKit.new_material(1.6)
	_rig.add_child(lamp.instance(_lamp_mat, false))
	# drill string (scaled to the depth) and the cutting head
	_string = Node3D.new()
	_rig.add_child(_string)
	var sk := MeshKit.new().bare()
	sk.tube(Vector3.ZERO, Vector3(0, -1.0, 0), 0.07, 0.07, Pal.STEEL, 8)
	_string.add_child(sk.instance())
	_string.position = Vector3(0, 2.6, 0)
	_head = Node3D.new()
	_rig.add_child(_head)
	var hk := MeshKit.new().cast()
	hk.turned(Vector3(0, 0.3, 0), Vector3(0, -0.5, 0), PackedVector2Array([Vector2(0.95, 0.0), Vector2(0.95, 0.25), Vector2(0.6, 0.6), Vector2(0.0, 0.8)]), Pal.STEEL_DARK, 12, false, true)
	hk.bare()
	for k in 6:
		var a := TAU * float(k) / 6.0
		hk.cone(Vector3(cos(a), 0, sin(a)) * 0.7 + Vector3(0, -0.15, 0), Vector3(cos(a), 0, sin(a)) * 0.8 + Vector3(0, -0.4, 0), 0.08, Pal.STEEL, 6)
	_head.add_child(hk.instance())
	var body := StaticBody3D.new()
	body.collision_layer = 4 | 8
	body.collision_mask = 0
	var shape := CylinderShape3D.new()
	shape.radius = 0.4
	shape.height = 3.0
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = Vector3(0, 1.6, 0)
	body.add_child(cs)
	body.set_meta("prompt", "Auto-Borer - press G to pack up")
	body.set_meta("action", func() -> void: pack_up())
	_rig.add_child(body)


func _update_visual() -> void:
	if _rig == null:
		return
	var string_len := depth + 2.6 - 0.3
	_string.scale = Vector3(1, maxf(string_len, 0.1), 1)
	_head.position = Vector3(0, -depth - 0.3 + 0.8, 0)
	var col: Color = {"running": Pal.ION, "paused": Pal.CREAM, "stalled": Pal.RED, "done": Pal.GREEN}.get(state, Pal.CREAM)
	_lamp_mat.set_shader_parameter("emission_scale", 1.8 if state == "running" else 0.8)
	_lamp_tint(col)


func _lamp_tint(col: Color) -> void:
	# the lamp mesh is white; tint it by swapping a tiny mesh in its colour (on change only)
	if col.is_equal_approx(_lamp_col):
		return
	_lamp_col = col
	var lamp_node := _rig.get_child(1) as MeshInstance3D
	var lamp := MeshKit.new().surf(0.3)
	lamp.set_emission(1.0)
	lamp.sphere(Vector3(0, 3.3, 0), 0.08, col, Vector3.ONE, 8, 5)
	lamp_node.mesh = lamp.commit()
