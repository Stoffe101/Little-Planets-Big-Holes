extends TestSuite
## Stability of the streamed planets under stress: collision that matches the voxels where mesh
## blocks meet, tunnels across block faces, many save/load cycles, repeated relay travel and
## fast jetpack traversal on both planets. Mesh blocks are 32 voxels (16 m), data blocks 16
## voxels (8 m): the boundaries these tests aim at.

var w: World
var geo: Geology


func before_all() -> void:
	use_sandbox("stability")
	GameState.reset()
	w = await make_world("pipseed", false)
	geo = w.planet.geology


func after_all() -> void:
	await free_world(w)


func _block_m() -> float:
	return float(w.planet.mesh_block_size) * geo.voxel_size


## A mesh-block corner 5-12 m under the surface, 25-45 m from the outpost.
func _buried_corner() -> Vector3:
	var b := _block_m()
	var base := geo.landing_dir * geo.surface_radius(geo.landing_dir)
	var best := Vector3.ZERO
	for ix in range(-4, 5):
		for iy in range(-4, 5):
			for iz in range(-4, 5):
				var c := ((base / b).round() + Vector3(ix, iy, iz)) * b
				var dist := c.distance_to(base)
				if dist < 25.0 or dist > 45.0:
					continue
				var depth := geo.surface_radius(c.normalized()) - c.length()
				if depth > 5.0 and depth < 12.0 and not w.is_protected(c):
					return c
	return best


## Distance along a ray to where the voxel SDF changes sign (marching, then refined).
func _voxel_hit(from: Vector3, dir: Vector3, max_d: float) -> float:
	var step := 0.1
	var t := 0.0
	while t < max_d:
		if w.planet.sdf_at(from + dir * t) < 0.0:
			var a := t - step
			var b := t
			for i in 8:
				var m := (a + b) * 0.5
				if w.planet.sdf_at(from + dir * m) < 0.0:
					b = m
				else:
					a = m
			return (a + b) * 0.5
		t += step
	return -1.0


func test_collision_matches_the_voxels_around_a_block_corner() -> void:
	var c := _buried_corner()
	assert_true(c != Vector3.ZERO, "found a buried mesh-block corner near the outpost")
	var up := c.normalized()
	await stream_to(w, (c.normalized() * (geo.surface_radius(c.normalized()) + 2.0)), 18.0)
	# a cavity centred on the corner: its walls belong to all eight blocks that meet there
	assert_true(bool(w.dig.dig_sphere(c, 3.4, 9)["ok"]), "cavity dug at the block corner")
	var dirs: Array[Vector3] = []
	for x in [-1, 0, 1]:
		for y in [-1, 0, 1]:
			for z in [-1, 0, 1]:
				if x != 0 or y != 0 or z != 0:
					dirs.append(Vector3(x, y, z).normalized())
	var agree := func() -> bool:
		for d: Vector3 in dirs:
			var vox := _voxel_hit(c, d, 8.0)
			var hit := ray(w, c, c + d * 8.0)
			if vox < 0.0 or hit.is_empty() or absf(c.distance_to(hit["position"]) - vox) > 0.3:
				return false
		return true
	var ok: bool = await wait_until(agree, 240)
	assert_true(ok, "all 26 rays from the corner hit the collider where the voxels say the wall is")
	var worst := 0.0
	for d in dirs:
		var vox := _voxel_hit(c, d, 8.0)
		var hit := ray(w, c, c + d * 8.0)
		if not hit.is_empty() and vox >= 0.0:
			worst = maxf(worst, absf(c.distance_to(hit["position"]) - vox))
	assert_lt(worst, 0.3, "collider within %.2f m of the voxel surface in every block" % worst)
	# and a second bite that straddles the corner from above changes all of them again
	assert_true(bool(w.dig.dig_sphere(c + up * 2.0, 2.6, 9)["ok"]), "second bite across the corner")
	ok = await wait_until(agree, 240)
	assert_true(ok, "colliders follow a second edit in every block around the corner")


