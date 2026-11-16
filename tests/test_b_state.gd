extends TestSuite
## Progression rules: inventory, selling, tools, mods, gear, requirements, objectives, travel.


func test_inventory_capacity() -> void:
	GameState.reset()
	var cap := GameState.capacity()
	assert_eq(cap, int(GameData.gear_by_id["backpack"]["values"][0]), "starting capacity comes from the gear table")
	assert_gt(cap, 10, "starting capacity is usable")
	assert_eq(GameState.add_to_inventory("topsoil", 10), 10, "accepts when there is room")
	assert_eq(GameState.add_to_inventory("copper", cap), cap - 10, "accepts only what fits")
	assert_true(GameState.is_full(), "full")
	assert_eq(GameState.add_to_inventory("copper", 1), 0, "rejects when full")
	assert_eq(GameState.inventory_count(), cap, "count equals capacity")


func test_selling_pays_exact_value() -> void:
	GameState.reset()
	GameState.add_to_inventory("topsoil", 7)
	GameState.add_to_inventory("copper", 5)
	# values may be fractional per unit; each material line is rounded to whole credits
	var expected := int(round(7.0 * float(GameData.material("topsoil")["value"]))) + int(round(5.0 * float(GameData.material("copper")["value"])))
	assert_eq(GameState.inventory_value(), expected, "inventory value")
	var before := GameState.money
	var res := GameState.sell_all()
	assert_eq(int(res["total"]), expected, "sale total")
	assert_eq(GameState.money - before, expected, "money increased by the sale")
	assert_eq(GameState.inventory_count(), 0, "inventory emptied")
	assert_eq(int(GameState.stats["sales"]), 1, "sale counted")
	assert_eq(int(GameState.sell_all()["total"]), 0, "selling nothing pays nothing")


func test_refinery_and_blessing_multiply_sales() -> void:
	GameState.reset()
	GameState.money = 100000
	GameState.buy_gear("refinery")
	GameState.add_to_inventory("gold", 10)
	var base := 10.0 * float(GameData.material("gold")["value"])
	assert_eq(int(GameState.sell_all()["total"]), int(round(base * 1.12)), "refinery level 1")
	GameState.discover("pip_heart")
	GameState.add_to_inventory("gold", 10)
	assert_eq(int(GameState.sell_all()["total"]), int(round(base * 1.12 * 1.2)), "heart blessing stacks")


func test_buying_tool_tiers() -> void:
	GameState.reset()
	assert_eq(GameState.tier_of("shovel"), 1, "start with the rusty scoop")
	assert_false(GameState.buy_next_tier("shovel"), "cannot buy without money")
	var cost := int(GameState.next_tier_def("shovel")["cost"])
	GameState.money = cost
	var r0 := float(GameState.tool_stats("shovel")["radius"])
	assert_true(GameState.buy_next_tier("shovel"), "buys the spade")
	assert_eq(GameState.money, 0, "money spent exactly")
	assert_eq(GameState.tier_of("shovel"), 2, "tier advanced")
	assert_gt(float(GameState.tool_stats("shovel")["radius"]), r0, "radius improved")
	assert_eq(int(GameState.tool_stats("shovel")["power"]), 2, "power improved")


func test_mods_apply_to_stats() -> void:
	GameState.reset()
	GameState.money = 100000
	var base := GameState.tool_stats("shovel")
	assert_true(GameState.buy_mod("shovel", "quick_hands"), "buy quick hands")
	assert_true(GameState.buy_mod("shovel", "wide_scoop"), "buy wide scoop")
	var s := GameState.tool_stats("shovel")
	assert_near(float(s["cooldown"]), float(base["cooldown"]) * 0.88, 0.0001, "cooldown multiplied")
	assert_near(float(s["radius"]), float(base["radius"]) + 0.15, 0.0001, "radius added")
	assert_false(GameState.buy_mod("shovel", "trench_blade"), "trench blade locked before the spade")
	GameState.buy_next_tier("shovel")
	assert_true(GameState.buy_mod("shovel", "trench_blade"), "trench blade after the spade")
	assert_eq(int(GameState.tool_stats("shovel")["trench"]), 1, "trench flag set")
	# mods persist across tiers
	assert_near(float(GameState.tool_stats("shovel")["radius"]), float(GameData.family("shovel")["tiers"][1]["stats"]["radius"]) + 0.15, 0.0001, "mod carries over")
	for i in 5:
		GameState.buy_mod("shovel", "quick_hands")
	assert_eq(GameState.mod_level("shovel", "quick_hands"), 3, "mod capped at max")
	assert_eq(GameState.mod_cost("shovel", "quick_hands"), -1, "no cost when maxed")
	assert_false(GameState.buy_mod("drill", "turbo"), "cannot mod a tool you do not own")


func test_gear_levels() -> void:
	GameState.reset()
	var pack: Dictionary = GameData.gear_by_id["backpack"]
	GameState.money = int(pack["costs"][0])
	assert_true(GameState.buy_gear("backpack"), "buy backpack")
	assert_eq(GameState.capacity(), int(pack["values"][1]), "capacity grew to the next level")
	assert_gt(int(pack["values"][1]), int(pack["values"][0]), "and that is an improvement")
	assert_false(GameState.buy_gear("backpack"), "cannot afford the next one")
	GameState.money = 10000000
	for i in 20:
		GameState.buy_gear("backpack")
	assert_eq(GameState.gear_level("backpack"), GameState.gear_max_level("backpack"), "gear capped")
	assert_eq(GameState.gear_cost("backpack"), -1, "no cost at max")
	assert_false(GameState.buy_gear("robot"), "robots locked until the buried bot is found")
	GameState.discover("dormant_bot")
	assert_true(GameState.buy_gear("robot"), "robots unlocked by discovery")
	assert_eq(int(GameState.gear_value("robot")), 1, "one robot")


