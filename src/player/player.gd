class_name Player
extends CharacterBody3D
## First-person controller for tiny spherical worlds.
##
## * Gravity always points at the planet centre (and fades to zero-g inside the core chamber).
## * The body's "up" is re-aligned every physics tick with the shortest rotation, so walking
##   around the planet never snaps or rolls the view.
## * The camera rig is detached (top_level) and updated every rendered frame: mouse look has zero
##   latency while body motion is smoothed between physics ticks.
## * Comfort: the camera's own "up" eases towards the body's up with a short time constant
##   (Settings "horizon_smoothing"), so the horizon never snaps - walking a 400 m planet turns
##   the world by under 1 degree per second, and transitions (core, teleports) are softened.
##   See docs/TECHNICAL.md "Orientation and comfort" and tests/test_j_traversal.gd.

signal landed(impact_speed: float)
signal jumped()
signal jet_fuel_changed(ratio: float)

const EYE_HEIGHT := 1.55
const CAPSULE_HEIGHT := 1.75
const CAPSULE_RADIUS := 0.36
const WALK_SPEED := 5.6
const SPRINT_MULT := 1.55
const GROUND_ACCEL := 55.0
const AIR_ACCEL := 14.0
const GROUND_FRICTION := 11.0
const JUMP_HEIGHT := 1.45
const JET_ACCEL := 30.0
const MAX_FALL_SPEED := 38.0
const COYOTE_TIME := 0.12
const JUMP_BUFFER := 0.12

var planet: Planet
var camera: Camera3D
var cam_rig: Node3D
var tool_mount: Node3D
var headlamp: SpotLight3D
var pitch := 0.0
var input_enabled := true
var controls_locked := false         ## UI open: no look, no move
var up := Vector3.UP
var vertical_speed := 0.0
var jet_fuel := 1.0
var is_jetting := false
var in_zero_g := false
var depth := 0.0                     ## metres below the original surface (negative above ground)
var trauma := 0.0                    ## camera shake amount 0..1
var waiting_for_ground := false      ## terrain under the player is still streaming in
var cam_up := Vector3.UP             ## the camera's smoothed up vector (comfort)
var _air_jumps_left := 0
var _coyote := 0.0
var _jump_buffer := 0.0
var _was_on_floor := false
var _bob_phase := 0.0
var _land_dip := 0.0
var _recoil := Vector2.ZERO
var _fov_kick := 0.0
var _stuck_time := 0.0
var _prev_origin := Vector3.ZERO
var _curr_origin := Vector3.ZERO
var _sprint_toggled := false
var _shake_time := 0.0
## Test hook: when set, replaces keyboard input. Vector2(x = strafe, y = forward).
var forced_move := Vector2.INF
var forced_jump := false
var forced_sprint := false
var forced_hold_jump := false


func _init() -> void:
	collision_layer = 2
	collision_mask = 1 | 4
	floor_max_angle = deg_to_rad(56.0)
	floor_snap_length = 0.35
	floor_stop_on_slope = true
	floor_block_on_wall = false
	wall_min_slide_angle = deg_to_rad(8.0)
	max_slides = 5
	safe_margin = 0.02
	motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED

	var shape := CapsuleShape3D.new()
	shape.radius = CAPSULE_RADIUS
	shape.height = CAPSULE_HEIGHT
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position = Vector3(0, CAPSULE_HEIGHT * 0.5, 0)
	add_child(col)

	cam_rig = Node3D.new()
	cam_rig.name = "CamRig"
	cam_rig.top_level = true
	cam_rig.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(cam_rig)
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.near = 0.06
	camera.far = 600.0
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	cam_rig.add_child(camera)
	tool_mount = Node3D.new()
	tool_mount.name = "ToolMount"
	tool_mount.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	camera.add_child(tool_mount)

	headlamp = SpotLight3D.new()
	headlamp.name = "Headlamp"
	headlamp.spot_range = 30.0
	headlamp.spot_angle = 58.0
	headlamp.spot_angle_attenuation = 0.55
	headlamp.spot_attenuation = 0.8
	headlamp.light_color = Color(1.0, 0.93, 0.8)
	headlamp.light_energy = 0.0
	headlamp.shadow_enabled = false
	headlamp.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	camera.add_child(headlamp)


