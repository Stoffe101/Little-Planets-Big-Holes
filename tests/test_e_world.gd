extends TestSuite
## Gameplay on a real (headless) planet: spawning, spherical gravity, movement, digging,
## hardness rules, tunnels, collisions, pickups, tools, selling, scanner, robots, secrets.

var w: World
var geo: Geology
const DIG_DIR := Vector3(0.52, 0.7, 0.49)       ## a quiet spot away from the base and caverns


func before_all() -> void:
	use_sandbox("world")
	GameState.reset()
	w = await make_world("pipseed", false)
	geo = w.planet.geology


func after_all() -> void:
	await free_world(w)


func _reset_progress() -> void:
	GameState.reset()
	w.pickups.clear()


# ------------------------------------------------------------------ spawning & gravity

func test_player_spawns_standing_on_the_ground() -> void:
	await physics(60)
	var p := w.player
	assert_true(p.is_on_floor(), "player is on the floor after spawning")
	var r := p.global_position.length()
	assert_near(r, geo.surface_radius(p.global_position.normalized()), 1.0, "standing at the surface radius")
	var r0 := r
	await physics(120)
	assert_near(w.player.global_position.length(), r0, 0.05, "does not sink or drift while idle")
	assert_gt(w.planet.load_time_ms, 0, "planet load time recorded")


func test_gravity_points_to_the_planet_centre_everywhere() -> void:
	for dir: Vector3 in [Vector3.UP, Vector3.DOWN, Vector3.RIGHT, Vector3.BACK, Vector3(-1, -1, 0.4), Vector3(0.3, -0.2, -1)]:
		var d := dir.normalized()
		var pos := d * (geo.radius + 10.0)
		var g := w.planet.gravity_at(pos)
		assert_gt(g.normalized().dot(-d), 0.9999, "gravity direction at %s" % str(d))
		assert_near(g.length(), float(w.planet.config["gravity"]), 0.01, "gravity strength")
		await place_player(w, d)
		await physics(40)
		assert_true(w.player.is_on_floor(), "lands on the floor at %s" % str(d))
		assert_gt(w.player.up.dot(d), 0.995, "player up-vector follows the planet at %s" % str(d))
		assert_gt(w.player.global_basis.y.dot(w.player.global_position.normalized()), 0.995, "body is upright")
		assert_near(w.player.global_basis.determinant(), 1.0, 0.001, "basis stays orthonormal")


func test_walking_follows_the_curve_of_the_planet() -> void:
	await place_player(w, Vector3(-0.5, 0.75, -0.4))
	var start := w.player.global_position
	w.player.forced_move = Vector2(0, 1)
	await physics(240)       # 4 seconds
	w.player.forced_move = Vector2.ZERO
	await physics(30)
	var end := w.player.global_position
	assert_gt(start.distance_to(end), 12.0, "walked a good distance")
	var alt := w.planet.altitude(end)
	assert_true(alt > -1.5 and alt < 3.5, "still on the surface (altitude %.2f)" % alt)
	assert_gt(w.player.up.dot(end.normalized()), 0.995, "re-oriented to the new 'down'")
	assert_true(w.player.is_on_floor(), "on the floor after walking")


func test_jumping() -> void:
	await place_player(w, Vector3(-0.3, 0.9, 0.3))
	var r0 := w.player.global_position.length()
	w.player.forced_move = Vector2.ZERO
	w.player.forced_jump = true
	var peak := r0
	for i in 70:
		await get_tree().physics_frame
		peak = maxf(peak, w.player.global_position.length())
	assert_gt(peak - r0, 0.9, "jump gains height")
	await physics(60)
	assert_true(w.player.is_on_floor(), "lands again")
	assert_near(w.player.global_position.length(), r0, 0.3, "back at ground level")


