extends TestSuite
## The second planet loads from data alone and plays by its own rules.


func test_glimmerock_loads_and_differs() -> void:
	use_sandbox("planets")
	GameState.reset()
	var w := await make_world("glimmerock", false)
	var geo := w.planet.geology
	assert_lt(float(w.planet.config["gravity"]), 12.0, "low gravity moon")
	assert_near(w.planet.gravity_at(Vector3(0, geo.radius + 5.0, 0)).length(), float(w.planet.config["gravity"]), 0.01, "gravity from config")
	await physics(60)
	assert_true(w.player.is_on_floor(), "player lands on glimmerock")
	# its crust is made of its own materials
	var d := Vector3(0.5, 0.6, -0.6).normalized()
	var mat := GameData.mat_id(geo.material_at(d * (geo.surface_radius(d) - 0.5)))
	assert_true(mat in ["glimdust", "moonsilver"], "surface material is glimmer dust (got %s)" % mat)
	# starting shovel cannot dig here; the spade can
	await stream_to(w, d * (geo.surface_radius(d) + 2.0))
	var p := w.planet.ground_point(d) - d * 0.5
	assert_true(bool(w.dig.dig_sphere(p, 1.0, 1)["blocked"]), "power 1 bounces off glimmer dust")
	assert_true(bool(w.dig.dig_sphere(p, 1.0, 2)["ok"]), "power 2 digs it")
	# jumping is floatier than on pipseed
	var pip_g := float(GameData.planet("pipseed")["gravity"])
	assert_lt(w.player.jump_speed(), sqrt(2.0 * pip_g * Player.JUMP_HEIGHT), "lower take-off speed for the same jump height")
	assert_gt(float(w.props.get("formation_count")), 20.0, "crystal fields on the surface")
	assert_true(w.base != null, "base exists on the second planet")
	await free_world(w)


func test_planets_are_independent_seeds() -> void:
	var a := Geology.new(GameData.planet("pipseed"))
	var b := Geology.new(GameData.planet("glimmerock"))
	assert_true(a.radius != b.radius, "different radii")
	assert_true(a.layer_mat[0] != b.layer_mat[0], "different top layer")