func _ready() -> void:
	camera.fov = float(Settings.get_value("fov"))
	camera.make_current()
	Settings.changed.connect(_on_setting_changed)
	_prev_origin = global_position
	_curr_origin = global_position


func _on_setting_changed(key: String) -> void:
	if key == "fov":
		camera.fov = float(Settings.get_value("fov"))


## Places the player standing at `pos`, facing `look_dir` (projected onto the ground plane).
func teleport(pos: Vector3, look_dir := Vector3.ZERO) -> void:
	up = planet.up_at(pos) if planet else Vector3.UP
	var fwd := look_dir - up * look_dir.dot(up)
	if fwd.length() < 0.01:
		fwd = up.cross(Vector3.RIGHT)
		if fwd.length() < 0.01:
			fwd = up.cross(Vector3.FORWARD)
	fwd = fwd.normalized()
	var right := fwd.cross(up).normalized()
	global_transform = Transform3D(Basis(right, up, -fwd), pos)
	velocity = Vector3.ZERO
	vertical_speed = 0.0
	pitch = 0.0
	_prev_origin = pos
	_curr_origin = pos
	cam_up = up
	reset_physics_interpolation()
	_update_camera(0.0)


func _unhandled_input(event: InputEvent) -> void:
	if controls_locked or not input_enabled:
		return
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		var sens := float(Settings.get_value("mouse_sensitivity")) * 0.01
		var motion := (event as InputEventMouseMotion).relative
		look(Vector2(-motion.x * sens, -motion.y * sens * (-1.0 if Settings.get_value("invert_y") else 1.0)))


## Applies a look delta in radians (x = yaw, y = pitch).
func look(delta: Vector2) -> void:
	global_basis = (Basis(global_basis.y.normalized(), delta.x) * global_basis).orthonormalized()
	pitch = clampf(pitch + delta.y, deg_to_rad(-88.0), deg_to_rad(88.0))


func add_trauma(amount: float) -> void:
	trauma = clampf(trauma + amount, 0.0, 1.0)


func add_recoil(kick: Vector2) -> void:
	_recoil += kick


func move_speed() -> float:
	return WALK_SPEED * float(GameState.gear_value("boots"))


func gravity_strength() -> float:
	return float(planet.config.get("gravity", 17.0)) if planet else 17.0


func jump_speed() -> float:
	return sqrt(2.0 * gravity_strength() * JUMP_HEIGHT)


