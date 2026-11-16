extends TestSuite
## The streamed planet itself: LOD coverage and transitions, caves, regional ore richness,
## loading and unloading planets, and bounded memory while streaming (stress).

var w: World
var geo: Geology


func before_all() -> void:
	use_sandbox("terrain")
	GameState.reset()
	w = await make_world("pipseed", false)
	geo = w.planet.geology


func after_all() -> void:
	await free_world(w)


func _block_info(p: Vector3, lod: int) -> Dictionary:
	var v := Vector3i((p * geo.inv_voxel).floor())
	var s := int(round(log(float(w.planet.mesh_block_size)) / log(2.0))) + lod
	return w.planet.terrain.debug_get_mesh_block_info(Vector3(v.x >> s, v.y >> s, v.z >> s), lod)


func test_lod_pyramid_covers_the_whole_planet() -> void:
	# near the player: full resolution and collidable
	var here := w.player.global_position
	assert_true(w.planet.is_area_ready(here, 4.0), "LOD0 with live collision around the player")
	assert_false(ray(w, here + w.player.up * 2.0, here - w.player.up * 3.0).is_empty(), "a physics ray hits the ground under the player")
	# the far side of the planet is drawn too, at a coarse LOD, without being editable
	var anti := -geo.landing_dir * geo.surface_radius(-geo.landing_dir)
	assert_false(w.planet.is_loaded_at(anti), "the far side is not held at full resolution")
	var coarse_visible := false
	for lod in range(1, w.planet.lod_count):
		var info := _block_info(anti, lod)
		if bool(info.get("visible", false)):
			coarse_visible = true
			break
	assert_true(coarse_visible, "the far side is meshed and visible at some coarser LOD")
	# where LODs meet, Transvoxel transition masks are in use somewhere along a line outwards
	var masks := 0
	var side := geo.landing_dir.cross(Vector3.RIGHT).normalized()
	for m in range(20, 200, 6):
		var d := (geo.landing_dir + side * (float(m) / geo.radius)).normalized()
		for lod in 3:
			if int(_block_info(d * geo.surface_radius(d), lod).get("transition_mask", 0)) != 0:
				masks += 1
	assert_gt(float(masks), 0.0, "LOD seams use Transvoxel transition meshes (%d blocks sampled with a mask)" % masks)


func test_caves_exist_underground_and_not_at_the_pad() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var open := 0
	var samples := 0
	# sample the generator (the same function the terrain uses) along random deep columns
	var gen := geo.build_generator()
	var buf := VoxelBuffer.new()
	buf.create(1, 1, 1)
	for i in 400:
		var d := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized()
		var depth := rng.randf_range(12.0, 90.0)
		var p := d * (geo.surface_radius(d) - depth)
		gen.generate_block(buf, Vector3i((p * geo.inv_voxel).floor()), 0)
		samples += 1
		if buf.get_voxel_f(0, 0, 0, VoxelBuffer.CHANNEL_SDF) > 0.0:
			open += 1
	var frac := float(open) / float(samples)
	assert_gt(frac, 0.005, "there are natural caves at depth (%.1f%% of samples open)" % (frac * 100.0))
	assert_lt(frac, 0.25, "but the crust is mostly solid")
	# the landing pad is never undermined by a cave close to the surface
	for k in 12:
		var d2 := (geo.landing_dir + geo.landing_dir.cross(Vector3.RIGHT).normalized().rotated(geo.landing_dir, TAU * k / 12.0) * (6.0 / geo.radius)).normalized()
		gen.generate_block(buf, Vector3i((d2 * (geo.surface_radius(d2) - 3.0) * geo.inv_voxel).floor()), 0)
		assert_lt(buf.get_voxel_f(0, 0, 0, VoxelBuffer.CHANNEL_SDF), 0.0, "solid ground 3 m under the pad")


