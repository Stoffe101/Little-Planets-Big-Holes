extends TestSuite
## Finding your way on big planets: regions, survey relays, travel rules, recall, waypoint,
## compass bearings and the map projection.

var w: World
var geo: Geology
var nav: Navigation


func before_all() -> void:
	use_sandbox("navigation")
	GameState.reset()
	w = await make_world("pipseed", false)
	geo = w.planet.geology
	nav = w.nav


func after_all() -> void:
	GameState.reset()
	await free_world(w)


func test_relays_stand_on_the_planet_and_are_shielded() -> void:
	assert_gt(float(nav.relays.size()), 4.0, "Pipseed has survey relays")
	for r in nav.relays:
		var p: Vector3 = r["pos"]
		assert_near(p.length(), geo.surface_radius(p.normalized()), 0.01, "%s sits on the original surface" % r["id"])
		assert_true(w.is_protected(p - (r["up"] as Vector3) * 1.0), "%s footing is shielded from digging" % r["id"])
		assert_gt(nav.surface_distance(p, geo.spawn_position()), 100.0, "%s is out in the regions" % r["id"])
		var region := nav.region_at(p)
		assert_false(region.is_empty(), "%s stands inside a named region" % r["id"])


func test_every_planets_relays_sit_in_regions() -> void:
	for pid: String in GameData.planet_order:
		var cfg := GameData.planet(pid)
		var g := Geology.new(cfg)
		var relays: Array = cfg.get("relays", [])
		assert_gt(float(relays.size()), 2.0, "%s has relays" % pid)
		for r: Dictionary in relays:
			var d := Vector3(r["dir"][0], r["dir"][1], r["dir"][2]).normalized()
			assert_false(g.region_at(d).is_empty(), "%s / %s stands in a named region" % [pid, r["id"]])
			for c in g.cavities:
				assert_gt(((c["center"] as Vector3) - d * g.radius).length(), float(c["radius"]) + 6.0, "%s / %s is not above a cavern" % [pid, r["id"]])


func test_regions_are_announced_and_remembered() -> void:
	var seen: Array[String] = []
	var cb := func(r: Dictionary) -> void: seen.append(str(r["id"]))
	nav.region_changed.connect(cb)
	var target := {}
	for r in geo.regions:
		if r["id"] == "copperfold":
			target = r
	assert_false(target.is_empty(), "Copperfold Vale exists")
	var d: Vector3 = target["dir"]
	await place_player(w, d)
	await physics(30)
	assert_eq(str(nav.current_region.get("id", "")), "copperfold", "current region updated")
	assert_true(seen.has("copperfold"), "entering the region is announced")
	assert_true(nav.region_visited("copperfold"), "and remembered")
	nav.region_changed.disconnect(cb)


func test_relay_activation_and_travel_rules() -> void:
	var rel: Dictionary = nav.relays[0]
	var far: Dictionary = nav.relays[nav.relays.size() - 1]
	assert_false(nav.relay_active(rel["id"]), "relays start offline")
	# far away from any relay or the outpost: no travel except recall
	var lone := (geo.landing_dir + Vector3(0.0, 0.0, -0.45)).normalized()
	await place_player(w, lone)
	assert_eq(nav.travel_origin(), "", "nowhere to travel from out in the field")
	assert_false(nav.travel(rel["id"]), "cannot jump to a relay from the field")
	# walk up to the relay: it comes online
	var up: Vector3 = rel["up"]
	await place_player(w, ((rel["pos"] as Vector3) + up.cross(Vector3.RIGHT).normalized() * 4.0).normalized())
	var online := await wait_until(func() -> bool: return nav.relay_active(rel["id"]), 120)
	assert_true(online, "standing next to a relay brings it online")
	assert_eq(nav.travel_origin(), str(rel["id"]), "you can travel from an online relay")
	# recall to the outpost from anywhere
	assert_true(nav.travel("outpost"), "recall to the outpost")
	var home := await wait_until(func() -> bool: return w.planet.is_area_ready(w.player.global_position, 3.0) and w.player.is_on_floor(), 900)
	assert_true(home, "landed at the outpost after streaming in")
	assert_lt(w.player.global_position.distance_to(geo.spawn_position()), 20.0, "next to the outpost")
	assert_eq(nav.travel_origin(), "outpost", "the outpost is a travel point")
	assert_false(nav.travel(far["id"]), "an offline relay is not a destination")
	assert_true(nav.travel(rel["id"]), "travel from the outpost to the online relay")
	var there := await wait_until(func() -> bool: return w.planet.is_area_ready(w.player.global_position, 3.0) and w.player.is_on_floor(), 900)
	assert_true(there, "standing on the ground at the relay")
	assert_lt(w.player.global_position.distance_to(rel["pos"]), 8.0, "beside the relay")
	assert_gt(float(GameState.stats.get("travels", 0)), 1.0, "travels counted")