func _physics_process(delta: float) -> void:
	if planet == null or not planet.is_loaded:
		return
	_prev_origin = _curr_origin
	var pos := global_position
	# Terrain streams in around the player. If the ground here has not got full-resolution
	# collision yet (a jet-assisted sprint outran the loader, or a teleport), hold still for the
	# few frames it takes rather than falling through the world.
	waiting_for_ground = not planet.is_area_ready(pos, 3.0)
	if waiting_for_ground:
		velocity = Vector3.ZERO
		vertical_speed = 0.0
		_curr_origin = pos
		return

	# --- gravity & orientation
	var grav := planet.gravity_at(pos)
	var g_len := grav.length()
	var full_g := gravity_strength()
	var g_ratio := g_len / maxf(full_g, 0.001)
	in_zero_g = g_ratio < 0.25
	var target_up := planet.up_at(pos)
	if g_ratio > 0.02:
		var cur_up := global_basis.y.normalized()
		var align := Quaternion(cur_up, target_up)
		# Near the core the direction to the centre swings wildly, so follow it more lazily.
		var weight := clampf(g_ratio * 1.4, 0.0, 1.0)
		var q := Quaternion.IDENTITY.slerp(align, weight)
		global_basis = (Basis(q) * global_basis).orthonormalized()
	up = global_basis.y.normalized()
	up_direction = up

	# --- input
	var move := Vector2.ZERO
	var want_jump := false
	var hold_jump := false
	var sprinting := false
	if input_enabled and not controls_locked:
		if forced_move != Vector2.INF:
			move = forced_move
			want_jump = forced_jump
			hold_jump = forced_jump or forced_hold_jump
			sprinting = forced_sprint
			forced_jump = false
		else:
			move = Vector2(Input.get_axis("move_left", "move_right"), Input.get_axis("move_back", "move_forward"))
			want_jump = Input.is_action_just_pressed("jump")
			hold_jump = Input.is_action_pressed("jump")
			if Settings.get_value("toggle_sprint"):
				if Input.is_action_just_pressed("sprint"):
					_sprint_toggled = not _sprint_toggled
				if move.length() < 0.1:
					_sprint_toggled = false
				sprinting = _sprint_toggled
			else:
				sprinting = Input.is_action_pressed("sprint")
	if move.length() > 1.0:
		move = move.normalized()

	var on_floor := is_on_floor()
	var speed := move_speed() * (SPRINT_MULT if sprinting and move.y > 0.1 else 1.0)
	var wish := (global_basis.x * move.x - global_basis.z * move.y) * speed

	if in_zero_g:
		_physics_zero_g(delta, move, hold_jump)
	else:
		# split velocity
		vertical_speed = velocity.dot(up)
		var tangent := velocity - up * vertical_speed
		if on_floor:
			var accel := GROUND_ACCEL if wish.length() > 0.1 else GROUND_FRICTION * maxf(tangent.length(), 2.0)
			tangent = tangent.move_toward(wish, accel * delta)
		else:
			# air control: steer without killing momentum
			if wish.length() > 0.1:
				tangent = tangent.move_toward(wish, AIR_ACCEL * delta)

		# timers
		if on_floor:
			_coyote = COYOTE_TIME
			_air_jumps_left = 1 if int(GameState.gear_value("jets")) >= 1 else 0
			jet_fuel = minf(1.0, jet_fuel + delta * 0.9)
		else:
			_coyote = maxf(0.0, _coyote - delta)
		_jump_buffer = JUMP_BUFFER if want_jump else maxf(0.0, _jump_buffer - delta)

		# gravity
		vertical_speed -= g_len * delta
		if on_floor and vertical_speed < 0.0:
			vertical_speed = -g_len * delta   # small stick force

		# jumping
		is_jetting = false
		var jets := int(GameState.gear_value("jets"))
		if _jump_buffer > 0.0 and _coyote > 0.0:
			vertical_speed = jump_speed()
			_jump_buffer = 0.0
			_coyote = 0.0
			jumped.emit()
			Audio.play("jump", -8.0, 1.0, 0.08)
		elif want_jump and not on_floor and _air_jumps_left > 0:
			_air_jumps_left -= 1
			vertical_speed = jump_speed() * 0.95
			_jump_buffer = 0.0
			jumped.emit()
			Audio.play("jet_puff", -5.0, 1.0, 0.1)
		elif hold_jump and not on_floor and jets >= 2 and jet_fuel > 0.0 and _air_jumps_left <= 0 and vertical_speed < jump_speed() * 0.8:
			var burn := 0.42 if jets == 2 else 0.2
			jet_fuel = maxf(0.0, jet_fuel - delta * burn)
			vertical_speed = minf(vertical_speed + (JET_ACCEL + g_len) * delta, 7.5 if jets == 2 else 10.0)
			is_jetting = true
		vertical_speed = maxf(vertical_speed, -MAX_FALL_SPEED)
		velocity = tangent + up * vertical_speed

	Audio.set_loop("jetpack", is_jetting, 1.0, -8.0)
	jet_fuel_changed.emit(jet_fuel)

	var pre_vertical := vertical_speed
	move_and_slide()

	# landing feedback
	var now_on_floor := is_on_floor()
	if now_on_floor and not _was_on_floor and pre_vertical < -5.0:
		var impact := -pre_vertical
		_land_dip = clampf(impact * 0.012, 0.0, 0.22)
		landed.emit(impact)
		Audio.play("land", clampf(-14.0 + impact * 0.5, -14.0, -2.0), 1.0, 0.08)
	_was_on_floor = now_on_floor

	# footsteps / bob
	var horiz := (velocity - up * velocity.dot(up)).length()
	if now_on_floor and horiz > 1.0:
		var before := _bob_phase
		_bob_phase += horiz * delta * 1.45
		if int(before / PI) != int(_bob_phase / PI):
			Audio.play("step", -17.0, 1.0, 0.12)

	_curr_origin = global_position
	depth = planet.geology.depth_at(global_position + up * 0.9)
	_unstick(delta)


func _physics_zero_g(delta: float, move: Vector2, rise: bool) -> void:
	# Weightless drifting near a planet's heart: swim where you look.
	var cam_basis := camera.global_basis
	var wish := (cam_basis.x * move.x - cam_basis.z * move.y) * move_speed() * 0.8
	if rise:
		wish += global_basis.y * move_speed() * 0.6
	velocity = velocity.lerp(wish, clampf(delta * 2.2, 0.0, 1.0))
	vertical_speed = velocity.dot(up)
	is_jetting = false
	_air_jumps_left = 1 if int(GameState.gear_value("jets")) >= 1 else 0
	jet_fuel = minf(1.0, jet_fuel + delta * 0.5)


