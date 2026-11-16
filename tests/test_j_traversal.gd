extends TestSuite
## Traversal comfort on big planets: how much the world turns under you, and that the camera
## never snaps or rolls. These are measurements of camera orientation, not a judgement of how
## the motion feels - that needs a human (docs/PLAYTEST.md).

var w: World
var geo: Geology
var log_lines: Array[String] = []


func before_all() -> void:
	use_sandbox("traversal")
	GameState.reset()
	w = await make_world("pipseed", false)
	geo = w.planet.geology


func after_all() -> void:
	for l in log_lines:
		print("         ", l)
	GameState.reset()
	await free_world(w)


## Drives the player for `n` physics frames, sampling the camera rig every frame.
func _drive(n: int, move: Vector2, sprint := false, jump_every := 0, hold_jets := false) -> Dictionary:
	var p := w.player
	p.forced_move = move
	p.forced_sprint = sprint
	p.forced_hold_jump = hold_jets
	await get_tree().process_frame
	var prev_up := p.cam_rig.global_basis.y.normalized()
	var start_up := prev_up
	var start := p.global_position
	var max_step := 0.0
	var max_roll := 0.0
	var total := 0.0
	for i in n:
		if jump_every > 0 and i % jump_every == 0:
			p.forced_jump = true
		await get_tree().physics_frame
		await get_tree().process_frame
		var rig := p.cam_rig.global_basis.orthonormalized()
		var up := rig.y
		var step := rad_to_deg(prev_up.angle_to(up))
		max_step = maxf(max_step, step)
		total += step
		prev_up = up
		# roll: the camera's right vector must stay level with the local horizon
		var planet_up := w.planet.up_at(p.global_position)
		max_roll = maxf(max_roll, absf(rad_to_deg(asin(clampf(rig.x.dot(planet_up), -1.0, 1.0)))))
	p.forced_move = Vector2.INF
	p.forced_sprint = false
	p.forced_hold_jump = false
	var secs := float(n) / float(Engine.physics_ticks_per_second)
	return {"max_step_deg": max_step, "mean_rate_deg_s": total / secs, "max_roll_deg": max_roll,
		"distance": start.distance_to(p.global_position), "turned_deg": rad_to_deg(start_up.angle_to(prev_up)), "frames": n}


func _report(label: String, r: Dictionary) -> void:
	log_lines.append("%s: %.1f m in %.1f s, world turned %.2f deg (%.2f deg/s), largest per-frame change %.4f deg, max roll %.3f deg" % [
		label, float(r["distance"]), float(r["frames"]) / 60.0, float(r["turned_deg"]), float(r["mean_rate_deg_s"]), float(r["max_step_deg"]), float(r["max_roll_deg"])])


func test_walking_turns_the_world_slowly_and_smoothly() -> void:
	await place_player(w, geo.landing_dir + Vector3(0.04, 0, 0.06))
	var r := await _drive(600, Vector2(0, 1))
	_report("walk", r)
	assert_gt(float(r["distance"]), 25.0, "walked a fair distance")
	# 5.6 m/s on a 400 m planet turns the world by ~0.8 deg/s (it was ~6.7 deg/s at 48 m)
	assert_lt(float(r["mean_rate_deg_s"]), 1.6, "world turns slowly underfoot")
	assert_lt(float(r["max_step_deg"]), 0.12, "no orientation jumps between frames")
	assert_lt(float(r["max_roll_deg"]), 0.5, "the horizon never rolls")


func test_sprinting_and_jumping_stay_smooth() -> void:
	GameState.gear_levels["boots"] = GameState.gear_max_level("boots")
	GameState.gear_levels["jets"] = GameState.gear_max_level("jets")
	await place_player(w, geo.landing_dir + Vector3(-0.08, 0, 0.03))
	var r := await _drive(600, Vector2(0, 1), true, 50)
	_report("sprint + jumps (best boots)", r)
	assert_gt(float(r["distance"]), 40.0, "covered ground")
	assert_lt(float(r["mean_rate_deg_s"]), 3.5, "world turns gently even at top speed")
	assert_lt(float(r["max_step_deg"]), 0.2, "no snaps on take-off or landing")
	assert_lt(float(r["max_roll_deg"]), 0.5, "no roll")
	var r2 := await _drive(240, Vector2(0.3, 1), true, 0, true)
	_report("jetpack flight", r2)
	assert_lt(float(r2["max_step_deg"]), 0.2, "jetting stays smooth")
	GameState.gear_levels["boots"] = 0
	GameState.gear_levels["jets"] = 0