func test_zero_gravity_in_the_core() -> void:
	assert_lt(w.planet.gravity_at(Vector3(0.5, 0.2, 0.1)).length(), 0.5, "almost no gravity at the centre")
	await stream_to(w, Vector3(2.5, 0.0, 1.0), 4.0)
	w.player.teleport(Vector3(2.5, 0.0, 1.0), Vector3(-1, 0, 0))
	await physics(40)
	assert_true(w.player.in_zero_g, "zero-g mode inside the heart chamber")
	var p := w.player.global_position
	assert_true(is_finite(p.x) and is_finite(p.y) and is_finite(p.z), "position stays finite")
	assert_lt(p.length(), geo.core_radius + 1.0, "floats inside the chamber instead of falling")


# ------------------------------------------------------------------ digging

func test_dig_removes_ground_and_collision_follows() -> void:
	_reset_progress()
	var d := DIG_DIR.normalized()
	await stream_to(w, d * (geo.surface_radius(d) + 2.0))
	var surface := w.planet.ground_point(d)
	var before := ray(w, d * (geo.radius + 30.0), Vector3.ZERO)
	assert_false(before.is_empty(), "physics ray hits the terrain")
	var r_before := (before["position"] as Vector3).length()
	var center := surface - d * 0.4
	assert_true(w.planet.is_solid(center), "solid before digging")
	var res := w.dig.dig_sphere(center, 1.3, 1)
	assert_true(bool(res["ok"]), "dig succeeded")
	assert_gt(float(res["volume"]), 2.0, "removed some volume")
	assert_false((res["yields"] as Dictionary).is_empty(), "produced resources")
	assert_false(w.planet.is_solid(center), "air after digging (voxel data updates immediately)")
	var ok := await wait_until(func() -> bool:
		var h := ray(w, d * (geo.radius + 30.0), Vector3.ZERO)
		return not h.is_empty() and (h["position"] as Vector3).length() < r_before - 0.9)
	assert_true(ok, "collision mesh updated to the new hole")
	assert_eq(int(GameState.stats["digs"]), 1, "dig counted")


func test_yields_are_made_of_what_was_dug() -> void:
	_reset_progress()
	var d := Vector3(0.6, 0.6, -0.5).normalized()
	await stream_to(w, d * (geo.surface_radius(d) + 2.0))
	var surface := w.planet.ground_point(d)
	var res := w.dig.dig_sphere(surface - d * 0.7, 1.5, 1)
	assert_true(bool(res["ok"]), "dig ok")
	var total := 0
	for m: int in res["yields"]:
		total += int(res["yields"][m])
		assert_true(geo.hardness_of(m) <= 1, "only materials the tool can break are yielded")
	# ~7 m3 of soil at 0.5 units/m3 (ore pockets may add more)
	assert_true(total >= 2 and total <= 12, "plausible unit count (%d)" % total)
	assert_eq(int(res["dominant"]), GameData.mat_index("topsoil"), "surface dig is mostly soft soil")


func test_digging_air_does_nothing() -> void:
	var res := w.dig.dig_sphere(DIG_DIR.normalized() * (geo.radius + 25.0), 1.0, 5)
	assert_true(bool(res["empty"]), "empty result in the sky")
	assert_false(bool(res["ok"]), "not counted as a dig")


func test_digging_unloaded_terrain_is_refused() -> void:
	_reset_progress()
	await place_player(w, geo.landing_dir + Vector3(0.05, 0, 0))
	var anti := -geo.landing_dir
	var far := anti * (geo.surface_radius(anti) - 1.0)
	assert_false(w.planet.is_area_ready(far, 2.0), "the far side is not loaded at full resolution")
	var res := w.dig.dig_sphere(far, 1.5, 5)
	assert_true(bool(res.get("unloaded", false)), "dig reports unloaded terrain")
	assert_false(bool(res["ok"]), "nothing dug")
	assert_eq(int(GameState.stats["digs"]), 0, "not counted as a dig")
	var cap := w.dig.dig_capsule(far, far + anti.cross(Vector3.RIGHT).normalized() * 6.0, 1.5, 5)
	assert_false(bool(cap["ok"]), "capsule digs are refused too")


