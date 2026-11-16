extends TestSuite
## Activities on big planets: survey contracts, the Auto-Borer (a machine that really digs),
## and helper-bot work zones that unload at relays.

var w: World
var geo: Geology


func before_all() -> void:
	use_sandbox("activities")
	GameState.reset()
	w = await make_world("pipseed", false)
	geo = w.planet.geology


func after_all() -> void:
	GameState.reset()
	await free_world(w)


func test_contracts_are_deterministic_and_pay_out() -> void:
	var c := w.contracts.current()
	assert_false(c.is_empty(), "a contract is open from the start")
	assert_eq(int(c["k"]), 0, "the first one")
	var again := w.contracts.make(0)
	assert_eq(str(again["text"]), str(c["text"]), "same slot, same contract")
	for k in 6:
		var ck := w.contracts.make(k)
		assert_true(str(ck["kind"]) in ["relay", "deliver", "depth"], "contract %d has a known kind" % k)
		assert_gt(float(ck["reward"]), 0.0, "contract %d pays" % k)
		assert_false(str(ck["text"]).is_empty(), "contract %d is described" % k)
	# force a delivery contract and fulfil it through ordinary sales (player and bots)
	var dc := {}
	for k in 6:
		if str(w.contracts.make(k)["kind"]) == "deliver":
			dc = w.contracts.make(k)
			break
	assert_false(dc.is_empty(), "the cycle includes deliveries")
	GameState.flags["contract/pipseed"] = dc
	var mid := str(dc["target"])
	var money0 := GameState.money
	GameState.add_to_inventory(mid, 5)
	GameState.sell_all()
	assert_eq(int(w.contracts.current()["progress"]), 5, "a sale at the Depot counts")
	GameState.sell_units(mid, int(dc["amount"]), false)     # a helper bot's delivery
	assert_true(int(w.contracts.current()["k"]) == int(dc["k"]) + 1, "completed, the next contract opened")
	assert_gt(float(GameState.money - money0), float(dc["reward"]), "reward paid on top of the sale value")
	assert_eq(int(GameState.stats.get("contracts_done", 0)), 1, "counted")


func test_relay_and_depth_contracts_track_the_world() -> void:
	# relay contract: bring the target relay online
	var rc := {}
	for k in 6:
		var c := w.contracts.make(k)
		if str(c["kind"]) == "relay":
			rc = c
			break
	assert_false(rc.is_empty(), "the cycle includes relay contracts")
	GameState.flags["contract/pipseed"] = rc
	GameState.set_flag("relay/pipseed/%s" % rc["target"])
	var done := await wait_until(func() -> bool: return int(w.contracts.current().get("k", -1)) != int(rc["k"]), 120)
	assert_true(done, "bringing the relay online completes the contract")
	# depth contract: dig down inside the named region
	var region: Dictionary = geo.regions[1]
	var dc := {"k": 99, "kind": "depth", "target": region["id"], "amount": 4, "progress": 0, "reward": 50, "text": "test"}
	GameState.flags["contract/pipseed"] = dc
	var d: Vector3 = region["dir"]
	await place_player(w, d)
	var top := w.planet.ground_point(d)
	assert_true(bool(w.dig.dig_capsule(top + d * 0.5, top - d * 6.0, 1.5, 9)["ok"]), "dug a shaft")
	await wait_until(func() -> bool: return not ray(w, top - d * 3.0, top - d * 9.0).is_empty())
	w.player.teleport(top - d * 5.0, Vector3.FORWARD)
	var deep := await wait_until(func() -> bool: return int(w.contracts.current().get("k", -1)) == 100, 300)
	assert_true(deep, "standing deep enough in the region completes it")


func test_auto_borer_sinks_a_real_shaft_and_respects_streaming() -> void:
	var b := w.borer
	GameState.gear_levels["borer"] = 0
	b.toggle()
	assert_false(b.deployed, "needs the gear")
	GameState.gear_levels["borer"] = 1
	var site := (geo.landing_dir + Vector3(0.0, 0.0, 0.085)).normalized()
	await place_player(w, site)
	var top := w.planet.ground_point(site)
	b.deploy(top)
	assert_true(b.deployed, "deployed")
	var units0 := w.pickups.total_units()
	var progressed := await wait_until(func() -> bool: return b.depth >= 4.0, 900)
	assert_true(progressed, "the rig works its way down")
	var up := w.planet.up_at(top)
	assert_false(w.planet.is_solid(top - up * 2.5), "the shaft is real: open voxels 2.5 m down")
	assert_gt(float(w.pickups.total_units()), float(units0), "spoil comes up as loose chunks")
	var saved: Dictionary = GameState.flags.get("borer/pipseed", {})
	assert_near(float(saved.get("depth", -1.0)), b.depth, 0.01, "progress is saved")
	# walk away: the shaft area unloads and the rig pauses
	var away := (site + Vector3(0.0, 0.0, 0.5)).normalized()
	await stream_to(w, away * (geo.surface_radius(away) + 2.0))
	var paused := await wait_until(func() -> bool: return b.state == "paused", 300)
	assert_true(paused, "out of range: paused")
	var held := b.depth
	await physics(120)
	assert_near(b.depth, held, 0.001, "no digging while paused")
	# come back: it resumes
	await place_player(w, site + Vector3(0.02, 0, 0))
	var resumed := await wait_until(func() -> bool: return b.depth > held + 0.9, 600)
	assert_true(resumed, "back in range: it resumes")
	# a hard layer stalls it
	b.depth = 30.0
	b.state = "running"
	var stalled := await wait_until(func() -> bool: return b.state == "stalled", 300)
	assert_true(stalled, "stalls on rock too hard for its level")
	assert_false(b.stall_reason.is_empty(), "says which rock")
	b.pack_up()
	assert_false(GameState.flags.has("borer/pipseed"), "packed up")
	GameState.gear_levels["borer"] = 0


func test_bot_work_zone_unloads_at_the_nearest_relay() -> void:
	GameState.discover("dormant_bot")
	GameState.gear_levels["robot"] = 1
	GameState.gear_levels["robot_speed"] = 2
	GameState.gear_changed.emit("robot")
	var rm: RobotManager = w.robots
	var rel: Dictionary = w.nav.relays[0]
	GameState.set_flag("relay/pipseed/%s" % rel["id"])
	var spot := ((rel["pos"] as Vector3) + (rel["up"] as Vector3).cross(Vector3.RIGHT).normalized() * 12.0).normalized()
	await place_player(w, spot)
	rm.toggle_zone()
	assert_true(rm.zone != Vector3.ZERO, "zone marked at the player")
	assert_lt(rm._unload_point().distance_to(rel["pos"]), 4.0, "unloads at the relay, not the far Depot")
	var ground := w.planet.ground_point(spot)
	var side := (rel["up"] as Vector3).cross(Vector3.FORWARD).normalized()
	for i in 4:
		w.pickups.spawn(GameData.mat_index("copper"), 2, ground + spot * 0.6 + side * (5.0 + float(i) * 0.4), Vector3.ZERO)
	var earned0 := int(GameState.stats.get("robot_earned", 0))
	# step back so the bot is allowed to take the loot
	w.player.teleport(ground + spot * 0.2 - side * 8.0, side)
	var sold := await wait_until(func() -> bool: return int(GameState.stats.get("robot_earned", 0)) > earned0, 3600)
	assert_true(sold, "the bot collected in the zone and sold at the relay")
	rm.zone = Vector3.ZERO
	GameState.gear_levels["robot"] = 0
	GameState.gear_changed.emit("robot")