func test_requirement_text_explains_locks() -> void:
	GameState.reset()
	var req: Dictionary = GameData.family("cannon")["tiers"][0]["requires"]
	assert_false(GameState.requirement_met(req), "cannon locked at start")
	assert_true(GameState.requirement_text(req).contains("Thumper"), "lock text names the needed tool")
	GameState.tiers["shovel"] = 3
	assert_true(GameState.requirement_met(req), "cannon unlocked with the thumper")
	assert_eq(GameState.requirement_text(req), "", "no text when met")


func test_objectives_advance_and_reward() -> void:
	GameState.reset()
	assert_eq(GameState.objective_index, 0, "first objective")
	var first := GameState.current_objective()
	var reward := int(first["reward"])
	GameState.add_stat("digs", 4)
	assert_eq(GameState.objective_index, 0, "not complete yet")
	assert_eq(str(GameState.objective_progress()["label"]), "4 / 5", "progress label")
	GameState.add_stat("digs", 1)
	assert_eq(GameState.objective_index, 1, "objective completed")
	assert_eq(GameState.money, reward, "reward paid")
	var need := int(GameState.current_objective()["cond"]["gte"])
	GameState.add_to_inventory("topsoil", need - 1)
	assert_eq(GameState.objective_index, 1, "collect objective needs the full amount")
	GameState.add_to_inventory("topsoil", 1)
	assert_eq(GameState.objective_index, 2, "collect objective completed")


func test_discoveries_and_planet_unlock() -> void:
	GameState.reset()
	assert_false(GameState.planet_unlocked_now("glimmerock"), "glimmerock locked")
	assert_false(GameState.can_travel_to("glimmerock"), "cannot travel")
	assert_true(GameState.discover("star_chart_a"), "new discovery")
	assert_false(GameState.discover("star_chart_a"), "not new twice")
	assert_eq(GameState.money, int(GameData.discovery("star_chart_a")["reward"]), "discovery reward paid once")
	GameState.discover("star_chart_b")
	assert_true(GameState.planet_unlocked_now("glimmerock"), "unlocked by both charts")
	var cost := int(GameData.planet("glimmerock")["travel_cost"])
	GameState.money = cost - 1
	assert_false(GameState.can_travel_to("glimmerock"), "needs the fare")
	GameState.money = cost + 10
	assert_true(GameState.travel_to("glimmerock"), "travel")
	assert_eq(GameState.money, 10, "fare paid")
	assert_eq(GameState.current_planet, "glimmerock", "planet switched")
	assert_true(GameState.travel_to("pipseed"), "flying home is free")
	GameState.money = 0
	assert_true(GameState.travel_to("glimmerock"), "return trips are free")


func test_serialisation_round_trip() -> void:
	GameState.reset()
	GameState.money = 4321
	GameState.add_to_inventory("iron", 9)
	GameState.tiers["shovel"] = 3
	GameState.tiers["drill"] = 1
	GameState.mods["shovel/wide_scoop"] = 2
	GameState.gear_levels["magnet"] = 2
	GameState.discover("time_capsule")
	GameState.set_flag("pipseed/formation_3")
	GameState.stats["max_depth"] = 17.5
	GameState.playtime = 99.0
	var money_before := GameState.money
	var d := GameState.to_dict()
	GameState.reset()
	assert_true(GameState.from_dict(d), "loads")
	assert_eq(GameState.money, money_before, "money")
	assert_eq(int(GameState.inventory["iron"]), 9, "inventory")
	assert_eq(GameState.tier_of("shovel"), 3, "tier")
	assert_eq(GameState.tier_of("drill"), 1, "second family")
	assert_eq(GameState.mod_level("shovel", "wide_scoop"), 2, "mods")
	assert_eq(GameState.gear_level("magnet"), 2, "gear")
	assert_true(GameState.has_discovery("time_capsule"), "discoveries")
	assert_true(GameState.has_flag("pipseed/formation_3"), "flags")
	assert_near(float(GameState.stats["max_depth"]), 17.5, 0.001, "stats")


func test_from_dict_rejects_garbage_and_drops_unknown_ids() -> void:
	GameState.reset()
	assert_false(GameState.from_dict({}), "empty dictionary rejected")
	assert_false(GameState.from_dict({"hello": 1}), "missing fields rejected")
	var d := {"money": -50, "tiers": {"shovel": 99, "banana": 3}, "inventory": {"unobtainium": 5, "copper": 2},
		"gear": {"backpack": 99, "nope": 1}, "discoveries": ["nope", "time_capsule"], "current_planet": "atlantis", "equipped": "cannon"}
	assert_true(GameState.from_dict(d), "damaged but usable data loads")
	assert_eq(GameState.money, 0, "negative money clamped")
	assert_eq(GameState.tier_of("shovel"), 4, "tier clamped to max")
	assert_false(GameState.tiers.has("banana"), "unknown family dropped")
	assert_false(GameState.inventory.has("unobtainium"), "unknown material dropped")
	assert_eq(GameState.gear_level("backpack"), GameState.gear_max_level("backpack"), "gear clamped")
	assert_eq(GameState.current_planet, "pipseed", "unknown planet falls back")
	assert_eq(GameState.equipped, "shovel", "unowned equipped tool falls back")
	assert_eq(GameState.discoveries.size(), 1, "unknown discovery dropped")
