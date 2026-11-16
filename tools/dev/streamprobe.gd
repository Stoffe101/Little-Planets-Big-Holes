extends Node
## Dev tool: frame-by-frame view of what terrain streaming does around a long jump (relay
## travel). For every frame after the jump it prints the frame time and how the voxel engine's
## state changed (mesh/data block counts, queued tasks, the terrain's own update timings), so a
## spike can be matched to block loading, meshing or unloading. Strategies:
##   plain     teleport, nothing else (what pass 3 shipped)
##   prestream add a second VoxelViewer at the destination first, wait until it is ready,
##             teleport, then drop the helper viewer
##   run       no jump: sprint with max boots + jetpack hops straight across country for
##             `metres` seconds and report hitches, frames held waiting for ground, distance
##
##   <godot> [--headless] --path . res://tools/dev/streamprobe.tscn -- [planet] [plain|prestream] [metres]

var world: World
var _last := 0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var pid: String = args[0] if args.size() > 0 else "pipseed"
	var mode: String = args[1] if args.size() > 1 else "plain"
	var dist := float(args[2]) if args.size() > 2 else 300.0
	SaveSystem.save_dir = "user://dev_streamprobe"
	SaveSystem.ensure_dir()
	SaveSystem.delete_save()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	GameState.reset()
	GameState.current_planet = pid
	world = World.new()
	add_child(world)
	world.start(pid, true)
	await world.ready_to_play
	await _settle()
	var p := world.player
	print("== streamprobe %s mode=%s jump=%.0f m  mesh blocks %d data blocks %d" % [pid, mode, dist,
		world.planet.terrain.debug_get_mesh_block_count(), world.planet.terrain.debug_get_data_block_count()])
	if mode == "run":
		await _run(dist)
		SaveSystem.delete_save()
		print("done")
		get_tree().quit()
		return
	for jump in 3:
		var d := (p.global_position.normalized() + p.global_basis.x * (dist / world.planet.geology.radius)).normalized()
		var target := d * (world.planet.geology.surface_radius(d) + 1.2)
		var helper: VoxelViewer = null
		var t0 := Time.get_ticks_msec()
		if mode == "prestream":
			helper = VoxelViewer.new()
			helper.view_distance = world.planet.viewer.view_distance
			helper.requires_collisions = true
			helper.requires_visuals = true
			world.planet.add_child(helper)
			helper.global_position = target
			print("-- jump %d: helper viewer placed" % jump)
			await _trace(func() -> bool: return world.planet.is_area_ready(target, 3.0), 400)
			print("   destination ready after %d ms (player still at origin)" % (Time.get_ticks_msec() - t0))
		print("-- jump %d: teleport" % jump)
		DevPerf.mark("jump %d" % jump)
		t0 = Time.get_ticks_msec()
		p.teleport(target, Vector3.FORWARD)
		if helper != null:
			await get_tree().process_frame
			helper.queue_free()
		await _trace(func() -> bool: return world.planet.is_area_ready(p.global_position, 3.0), 240)
		print("   player ground ready %d ms after teleport" % (Time.get_ticks_msec() - t0))
		DevPerf.mark("(settle)")
		await _settle()
	SaveSystem.delete_save()
	print("done")
	get_tree().quit()


func _run(seconds: float) -> void:
	var p := world.player
	GameState.gear_levels["boots"] = GameState.gear_max_level("boots")
	GameState.gear_levels["jets"] = GameState.gear_max_level("jets")
	GameState.gear_changed.emit("boots")
	p.teleport(p.global_position, Vector3(0.2, 0, -1))
	p.forced_move = Vector2(0, 1)
	p.forced_sprint = true
	var hop := create_tween().set_loops()
	hop.tween_interval(0.9)
	hop.tween_callback(func() -> void: p.forced_jump = true)
	var start := p.global_position
	var held := [0]
	var counter := func() -> bool:
		if p.waiting_for_ground:
			held[0] += 1
		return false
	print("-- run: %.0f s sprint + jets" % seconds)
	DevPerf.mark("run")
	var t0 := Time.get_ticks_msec()
	var frames := 0
	# _trace counts frames, so run it in slices until the time is up
	while Time.get_ticks_msec() - t0 < int(seconds * 1000.0):
		await _trace(counter, 120)
		frames += 120
	DevPerf.mark("(settle)")
	hop.kill()
	p.forced_move = Vector2.INF
	p.forced_sprint = false
	print("   run: covered %.0f m in %.1f s (%.1f m/s), frames held waiting for ground: %d" % [start.distance_to(p.global_position),
		(Time.get_ticks_msec() - t0) / 1000.0, start.distance_to(p.global_position) / ((Time.get_ticks_msec() - t0) / 1000.0), held[0]])


## Runs `frames` frames, printing every frame slower than 12 ms with the engine state deltas,
## and a summary. `ready` is polled to report when the condition first held.
func _trace(ready: Callable, frames: int) -> void:
	var t := world.planet.terrain
	var prev_mesh := t.debug_get_mesh_block_count()
	var prev_data := t.debug_get_data_block_count()
	var last := Time.get_ticks_usec()
	var times := PackedFloat32Array()
	var ready_at := -1
	for i in frames:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		var ms := float(now - last) / 1000.0
		last = now
		times.append(ms)
		var mesh := t.debug_get_mesh_block_count()
		var data := t.debug_get_data_block_count()
		if ready_at < 0 and ready.call():
			ready_at = i
		if ms > 30.0 or i % 15 == 0 or (ready_at == i):
			var st: Dictionary = t.get_statistics()
			var tk: Dictionary = VoxelEngine.get_stats()["tasks"]
			print("   f%3d %6.1f ms  mesh %5d (%+5d) data %6d (%+6d)  tasks gen %4d mesh %4d main %4d stream %3d  detect %5d us update_task %5d us" % [
				i, ms, mesh, mesh - prev_mesh, data, data - prev_data, int(tk["generation"]), int(tk["meshing"]), int(tk["main_thread"]),
				int(tk["streaming"]), int(st["time_detect_required_blocks"]), int(st["time_update_task"])])
		prev_mesh = mesh
		prev_data = data
	var sorted := Array(times)
	sorted.sort()
	var total := 0.0
	for v: float in sorted:
		total += v
	print("   summary: %d frames, avg %.2f ms, p95 %.1f, p99 %.1f, max %.1f; frames > 33 ms: %d; condition true at frame %d" % [
		sorted.size(), total / sorted.size(), sorted[int(sorted.size() * 0.95)], sorted[mini(sorted.size() - 1, int(sorted.size() * 0.99))],
		sorted[-1], sorted.filter(func(v: float) -> bool: return v > 33.0).size(), ready_at])


func _settle() -> void:
	var t0 := Time.get_ticks_msec()
	var quiet := 0
	while Time.get_ticks_msec() - t0 < 15000 and quiet < 10:
		await get_tree().process_frame
		var tk: Dictionary = VoxelEngine.get_stats()["tasks"]
		quiet = quiet + 1 if int(tk["meshing"]) + int(tk["generation"]) + int(tk["streaming"]) + int(tk["main_thread"]) == 0 else 0