func test_weak_tools_bounce_off_hard_layers() -> void:
	_reset_progress()
	var d := Vector3(-0.6, 0.5, 0.62).normalized()
	var deep := d * (geo.surface_radius(d) - 9.0)       # dense clay / iron: hardness >= 2
	await stream_to(w, d * (geo.surface_radius(d) + 2.0), 12.0)
	assert_true(w.planet.is_solid(deep), "solid at depth")
	var res := w.dig.dig_sphere(deep, 1.2, 1)
	assert_true(bool(res["blocked"]), "power 1 is blocked 9 m down")
	assert_true(int(res["hard_material"]) >= 0, "reports which material was too hard")
	assert_true(w.planet.is_solid(deep), "terrain untouched by a blocked dig")
	assert_eq(int(GameState.stats["blocked_digs"]), 1, "blocked dig counted")
	var res2 := w.dig.dig_sphere(deep, 1.2, 5)
	assert_true(bool(res2["ok"]), "a strong tool digs the same spot")
	assert_false(w.planet.is_solid(deep), "now excavated")


func test_selective_dig_leaves_harder_material_standing() -> void:
	_reset_progress()
	var rng := RandomNumberGenerator.new()
	rng.seed = 314
	var soil := GameData.mat_index("topsoil")
	var tested := false
	for attempt in 200:
		var d := Vector3(rng.randf_range(-1, 1), rng.randf_range(0.1, 1), rng.randf_range(-1, 1)).normalized()
		if w.is_protected(d * geo.radius):
			continue
		var sr := geo.surface_radius(d)
		var soft_p := d * (sr - 2.9)
		var hard_p := d * (sr - 5.3)
		var center := d * (sr - 4.1)
		if geo.material_at(soft_p) != soil or geo.hardness_of(geo.material_at(hard_p)) < 2:
			continue
		await stream_to(w, d * (sr + 2.0), 8.0)
		if not w.planet.is_solid(soft_p) or not w.planet.is_solid(hard_p):
			continue
		var sv := w.dig.survey(center, 1.7, 1)
		if int(sv["hard"]) == 0 or float(sv["hard"]) / float(sv["solid"]) > 0.6:
			continue
		var res := w.dig.dig_sphere(center, 1.7, 1)
		assert_true(bool(res["ok"]), "mixed dig succeeds")
		assert_true(bool(res["hit_hard"]), "reports that it touched hard material")
		assert_false(w.planet.is_solid(soft_p), "soft soil inside the bite was removed")
		assert_true(w.planet.is_solid(hard_p), "hard material inside the bite is still there")
		for m: int in res["yields"]:
			assert_true(geo.hardness_of(m) <= 1, "nothing too hard was harvested")
		tested = true
		break
	assert_true(tested, "found a soil/clay boundary to test on")


func test_tunnel_into_a_hillside_is_walkable() -> void:
	_reset_progress()
	var d := Vector3(0.62, 0.50, 0.60).normalized()          # the tall hill
	var side := d.cross(Vector3.UP).normalized()
	var mouth := (d + side * 0.16).normalized()
	await stream_to(w, mouth * (geo.surface_radius(mouth) + 2.0), 18.0)
	var a := w.planet.ground_point(mouth) + mouth * 0.5
	var inward := (-mouth * 0.45 - side).normalized()
	var b := a + inward * 11.0
	assert_true(w.planet.is_solid(b), "end of the tunnel starts as solid rock")
	var res := w.dig.dig_capsule(a, b, 1.7, 9)
	assert_true(bool(res["ok"]), "capsule dig ok")
	assert_gt(float(res["volume"]), 40.0, "tunnel volume")
	for f: float in [0.2, 0.5, 0.8, 1.0]:
		assert_false(w.planet.is_solid(a.lerp(b, f)), "tunnel is open at %.1f" % f)
	assert_true(w.planet.is_solid(b + inward * 3.0), "rock beyond the tunnel is intact")
	# walk inside: stand at the far end and check floor + ceiling
	var up := w.planet.up_at(b)
	var has_floor := await wait_until(func() -> bool: return not ray(w, b, b - up * 4.0).is_empty())
	assert_true(has_floor, "tunnel floor has collision")
	w.player.teleport(b - up * 1.2, -inward)
	await physics(60)
	assert_true(w.player.is_on_floor(), "player stands on the tunnel floor")
	assert_gt(w.player.depth, 2.0, "player is underground")
	var ceiling := ray(w, w.player.global_position + up * 1.0, w.player.global_position + up * 6.0)
	assert_false(ceiling.is_empty(), "there is a ceiling overhead")


