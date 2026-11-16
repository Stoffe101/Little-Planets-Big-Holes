extends TestSuite
## "Dig a tunnel, leave, come back, find the same tunnel": terrain edits and progress survive
## a full save / unload / reload cycle.

var tunnel_points: Array[Vector3] = []
var sdf_after_dig: Array[float] = []
var untouched_points: Array[Vector3] = []
var sdf_untouched: Array[float] = []


func test_tunnel_and_progress_survive_reload() -> void:
	use_sandbox("persist")
	GameState.reset()
	var w := await make_world("pipseed", true)
	var geo := w.planet.geology
	var d := Vector3(-0.4, 0.55, 0.73).normalized()
	var side := d.cross(Vector3.UP).normalized()
	var a := w.planet.ground_point(d) + d * 0.5
	var b := a - d * 7.0 + side * 9.0
	# a control sample: all solid before we dig
	for i in 12:
		tunnel_points.append(a.lerp(b, 0.15 + 0.07 * i))
	var solid_before := 0
	for p in tunnel_points:
		if w.planet.is_solid(p):
			solid_before += 1
	assert_gt(float(solid_before), 9.0, "the tunnel route starts as solid ground")
	for i in 20:
		var dir := Vector3(sin(i * 1.7), -0.8, cos(i * 2.3)).normalized()
		untouched_points.append(dir * (geo.surface_radius(dir) - 3.0 - 0.5 * i))
		sdf_untouched.append(w.planet.sdf_at(untouched_points[i]))

	assert_true(bool(w.dig.dig_capsule(a, b, 1.6, 9)["ok"]), "tunnel dug")
	assert_true(bool(w.dig.dig_sphere(b, 3.0, 9)["ok"]), "chamber dug at the end")
	for p in tunnel_points:
		assert_false(w.planet.is_solid(p), "tunnel point is open")
		sdf_after_dig.append(w.planet.sdf_at(p))
	GameState.money = 2468
	GameState.add_to_inventory("gold", 3)
	GameState.discover("old_helmet")
	var money := GameState.money
	await physics(30)
	assert_true(w.save_all(true), "save (progress + terrain) succeeded")
	var db := ProjectSettings.globalize_path(SaveSystem.terrain_db_path("pipseed"))
	await free_world(w)
	assert_true(FileAccess.file_exists(db), "terrain database written")
	assert_gt(float(FileAccess.get_file_as_bytes(db).size()), 1000.0, "terrain database has content")

	# ---- a brand new session
	GameState.reset()
	assert_true(SaveSystem.load_game(), "progress loads")
	assert_eq(GameState.money, money, "money restored")
	assert_eq(int(GameState.inventory["gold"]), 3, "inventory restored")
	assert_true(GameState.has_discovery("old_helmet"), "discoveries restored")
	var w2 := await make_world("pipseed", true)
	for i in tunnel_points.size():
		assert_false(w2.planet.is_solid(tunnel_points[i]), "tunnel point %d is still open after reload" % i)
		assert_near(w2.planet.sdf_at(tunnel_points[i]), sdf_after_dig[i], 0.02, "edited SDF value preserved")
	for i in untouched_points.size():
		assert_near(w2.planet.sdf_at(untouched_points[i]), sdf_untouched[i], 0.0001, "untouched ground regenerates identically")
	# the tunnel is physically there: stand in the end chamber
	var up := w2.planet.up_at(b)
	w2.player.teleport(b - up * 2.0, Vector3(1, 0, 0))
	await physics(90)
	assert_true(w2.player.is_on_floor(), "player can stand inside the reloaded chamber")
	assert_gt(w2.player.depth, 2.0, "and is underground")
	# discovered artifacts stay collected
	var sm: SecretsManager = w2.secrets
	for art in sm.artifacts:
		assert_true(art["id"] != "old_helmet", "collected artifact does not respawn")
	await free_world(w2)


func test_fresh_save_slot_has_pristine_terrain() -> void:
	# Control for the test above: a different (empty) slot must NOT contain the tunnel.
	use_sandbox("persist_control")
	GameState.reset()
	var w := await make_world("pipseed", true)
	var solid := 0
	for p in tunnel_points:
		if w.planet.is_solid(p):
			solid += 1
	assert_gt(float(solid), 9.0, "tunnel is absent in a fresh slot")
	await free_world(w)