func test_a_tunnel_across_block_faces_is_walkable() -> void:
	var d := (geo.landing_dir + Vector3(0.0, 0.0, -0.09)).normalized()
	await stream_to(w, d * (geo.surface_radius(d) + 2.0), 22.0)
	var side := d.cross(Vector3(1, 0, 0.2)).normalized()
	var start := d * (geo.surface_radius(d) - 5.0)
	var finish := start + side * 30.0
	finish = finish.normalized() * (geo.surface_radius(finish.normalized()) - 5.0)
	# how many mesh-block faces does it cross?
	var b := _block_m()
	var faces := 0
	var prev := (start / b).floor()
	for i in 61:
		var cell := (start.lerp(finish, i / 60.0) / b).floor()
		faces += int(cell.x != prev.x) + int(cell.y != prev.y) + int(cell.z != prev.z)
		prev = cell
	assert_gt(float(faces), 1.0, "the tunnel crosses %d mesh-block faces" % faces)
	assert_true(bool(w.dig.dig_capsule(start, finish, 1.7, 9)["ok"]), "tunnel dug")
	await physics(20)
	w.player.teleport(start, finish - start)
	await wait_until(func() -> bool: return w.planet.is_area_ready(start, 3.0), 240)
	var lowest_gap := INF
	w.player.forced_move = Vector2(0, 1)
	for i in 300:
		await get_tree().physics_frame
		var p := w.player.global_position
		var fwd := (finish - p)
		fwd -= w.player.up * fwd.dot(w.player.up)
		if fwd.length() > 0.5:
			w.player.look_at(p + fwd, w.player.up)      # keep heading down the tunnel
		var t := clampf((p - start).dot(finish - start) / (finish - start).length_squared(), 0.0, 1.0)
		lowest_gap = minf(lowest_gap, p.length() - (start.lerp(finish, t).length() - 1.7))
		if p.distance_to(finish) < 2.5:
			break
	w.player.forced_move = Vector2.INF
	var walked := start.distance_to(w.player.global_position)
	assert_gt(walked, 22.0, "walked %.1f m along the tunnel across the block faces" % walked)
	assert_gt(lowest_gap, -0.6, "never fell through the tunnel floor (lowest %.2f m vs the floor)" % lowest_gap)
	assert_true(w.player.is_on_floor(), "standing on the tunnel floor at the end")


func test_repeated_save_and_load_keeps_every_hole() -> void:
	use_sandbox("stability_cycles")
	var holes: Array[Vector3] = []
	var cycles := 4
	for cycle in cycles:
		if cycle == 0:
			GameState.reset()
		else:
			assert_true(SaveSystem.load_game(), "cycle %d: save loads" % cycle)
		var ww := await make_world("pipseed", true)
		var g := ww.planet.geology
		for h in holes:
			await stream_to(ww, h.normalized() * (g.surface_radius(h.normalized()) + 2.0), 6.0)
			assert_gt(ww.planet.sdf_at(h), 0.0, "cycle %d: an earlier hole is still open" % cycle)
		for k in 2:
			var dir := (g.landing_dir + Vector3(0.03 + 0.025 * cycle, 0.0, -0.06 + 0.12 * k)).normalized()
			await stream_to(ww, dir * (g.surface_radius(dir) + 2.0), 6.0)
			var c := dir * (g.surface_radius(dir) - 1.2)
			assert_true(bool(ww.dig.dig_sphere(c, 1.8, 9)["ok"]), "cycle %d: dug hole %d" % [cycle, k])
			holes.append(c)
		GameState.money = 1000 + cycle
		assert_true(ww.save_all(true), "cycle %d: saved" % cycle)
		await free_world(ww)
	assert_true(SaveSystem.load_game(), "final load")
	assert_eq(GameState.money, 1000 + cycles - 1, "progress from the last cycle")
	var ww2 := await make_world("pipseed", true)
	var open := 0
	for h in holes:
		await stream_to(ww2, h.normalized() * (ww2.planet.geology.surface_radius(h.normalized()) + 2.0), 6.0)
		if ww2.planet.sdf_at(h) > 0.0:
			open += 1
	assert_eq(open, holes.size(), "all %d holes from %d sessions are still there" % [holes.size(), cycles])
	await free_world(ww2)
	use_sandbox("stability")