# ------------------------------------------------------------------ pickups, tools, economy

func test_pickups_fly_into_the_backpack() -> void:
	_reset_progress()
	await place_player(w, Vector3(0.1, 0.6, -0.8))
	var p := w.player
	var copper := GameData.mat_index("copper")
	w.pickups.spawn(copper, 3, p.global_position + p.up * 0.6 - p.global_basis.z * 1.4, Vector3.ZERO)
	assert_eq(w.pickups.count(), 1, "pickup spawned")
	var got := await wait_until(func() -> bool: return int(GameState.inventory.get("copper", 0)) == 3, 240)
	assert_true(got, "collected into the inventory")
	assert_eq(w.pickups.count(), 0, "pickup removed from the world")
	assert_eq(int(GameState.stats["collected_copper"]), 3, "collection stat tracked")


func test_full_backpack_leaves_loot_on_the_ground() -> void:
	_reset_progress()
	await place_player(w, Vector3(0.1, 0.6, -0.8))
	GameState.add_to_inventory("topsoil", GameState.capacity())
	var p := w.player
	w.pickups.spawn(GameData.mat_index("copper"), 2, p.global_position + p.up * 0.6 - p.global_basis.z * 1.2, Vector3.ZERO)
	await physics(150)
	assert_eq(w.pickups.count(), 1, "pickup stays in the world")
	assert_false(GameState.inventory.has("copper"), "nothing collected while full")
	GameState.sell_all()
	var got := await wait_until(func() -> bool: return int(GameState.inventory.get("copper", 0)) == 2, 300)
	assert_true(got, "collected once there is room again")


func test_shovel_swing_digs_through_the_tool_controller() -> void:
	_reset_progress()
	await place_player(w, Vector3(-0.2, 0.7, 0.68))
	w.player.pitch = deg_to_rad(-50.0)
	await frames(2)
	var vol0 := float(GameState.stats["volume_dug"])
	w.tools.forced_use_enabled = true
	w.tools.forced_use = true
	await physics(150)
	w.tools.forced_use = false
	await physics(90)
	assert_gt(float(int(GameState.stats["digs"])), 1.0, "several swings landed")
	assert_gt(float(GameState.stats["volume_dug"]), vol0 + 1.0, "ground was removed")
	assert_gt(float(GameState.inventory_count() + w.pickups.total_units()), 0.0, "resources came out")


func test_launch_pad_is_protected() -> void:
	var pad := geo.landing_dir * (geo.surface_radius(geo.landing_dir) - 1.0)
	assert_true(w.is_protected(pad), "ground under the rocket is shielded")
	assert_false(w.is_protected(DIG_DIR.normalized() * geo.radius), "elsewhere is fair game")
	assert_false(w.is_protected(geo.landing_dir * (geo.radius - 30.0)), "deep below the pad is not shielded")


func test_selling_on_the_pad_pays_out() -> void:
	_reset_progress()
	GameState.add_to_inventory("copper", 6)
	GameState.add_to_inventory("topsoil", 10)
	var expected := GameState.inventory_value()
	var base: RocketBase = w.base
	w.player.teleport(base.sell_pad_center + geo.landing_dir * 0.3, Vector3(1, 0, 0))
	var sold := await wait_until(func() -> bool: return GameState.inventory_count() == 0, 200)
	assert_true(sold, "inventory sold by standing on the pad")
	assert_eq(GameState.money, expected, "credits equal the inventory value")
	assert_eq(int(GameState.stats["sales"]), 1, "one sale")