## If the player ends up embedded in solid ground (e.g. terrain re-meshed around them),
## float them back out towards open air.
func _unstick(delta: float) -> void:
	var chest := global_position + up * (CAPSULE_HEIGHT * 0.55)
	if planet.sdf_at(chest) < -0.6:
		_stuck_time += delta
		if _stuck_time > 0.35:
			var p := global_position
			for i in 60:
				p += up * 0.5
				if planet.sdf_at(p + up * 0.9) > 0.3:
					break
			global_position = p
			velocity = Vector3.ZERO
			_stuck_time = 0.0
	else:
		_stuck_time = 0.0


func _process(delta: float) -> void:
	_update_camera(delta)


func _update_camera(delta: float) -> void:
	# Smooth the origin between physics ticks; orientation is always the live value.
	var f := clampf(Engine.get_physics_interpolation_fraction(), 0.0, 1.0)
	var origin := _prev_origin.lerp(_curr_origin, f) if Engine.is_in_physics_frame() == false else _curr_origin
	var body := global_basis.orthonormalized()
	# Comfort: the camera levels itself to a smoothed "up"; yaw always comes from the body.
	var tau := float(Settings.get_value("horizon_smoothing"))
	if tau > 0.001 and delta > 0.0 and cam_up.dot(body.y) > -0.99:
		cam_up = cam_up.slerp(body.y, 1.0 - exp(-delta / tau)).normalized()
	else:
		cam_up = body.y
	var fwd := -body.z - cam_up * (-body.z).dot(cam_up)
	if fwd.length() < 0.01:
		fwd = -body.z
	fwd = fwd.normalized()
	var b := Basis(fwd.cross(cam_up).normalized(), cam_up, -fwd)

	_land_dip = lerpf(_land_dip, 0.0, clampf(delta * 9.0, 0.0, 1.0))
	_recoil = _recoil.lerp(Vector2.ZERO, clampf(delta * 12.0, 0.0, 1.0))
	trauma = maxf(0.0, trauma - delta * 1.8)
	_shake_time += delta

	var bob_amt := float(Settings.get_value("view_bob"))
	var bob := Vector3.ZERO
	if is_on_floor():
		var horiz := (velocity - up * velocity.dot(up)).length()
		var w := clampf(horiz / WALK_SPEED, 0.0, 1.4) * bob_amt
		bob = Vector3(cos(_bob_phase) * 0.018, -absf(sin(_bob_phase)) * 0.028, 0.0) * w

	var shake_scale := float(Settings.get_value("camera_shake"))
	var sh := trauma * trauma * shake_scale
	var shake_rot := Vector3(sin(_shake_time * 61.0) * 0.022, sin(_shake_time * 47.0 + 1.3) * 0.022, sin(_shake_time * 53.0 + 2.1) * 0.016) * sh

	cam_rig.global_transform = Transform3D(b, origin + b.y * (EYE_HEIGHT - _land_dip))
	camera.transform = Transform3D(Basis.from_euler(Vector3(pitch + _recoil.y + shake_rot.x, _recoil.x + shake_rot.y, shake_rot.z)), bob)

	# sprint FOV kick
	var target_kick := 0.0
	var horiz2 := (velocity - up * velocity.dot(up)).length()
	if horiz2 > WALK_SPEED * 1.2 * float(GameState.gear_value("boots")) and bool(Settings.get_value("sprint_fov")):
		target_kick = 5.0
	_fov_kick = lerpf(_fov_kick, target_kick, clampf(delta * 6.0, 0.0, 1.0))
	camera.fov = float(Settings.get_value("fov")) + _fov_kick

	# headlamp fades in underground
	var lamp_target := clampf((depth - 1.5) / 4.0, 0.0, 1.0) * 3.2
	headlamp.light_energy = lerpf(headlamp.light_energy, lamp_target, clampf(delta * 3.0, 0.0, 1.0))
	headlamp.visible = headlamp.light_energy > 0.02


func eye_position() -> Vector3:
	return camera.global_position


func aim_direction() -> Vector3:
	return -camera.global_basis.z