func test_repeated_relay_travel_always_lands_on_the_ground() -> void:
	var nav := w.nav
	for r in nav.relays:
		GameState.set_flag(nav._flag("relay", r["id"]))
	await place_player(w, geo.landing_dir)
	var route: Array[String] = []
	for r in nav.relays:
		route.append(str(r["id"]))
		route.append("outpost")
	var mem0 := OS.get_static_memory_usage()
	var worst := 0.0
	for to in route:
		assert_true(nav.travel(to), "travel to %s" % to)
		var done := await wait_until(func() -> bool: return not w.transit.active, 1500)
		assert_true(done, "%s: transit finished" % to)
		await physics(30)
		var p := w.player.global_position
		var gap := p.length() - w.planet.ground_point(p.normalized()).length()
		worst = maxf(worst, absf(gap))
		assert_true(w.player.is_on_floor(), "%s: standing on the ground" % to)
		assert_gt(gap, -0.3, "%s: not inside the ground (%.2f m)" % [to, gap])
	assert_lt(worst, 0.6, "every arrival within %.2f m of the real ground" % worst)
	var grew := float(OS.get_static_memory_usage() - mem0) / 1048576.0
	assert_lt(grew, 200.0, "static memory grew %.0f MB over %d relay jumps" % [grew, route.size()])


## Sprint with the best boots and jetpack hops across country for ~12 s: the loader keeps up
## (the player is never held long) and the player never ends up under the ground.
func _run_across(ww: World, seconds: float) -> Dictionary:
	GameState.gear_levels["boots"] = GameState.gear_max_level("boots")
	GameState.gear_levels["jets"] = GameState.gear_max_level("jets")
	var p := ww.player
	var start := p.global_position
	p.forced_move = Vector2(0, 1)
	p.forced_sprint = true
	var held := 0
	var below := 0
	var frames := int(seconds * 60.0)
	for i in frames:
		if i % 50 == 0:
			p.forced_jump = true
		await get_tree().physics_frame
		if p.waiting_for_ground:
			held += 1
		var pos := p.global_position
		if ww.planet.is_loaded_at(pos) and ww.planet.sdf_at(pos + p.up * 0.5) < -1.0:
			below += 1
	p.forced_move = Vector2.INF
	p.forced_sprint = false
	return {"dist": start.distance_to(p.global_position), "held": held, "below": below, "frames": frames}


func test_fast_jetpack_traversal_on_both_planets() -> void:
	var s0 := (geo.landing_dir + Vector3(0.0, 0.0, -0.05)).normalized()
	await place_player(w, s0, s0 - geo.landing_dir)
	var r := await _run_across(w, 12.0)
	assert_gt(float(r["dist"]), 100.0, "Pipseed: covered %.0f m" % r["dist"])
	assert_lt(float(r["held"]), float(r["frames"]) * 0.05, "Pipseed: held waiting for ground %d of %d frames" % [r["held"], r["frames"]])
	assert_eq(int(r["below"]), 0, "Pipseed: never inside the ground")
	var g := await make_world("glimmerock", false)
	var gl := g.planet.geology.landing_dir
	var start := (gl + Vector3(0.12, 0.0, 0.05)).normalized()
	await place_player(g, start, start - gl)     # heading away from the outpost
	r = await _run_across(g, 12.0)
	assert_gt(float(r["dist"]), 100.0, "Glimmerock: covered %.0f m" % r["dist"])
	assert_lt(float(r["held"]), float(r["frames"]) * 0.05, "Glimmerock: held %d of %d frames" % [r["held"], r["frames"]])
	assert_eq(int(r["below"]), 0, "Glimmerock: never inside the ground")
	await free_world(g)
	GameState.current_planet = "pipseed"
