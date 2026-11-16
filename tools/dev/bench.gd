extends Node
## Headless micro-benchmark of the terrain pipeline. Prints real measurements for docs/TECHNICAL.md.
##   godot --headless --path . res://tools/dev/bench.tscn
func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	Audio.enabled = false
	SaveSystem.save_dir = "user://bench"
	SaveSystem.ensure_dir()
	SaveSystem.delete_save()
	GameState.reset()
	var t0 := Time.get_ticks_msec()
	var w := World.new()
	add_child(w)
	w.start("pipseed", true)
	var setup_ms := Time.get_ticks_msec() - t0
	await w.ready_to_play
	print("world setup (geology bake + graph compile): %d ms" % setup_ms)
	print("terrain streaming+meshing until playable: %d ms" % w.planet.load_time_ms)
	print("total to playable: %d ms" % (Time.get_ticks_msec() - t0))
	for i in 120:
		await get_tree().process_frame
	var st: Dictionary = VoxelEngine.get_stats()
	print("voxel blocks: %d, voxel memory: %.1f MB, static memory: %.0f MB, threads: %d" % [int(st["memory_pools"]["block_count"]), float(st["memory_pools"]["voxel_used"]) / 1048576.0, OS.get_static_memory_usage() / 1048576.0, VoxelEngine.get_thread_count()])
	print("props: %s, surface formations: %s, cave formations: %s" % [str(w.props.get("prop_count")), str(w.props.get("formation_count")), str(w.secrets.get("formation_count"))])
	var geo := w.planet.geology
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	for radius: float in [0.85, 1.5, 2.4, 3.4, 6.5]:
		var total := 0
		var n := 0
		for i in 40:
			var d := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, -0.3), rng.randf_range(-1, 1)).normalized()
			var c := d * (geo.surface_radius(d) - radius * 0.4)
			var t := Time.get_ticks_usec()
			var res := w.dig.dig_sphere(c, radius, 9)
			if bool(res["ok"]):
				total += Time.get_ticks_usec() - t
				n += 1
		print("dig_sphere r=%.2f m: %.3f ms avg over %d digs (survey + voxel edit, main thread)" % [radius, float(total) / 1000.0 / float(maxi(n, 1)), n])
		for i in 10:
			await get_tree().physics_frame
	# selective digs at a hardness boundary
	var sel_total := 0
	var sel_n := 0
	for i in 200:
		var d := Vector3(rng.randf_range(-1, 1), rng.randf_range(0.2, 1), rng.randf_range(-1, 1)).normalized()
		var c := d * (geo.surface_radius(d) - 4.1)
		var sv := w.dig.survey(c, 1.5, 1)
		if int(sv["hard"]) == 0 or float(sv["hard"]) / float(maxi(int(sv["solid"]), 1)) > 0.7:
			continue
		var t := Time.get_ticks_usec()
		w.dig.dig_sphere(c, 1.5, 1)
		sel_total += Time.get_ticks_usec() - t
		sel_n += 1
	print("selective dig r=1.50 m (protects hard voxels): %.3f ms avg over %d digs" % [float(sel_total) / 1000.0 / float(maxi(sel_n, 1)), sel_n])
	# remesh latency: time until collision reflects an edit
	var d2 := Vector3(0.3, -0.6, 0.74).normalized()
	var top := w.planet.ground_point(d2)
	var space := w.get_world_3d().direct_space_state
	var r0: float = (space.intersect_ray(PhysicsRayQueryParameters3D.create(d2 * 90.0, Vector3.ZERO, 1))["position"] as Vector3).length()
	var t1 := Time.get_ticks_msec()
	w.dig.dig_sphere(top - d2 * 0.5, 1.5, 9)
	var frames := 0
	while frames < 600:
		await get_tree().physics_frame
		frames += 1
		var h := space.intersect_ray(PhysicsRayQueryParameters3D.create(d2 * 90.0, Vector3.ZERO, 1))
		if not h.is_empty() and (h["position"] as Vector3).length() < r0 - 0.8:
			break
	print("edit -> collision updated: %d physics frames (%d ms wall, headless unthrottled)" % [frames, Time.get_ticks_msec() - t1])
	var t2 := Time.get_ticks_msec()
	w.save_all(true)
	print("blocking save (progress + modified terrain blocks): %d ms" % (Time.get_ticks_msec() - t2))
	var db := ProjectSettings.globalize_path(SaveSystem.terrain_db_path("pipseed"))
	print("terrain db size after ~%d digs: %.1f KB" % [w.dig.total_digs, FileAccess.get_file_as_bytes(db).size() / 1024.0])
	w.shutdown()
	get_tree().quit()
