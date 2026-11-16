extends Node
## Headless micro-benchmark of the terrain pipeline. Prints real measurements for docs/TECHNICAL.md.
##   godot --headless --path . res://tools/dev/bench.tscn
## All digs happen in the streamed, editable area around the outpost (the planet is streamed;
## digs further than ~70 m from the player are refused).
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
	print("data blocks: %d, mesh blocks: %d, static memory: %.0f MB, threads: %d" % [w.planet.terrain.debug_get_data_block_count(), w.planet.terrain.debug_get_mesh_block_count(), OS.get_static_memory_usage() / 1048576.0, VoxelEngine.get_thread_count()])
	print("props: %s, surface formations: %s, cave formations: %s" % [str(w.props.get("prop_count")), str(w.props.get("formation_count")), str(w.secrets.get("formation_count"))])
	var geo := w.planet.geology
	# how far from the player the ground is editable / collidable (16 directions along the surface)
	var me := w.player.global_position.normalized()
	var ax := me.cross(Vector3(0.3, 0.2, 0.9)).normalized()
	var edit_r := PackedFloat32Array()
	var coll_r := PackedFloat32Array()
	for k in 16:
		var h := ax.rotated(me, TAU * float(k) / 16.0)
		var e := 0.0
		var c := 0.0
		for m in range(2, 160, 2):
			var dd := (me + h * (float(m) / geo.radius)).normalized()
			var gp := dd * (geo.surface_radius(dd) - 0.5)
			if e == float(m - 2) and w.planet.is_loaded_at(gp):
				e = float(m)
			if c == float(m - 2) and w.planet.is_area_ready(gp, 1.0):
				c = float(m)
		edit_r.append(e)
		coll_r.append(c)
	var es := Array(edit_r); es.sort()
	var cs := Array(coll_r); cs.sort()
	print("editable ground around the player: %.0f-%.0f m (min-max over 16 directions); collidable: %.0f-%.0f m" % [es[0], es[-1], cs[0], cs[-1]])
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var up := geo.landing_dir
	var t1v := up.cross(Vector3(0.3, 0.2, 0.9)).normalized()
	var t2v := up.cross(t1v)
	var near := func() -> Vector3:
		var a := rng.randf() * TAU
		var m := rng.randf_range(16.0, 45.0)
		return (up + (t1v * cos(a) + t2v * sin(a)) * (m / geo.radius)).normalized()
	# one dig per frame, like play (the tools dig at most a few times per second)
	var radii: Array = [0.85, 1.5, 2.4, 3.4, 6.5]
	if OS.has_environment("LPBH_BENCH_RADII"):
		radii = Array(OS.get_environment("LPBH_BENCH_RADII").split(",")).map(func(x: String) -> float: return float(x))
	for radius: float in radii:
		var total := 0
		var survey_t := 0
		var edit_t := 0
		var n := 0
		for i in 40:
			var d: Vector3 = near.call()
			var c := d * (geo.surface_radius(d) - radius * 0.4)
			var t := Time.get_ticks_usec()
			var res := w.dig.dig_sphere(c, radius, 9)
			if bool(res["ok"]):
				total += Time.get_ticks_usec() - t
				survey_t += w.dig.last_survey_usec
				edit_t += w.dig.last_edit_usec
				n += 1
			await get_tree().process_frame
		var nn := float(maxi(n, 1)) * 1000.0
		print("dig_sphere r=%.2f m: %.3f ms avg over %d digs (survey %.3f, voxel edit %.3f; main thread)" % [radius, float(total) / nn, n, float(survey_t) / nn, float(edit_t) / nn])
		for i in 10:
			await get_tree().physics_frame
	# selective digs at a hardness boundary
	var sel_total := 0
	var sel_n := 0
	for i in 200:
		var d: Vector3 = near.call()
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
	var d2 := (up + t2v * (30.0 / geo.radius)).normalized()
	var top := w.planet.ground_point(d2)
	var space := w.get_world_3d().direct_space_state
	var ray_from := d2 * (geo.radius + 40.0)
	var ray_to := d2 * (geo.radius - 40.0)
	var r0: float = (space.intersect_ray(PhysicsRayQueryParameters3D.create(ray_from, ray_to, 1))["position"] as Vector3).length()
	var t1 := Time.get_ticks_msec()
	w.dig.dig_sphere(top - d2 * 0.5, 1.5, 9)
	var frames := 0
	while frames < 600:
		await get_tree().physics_frame
		frames += 1
		var h := space.intersect_ray(PhysicsRayQueryParameters3D.create(ray_from, ray_to, 1))
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