func test_crystal_formation_needs_power_then_shatters() -> void:
	_reset_progress()
	await place_player(w, Vector3(0.7, 0.2, 0.69))
	var f := Formation.new()
	f.flag_key = "test/formation"
	f.setup(GameData.mat_index("pipquartz"), 6, 1.0, [], 7)
	w.add_child(f)
	f.global_position = w.player.global_position - w.player.global_basis.z * 2.0
	assert_false(f.hit(1, w), "power 1 cannot crack pip quartz")
	assert_true(is_instance_valid(f) and f.hits_left == 1, "untouched")
	assert_true(f.hit(2, w), "power 2 cracks it")
	await frames(2)
	assert_true(GameState.has_flag("test/formation"), "harvest remembered")
	assert_gt(float(w.pickups.total_units() + int(GameState.inventory.get("pipquartz", 0))), 5.0, "gem chunks released")


func test_scanner_requires_gear_and_finds_ore() -> void:
	_reset_progress()
	await place_player(w, Vector3(0.2, 0.9, 0.4))
	var sc: Scanner = w.scanner
	sc.cooldown = 0.0
	assert_false(sc.try_scan(), "no scanner owned")
	GameState.gear_levels["scanner"] = 1
	assert_true(sc.try_scan(), "scan with the pocket pinger")
	assert_eq(int(GameState.stats["scans"]), 1, "scan counted")
	assert_gt(sc.cooldown, 0.0, "cooldown started")
	assert_false(sc.try_scan(), "cannot spam the scanner")
	assert_gt(float(sc._markers.size()), 0.0, "markers placed on nearby ore")


func test_cannon_blasts_a_crater() -> void:
	_reset_progress()
	await place_player(w, Vector3(-0.7, 0.3, 0.65))
	GameState.tiers["cannon"] = 1
	GameState.tools_changed.emit()
	GameState.set_equipped("cannon")
	await physics(60)
	await frames(30)
	assert_eq(w.tools.family_id, "cannon", "cannon equipped")
	w.player.pitch = deg_to_rad(-35.0)
	await frames(2)
	var vol0 := float(GameState.stats["volume_dug"])
	w.tools.forced_use_enabled = true
	w.tools.forced_use = true
	await physics(3)
	w.tools.forced_use = false
	var boomed := await wait_until(func() -> bool: return float(GameState.stats["volume_dug"]) > vol0 + 20.0, 400)
	assert_true(boomed, "a large crater was excavated")
	GameState.set_equipped("shovel")
	await physics(40)
	await frames(30)


func test_helper_bot_hauls_loot_to_the_sell_station() -> void:
	_reset_progress()
	GameState.discover("dormant_bot")
	GameState.gear_levels["robot"] = 1
	GameState.gear_changed.emit("robot")
	var rm: RobotManager = w.robots
	assert_eq(rm.bots.size(), 1, "one bot spawned")
	# drop loot ~14 m from the base, and park the player on the far side of the planet
	var d := (geo.landing_dir + Vector3(0.28, 0, 0.05)).normalized()
	var ground := w.planet.ground_point(d)
	for i in 5:
		w.pickups.spawn(GameData.mat_index("copper"), 2, ground + d * 0.6 + Vector3(i * 0.3, 0, 0), Vector3.ZERO)
	await place_player(w, -geo.landing_dir)
	var money0 := GameState.money
	var earned := await wait_until(func() -> bool: return int(GameState.stats.get("robot_earned", 0)) > 0, 3600)
	assert_true(earned, "the bot sold something within a minute")
	assert_gt(float(GameState.money), float(money0), "credits arrived without the player")
	GameState.gear_levels["robot"] = 0
	GameState.gear_changed.emit("robot")
	assert_eq(rm.bots.size(), 0, "bots removed when gear is reset")


# ------------------------------------------------------------------ secrets