func test_compass_bearings_and_heading() -> void:
	await place_player(w, geo.landing_dir + Vector3(0.05, 0, 0.0))
	var p := w.player
	var fwd := -p.camera.global_basis.z
	var flat := (fwd - p.up * fwd.dot(p.up)).normalized()
	var right := flat.cross(p.up).normalized()
	assert_lt(absf(nav.bearing_to(p.global_position + flat * 30.0)), 0.02, "a point straight ahead has bearing 0")
	assert_gt(nav.bearing_to(p.global_position + right * 30.0), 1.4, "a point to the right is +90 deg")
	assert_lt(nav.bearing_to(p.global_position - right * 30.0), -1.4, "a point to the left is -90 deg")
	# heading: face the -Z pole and the heading is ~0
	var north := Navigation.NORTH - p.up * Navigation.NORTH.dot(p.up)
	p.teleport(p.global_position, north)
	await frames(2)
	assert_lt(absf(wrapf(nav.heading(), -PI, PI)), 0.05, "facing north reads heading 0")


func test_map_projection_round_trips_and_keeps_distances() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	for i in 50:
		var d := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized()
		if d.dot(-geo.landing_dir) > 0.999:
			continue
		var back := nav.from_map(nav.to_map(d))
		assert_gt(back.dot(d), 0.9999, "map projection round trip")
		# azimuthal equidistant: distance from the centre is proportional to the map radius
		var t := acos(clampf(d.dot(geo.landing_dir), -1.0, 1.0))
		assert_near(nav.to_map(d).length(), t / PI, 0.0001, "true distance from home")


func test_waypoint_persists_in_the_save() -> void:
	var d := (geo.landing_dir + Vector3(0.3, 0, 0.1)).normalized()
	nav.set_waypoint(d)
	var wp: Variant = nav.waypoint()
	assert_true(wp != null, "waypoint set")
	var found := false
	for m: Dictionary in nav.markers():
		if m["kind"] == "waypoint":
			found = true
	assert_true(found, "waypoint shows on the compass and map")
	var dict := GameState.to_dict()
	GameState.reset()
	assert_true(GameState.from_dict(JSON.parse_string(JSON.stringify(dict))), "save round trip")
	var wp2: Variant = nav.waypoint()
	assert_true(wp2 != null and (wp2 as Vector3).distance_to(wp) < 0.01, "waypoint survives save and load")
	nav.set_waypoint(null)
	assert_true(nav.waypoint() == null, "waypoint cleared")


func test_map_image_renders_relief() -> void:
	var grass: Array = (w.planet.config.get("palette", {}) as Dictionary).get("grass", ["#7d9a5e", "#6b8f66"])
	var img := MapUi.render_image(geo, grass, 48)
	assert_eq(img.get_width(), 48, "map image size")
	assert_eq(img.get_pixel(24, 24).a, 1.0, "the planet disc is opaque")
	assert_eq(img.get_pixel(0, 0).a, 0.0, "corners outside the disc are clear")
	var distinct := {}
	for y in range(4, 44, 4):
		for x in range(4, 44, 4):
			distinct[img.get_pixel(x, y).to_html(false)] = true
	assert_gt(float(distinct.size()), 12.0, "relief and regions vary across the map")