func test_regions_are_richer_in_their_ore() -> void:
	# every ore with a regional boost must be measurably more common inside that region
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for o in geo.ores:
		var ri := int(o["region"])
		if ri < 0:
			continue
		var reg := geo.regions[ri]
		var rid := str(reg["id"])
		var inside := 0
		var outside := 0
		var n := 3000
		var lo: float = o["min"] + Geology.EDGE_FADE
		var hi: float = o["max"] - Geology.EDGE_FADE
		var mat := int(o["mat"])
		for i in n:
			# inside: within the region's core; outside: anywhere else on the planet
			var t1 := (reg["dir"] as Vector3).cross(Vector3(0.3, 0.9, 0.1)).normalized()
			var t2 := (reg["dir"] as Vector3).cross(t1)
			var ang := acos(float(reg["cos_in"])) * sqrt(rng.randf()) * 0.9
			var a := rng.randf() * TAU
			var din := ((reg["dir"] as Vector3) * cos(ang) + (t1 * cos(a) + t2 * sin(a)) * sin(ang)).normalized()
			var depth := rng.randf_range(lo, hi)
			if geo.material_at(din * (geo.surface_radius(din) - depth)) == mat:
				inside += 1
			var dout := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized()
			if float(geo.region_weights(dout)[ri]) > 0.0:
				continue
			if geo.material_at(dout * (geo.surface_radius(dout) - depth)) == mat:
				outside += 1
		assert_gt(float(inside), float(outside) * 1.5, "%s is richer in %s (%d vs %d samples)" % [rid, GameData.mat_id(mat), inside, outside])


func test_streaming_memory_stays_bounded_while_travelling() -> void:
	# stress: jump around the planet; loaded blocks must not accumulate
	var counts: Array[int] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for i in 8:
		var d := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized()
		await stream_to(w, d * (geo.surface_radius(d) + 2.0), 4.0)
		# a few digs on the way
		w.dig.dig_sphere(w.planet.ground_point(d) - d * 0.5, 2.0, 9)
		await physics(30)
		counts.append(w.planet.terrain.debug_get_data_block_count())
	var first := counts[0]
	var last := counts[counts.size() - 1]
	var peak: int = counts.max()
	print("         data blocks after each jump: %s" % str(counts))
	assert_lt(float(peak), float(first) * 1.6, "data blocks stay bounded while travelling (peak %d vs %d)" % [peak, first])
	assert_lt(float(last), float(first) * 1.5, "old areas are released")
	assert_lt(float(OS.get_static_memory_usage()) / 1048576.0, 1200.0, "static memory stays reasonable (%.0f MB)" % (OS.get_static_memory_usage() / 1048576.0))


func test_planets_load_and_unload_cleanly() -> void:
	var mem0 := OS.get_static_memory_usage()
	for pid: String in ["glimmerock", "pipseed", "glimmerock"]:
		GameState.current_planet = pid
		var w2 := await make_world(pid, false)
		assert_true(w2.is_ready, "%s loads" % pid)
		assert_true(w2.player.is_on_floor() or await wait_until(func() -> bool: return w2.player.is_on_floor(), 120), "player stands on %s" % pid)
		assert_eq(w2.planet.geology.id, pid, "the right planet")
		await free_world(w2)
	await frames(10)
	var grown := float(OS.get_static_memory_usage() - mem0) / 1048576.0
	print("         static memory change after loading 3 planets in turn: %+.0f MB" % grown)
	assert_lt(grown, 250.0, "loading and unloading planets does not leak large amounts of memory")
	GameState.current_planet = "pipseed"


## `is_area_ready` has a fallback that does not need Voxel Tools' debug query (physics rays).
## After a long jump the fallback must not report the destination ready while the block query
## still sees LOD0 blocks without live colliders, and both must agree once it has streamed in.
func test_readiness_fallback_agrees_with_the_block_query() -> void:
	var p := w.planet
	await place_player(w, geo.landing_dir)
	var here := w.player.global_position
	p.readiness_mode = "raycast"
	assert_true(p.is_area_ready(here, 3.0), "fallback: ready where the player stands")
	p.readiness_mode = "block_info"
	var d := (here.normalized() + w.player.global_basis.x * (250.0 / geo.radius)).normalized()
	var target := d * (geo.surface_radius(d) + 1.2)
	w.player.teleport(target, Vector3.FORWARD)
	var early := 0
	var frames := 0
	var both := false
	while frames < 900 and not both:
		await get_tree().physics_frame
		frames += 1
		var primary := p.is_area_ready(target, 3.0)
		p.readiness_mode = "raycast"
		var fallback := p.is_area_ready(target, 3.0)
		p.readiness_mode = "block_info"
		if fallback and not primary:
			early += 1
		both = primary and fallback
	assert_true(both, "both checks report the destination ready (after %d physics frames)" % frames)
	assert_eq(early, 0, "the fallback never says ready while a collider is still missing")
	await place_player(w, geo.landing_dir)