func test_turning_while_strafing_keeps_the_horizon_level() -> void:
	var hill := (geo.landing_dir + Vector3(0.18, 0, -0.05)).normalized()
	await place_player(w, hill)
	var worst_step := 0.0
	var worst_roll := 0.0
	var last := {}
	for k in 6:
		w.player.look(Vector2(0.5, 0))
		last = await _drive(60, Vector2(1, 0.6))
		worst_step = maxf(worst_step, float(last["max_step_deg"]))
		worst_roll = maxf(worst_roll, float(last["max_roll_deg"]))
	_report("strafe + turn on a hillside (last leg)", last)
	assert_lt(worst_step, 0.15, "turning the view does not tilt the horizon")
	assert_lt(worst_roll, 0.5, "no roll while turning")


func test_tunnel_walk_keeps_the_same_up() -> void:
	var d := (geo.landing_dir + Vector3(0.0, 0, 0.12)).normalized()
	await stream_to(w, d * (geo.surface_radius(d) + 2.0), 20.0)
	var side := d.cross(Vector3.RIGHT).normalized()
	var a := w.planet.ground_point(d) - d * 6.0
	var b := a + side * 18.0
	assert_true(bool(w.dig.dig_capsule(a, b, 1.8, 9)["ok"]), "tunnel dug")
	await wait_until(func() -> bool: return not ray(w, a + d * 0.5, a - d * 3.0).is_empty())
	w.player.teleport(a - d * 1.0, side)
	await physics(30)
	var r := await _drive(180, Vector2(0, 1))
	_report("tunnel", r)
	assert_gt(w.player.depth, 1.5, "walked underground")
	assert_lt(float(r["max_step_deg"]), 0.12, "no orientation change in the tunnel")


func test_smoothing_eases_a_sudden_change_of_down() -> void:
	# Gravity fading out at the core, or any other sudden change of "down": the camera must ease
	# into the new up instead of snapping in one frame.
	await place_player(w, geo.landing_dir)
	Settings.set_value("horizon_smoothing", 0.25, false)
	var p := w.player
	p.cam_up = p.global_basis.y.rotated(p.global_basis.x, deg_to_rad(30.0))
	await frames(1)
	var first := rad_to_deg(p.cam_up.angle_to(p.global_basis.y))
	var t := 0.0
	while t < 0.75:
		await get_tree().process_frame
		t += get_process_delta_time()
	var later := rad_to_deg(p.cam_up.angle_to(p.global_basis.y))
	log_lines.append("smoothing 0.25 s: a 30 deg change of up -> %.2f deg left after 1 frame, %.3f deg after 0.75 s" % [first, later])
	assert_gt(first, 20.0, "no snap: most of the change remains after one frame")
	assert_lt(later, 2.0, "settles within three quarters of a second")
	Settings.set_value("horizon_smoothing", 0.0, false)
	p.cam_up = p.global_basis.y.rotated(p.global_basis.x, deg_to_rad(30.0))
	await frames(2)
	assert_lt(rad_to_deg(p.cam_up.angle_to(p.global_basis.y)), 0.01, "smoothing off = rigid camera")
	Settings.set_value("horizon_smoothing", float(Settings.DEFAULTS["horizon_smoothing"]), false)


func test_rotation_rate_comparison_old_and_new_planets() -> void:
	# The documented figures: how many degrees the world turns per second under the player.
	var walk := Player.WALK_SPEED
	var boots: Array = GameData.gear_by_id["boots"]["values"]
	var top := Player.WALK_SPEED * Player.SPRINT_MULT * float(boots[-1])
	for pair: Array in [["v0.2 Pipseed (48 m)", 48.0], ["Glimmerock (300 m)", 300.0], ["Pipseed (400 m)", 400.0]]:
		log_lines.append("%s: walking %.2f deg/s, top speed %.2f deg/s" % [pair[0], rad_to_deg(walk / float(pair[1])), rad_to_deg(top / float(pair[1]))])
	assert_lt(rad_to_deg(walk / geo.radius), 1.0, "under one degree per second when walking")


func test_walking_the_roughest_region_never_sinks_into_the_ground() -> void:
	# Regression: regional roughness with a ~9 m wavelength made egg-crate terrain steep enough to
	# embed the player (up to 7.6 m below the surface while walking in Stonebrake).
	for pid_region: String in ["stonebrake", "pockmark"]:
		var reg := {}
		for r in geo.regions:
			if r["id"] == pid_region:
				reg = r
		var d: Vector3 = reg["dir"]
		var side := d.cross(Vector3(0.2, 1, 0.1)).normalized()
		await place_player(w, (d + side * (25.0 / geo.radius)).normalized(), -side)
		var p := w.player
		var worst := 0.0
		for leg in 6:
			p.look(Vector2(1.0, 0))
			p.forced_move = Vector2(0, 1)
			p.forced_sprint = leg % 2 == 0
			for i in 90:
				await get_tree().physics_frame
				worst = maxf(worst, geo.surface_radius_exact(p.global_position.normalized()) - p.global_position.length())
		p.forced_move = Vector2.INF
		p.forced_sprint = false
		log_lines.append("%s: deepest below the surface while walking %.2f m" % [pid_region, worst])
		assert_lt(worst, 1.0, "never sinks into the ground in %s" % pid_region)