func test_artifact_pickup_records_a_discovery() -> void:
	_reset_progress()
	var sm: SecretsManager = w.secrets
	var n := sm.artifacts.size()
	assert_gt(float(n), 3.0, "artifacts are buried on the planet")
	for a in sm.artifacts:
		await stream_to(w, a["pos"], 3.0)
		assert_false(w.planet.is_solid(a["pos"]), "artifact %s sits in an open pocket or cavern" % a["id"])
	# (streaming into the caverns above discovered them, which pays their own rewards)
	var money0 := GameState.money
	sm.collect("time_capsule")
	assert_true(GameState.has_discovery("time_capsule"), "discovery recorded")
	assert_eq(sm.artifacts.size(), n - 1, "artifact removed from the world")
	assert_eq(GameState.money - money0, int(GameData.discovery("time_capsule")["reward"]), "reward paid")


func test_entering_a_hidden_cavern_discovers_it() -> void:
	_reset_progress()
	for c in geo.cavities:
		if c["id"] == "mushroom_hollow":
			await stream_to(w, c["center"], 3.0)
			assert_false(w.planet.is_solid(c["center"]), "cavern is hollow")
			w.player.teleport(c["center"], Vector3(1, 0, 0))
	var found := await wait_until(func() -> bool: return GameState.has_discovery("mushroom_hollow"), 120)
	assert_true(found, "walking into the hollow discovers it")


func test_touching_the_heart_awakens_the_planet() -> void:
	_reset_progress()
	await stream_to(w, Vector3(0.5, 0.2, 0.1), geo.core_radius + 5.0)
	assert_false(w.planet.is_solid(Vector3.ZERO), "core chamber is hollow")
	assert_true(w.planet.is_solid(Vector3(geo.core_radius + 4.0, 0, 0)), "surrounded by rock")
	var sm: SecretsManager = w.secrets
	sm.touch_heart()
	assert_true(GameState.has_discovery("pip_heart"), "heart discovery recorded")
	await frames(60)
	assert_gt(w.bloom, 0.0, "planet bloom begins")
	assert_near(GameState.sell_multiplier(), 1.2, 0.001, "blessing boosts sell value")


# ------------------------------------------------------------------ robustness

func test_repeated_digging_stays_stable_and_fast() -> void:
	_reset_progress()
	var rng := RandomNumberGenerator.new()
	rng.seed = 2718
	# Hammer one streamed-in area (everything editable lies within ~70 m of the player).
	var site := Vector3(-0.4, -0.6, 0.7).normalized()
	await stream_to(w, site * (geo.surface_radius(site) - 8.0), 30.0)
	var t1 := site.cross(Vector3.UP).normalized()
	var t2 := site.cross(t1)
	var digs0 := w.dig.total_digs
	var usec0 := w.dig.total_dig_usec
	for i in 400:
		var d := (site + (t1 * rng.randf_range(-1, 1) + t2 * rng.randf_range(-1, 1)) * (22.0 / geo.radius)).normalized()
		var depth := rng.randf_range(0.0, 20.0)
		w.dig.dig_sphere(d * (geo.surface_radius(d) - depth), rng.randf_range(0.8, 3.2), 1 + rng.randi() % 5)
		if i % 20 == 0:
			await get_tree().physics_frame
	var n := w.dig.total_digs - digs0
	assert_gt(float(n), 100.0, "many digs landed")
	var avg_ms := float(w.dig.total_dig_usec - usec0) / 1000.0 / float(maxi(n, 1))
	print("         avg dig time over %d digs: %.3f ms" % [n, avg_ms])
	assert_lt(avg_ms, 25.0, "average dig stays well under one frame")
	# all queued meshing work drains
	var drained := await wait_until(func() -> bool:
		var t: Dictionary = VoxelEngine.get_stats()["tasks"]
		return int(t["meshing"]) == 0 and int(t["generation"]) == 0, 1200)
	assert_true(drained, "voxel task queues drain after heavy editing")
	await place_player(w, Vector3(0.1, 0.95, 0.2))
	assert_true(w.player.is_on_floor(), "world is still playable afterwards")
