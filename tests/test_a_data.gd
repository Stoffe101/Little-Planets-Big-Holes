extends TestSuite
## Static data sanity: every cross-reference in res://data resolves.


func test_databases_loaded() -> void:
	assert_gt(GameData.materials.size(), 10, "materials loaded")
	assert_true(GameData.materials.size() <= GameData.MAX_MATERIALS, "materials fit the shader array")
	assert_eq(GameData.tool_families.size(), 4, "four tool families")
	assert_gt(GameData.gear.size(), 6, "gear loaded")
	assert_true(GameData.planets.has("pipseed"), "pipseed exists")
	assert_true(GameData.planets.has("glimmerock"), "glimmerock exists")
	assert_gt(GameData.objectives.size(), 8, "objectives loaded")
	assert_eq(GameData.planet_order[0], "pipseed", "pipseed is the first planet")


func test_material_fields() -> void:
	for m in GameData.materials:
		for key in ["id", "name", "category", "hardness", "value", "yield", "color"]:
			assert_true(m.has(key), "material %s has %s" % [m.get("id", "?"), key])
		assert_true(int(m["hardness"]) >= 1 and int(m["hardness"]) <= 5, "hardness in 1..5 for %s" % m["id"])
		assert_gt(float(m["value"]), 0.0, "positive value for %s" % m["id"])


func test_planet_references() -> void:
	for pid: String in GameData.planets:
		var p: Dictionary = GameData.planets[pid]
		assert_gt((p["layers"] as Array).size(), 2, "%s has layers" % pid)
		for l: Dictionary in p["layers"]:
			assert_true(GameData.material_index.has(l["material"]), "%s layer material %s" % [pid, l["material"]])
		for o: Dictionary in p["ores"]:
			assert_true(GameData.material_index.has(o["material"]), "%s ore material %s" % [pid, o["material"]])
			assert_lt(float(o["min_depth"]), float(o["max_depth"]), "ore band ordered")
		for a: Dictionary in p.get("artifacts", []):
			assert_true(GameData.discovery_by_id.has(a["id"]), "%s artifact %s has a discovery entry" % [pid, a["id"]])
		for c: Dictionary in p.get("cavities", []):
			if c.has("discovery"):
				assert_true(GameData.discovery_by_id.has(c["discovery"]), "cavity discovery %s exists" % c["discovery"])
		assert_true(GameData.discovery_by_id.has(p["core"]["discovery"]), "%s core discovery exists" % pid)
		assert_true(GameData.material_index.has(p["bonus_gem"]), "bonus gem exists")
		assert_true(GameData.material_index.has(p["surface_crystal"]), "surface crystal exists")


func test_every_material_is_reachable() -> void:
	# The best purchasable power must break the hardest material on each planet.
	var best_power := 0
	for fam in GameData.tool_families:
		for t: Dictionary in fam["tiers"]:
			best_power = maxi(best_power, int((t["stats"] as Dictionary).get("power", 0)))
	for m in GameData.materials:
		assert_true(int(m["hardness"]) <= best_power, "%s can be dug by some tool" % m["id"])


func test_tool_and_gear_tables() -> void:
	for fam in GameData.tool_families:
		var last_cost := -1
		for t: Dictionary in fam["tiers"]:
			assert_true(int(t["cost"]) > last_cost, "%s tier costs increase" % fam["id"])
			last_cost = int(t["cost"])
		for m: Dictionary in fam["mods"]:
			assert_eq((m["costs"] as Array).size(), int(m["max"]), "mod %s has a cost per level" % m["id"])
			assert_eq((m["effect"]["values"] as Array).size(), int(m["max"]), "mod %s has a value per level" % m["id"])
	for g in GameData.gear:
		assert_eq((g["values"] as Array).size(), (g["costs"] as Array).size() + 1, "gear %s values = costs + 1" % g["id"])
		assert_eq((g["level_names"] as Array).size(), (g["values"] as Array).size(), "gear %s level names" % g["id"])


func test_objective_conditions_reference_real_things() -> void:
	for o in GameData.objectives:
		var c: Dictionary = o["cond"]
		if c.has("tier"):
			assert_true(GameData.tool_family_by_id.has(c["tier"][0]), "objective tier family")
		if c.has("gear"):
			assert_true(GameData.gear_by_id.has(c["gear"][0]), "objective gear id")
		if c.has("discovery"):
			assert_true(GameData.discovery_by_id.has(c["discovery"]), "objective discovery id")
		if c.has("collected"):
			assert_true(GameData.material_index.has(c["collected"][0]), "objective material")
		if c.has("visited"):
			assert_true(GameData.planets.has(c["visited"]), "objective planet")


func test_money_formatting() -> void:
	assert_eq(GameData.format_money(0), "0")
	assert_eq(GameData.format_money(999), "999")
	assert_eq(GameData.format_money(1000), "1,000")
	assert_eq(GameData.format_money(1234567), "1,234,567")
