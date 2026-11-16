extends TestSuite
## Regression coverage added with the visual / game-feel overhaul: procedural models, prop
## determinism, arrival, the shop screen, balance-table sanity and old-save tolerance.
## These check logic and structure only - what things LOOK like is verified from renders
## (see docs/TESTING.md).


func test_every_tool_tier_and_mod_builds_a_model() -> void:
	for fam in GameData.tool_families:
		var fid: String = fam["id"]
		var tiers: Array = fam["tiers"]
		var bare_counts: Array[int] = []
		for t in tiers.size():
			var bare := ToolModels.build(fid, t + 1, {}, true)
			var mods := {}
			for m: Dictionary in fam.get("mods", []):
				mods[m["id"]] = int(m["max"])
			var full := ToolModels.build(fid, t + 1, mods, true)
			var nb := _vertex_count(bare["root"])
			var nf := _vertex_count(full["root"])
			assert_gt(nb, 200, "%s tier %d has real geometry" % [fid, t + 1])
			assert_gt(nf, nb, "%s tier %d: attachments add visible parts" % [fid, t + 1])
			assert_true(bare["muzzle"] != null, "%s tier %d has a muzzle point" % [fid, t + 1])
			assert_true((bare["material"] as ShaderMaterial).get_shader_parameter("viewmodel"), "viewmodel material")
			bare_counts.append(nb)
			(bare["root"] as Node).free()
			(full["root"] as Node).free()
		# every single mod level must change the model, not only the fully kitted version
		for m: Dictionary in fam.get("mods", []):
			var prev := -1
			for lvl in range(0, int(m["max"]) + 1):
				var one := ToolModels.build(fid, tiers.size(), {m["id"]: lvl}, false)
				var n := _vertex_count(one["root"])
				(one["root"] as Node).free()
				if prev >= 0 and str(m["id"]) not in ["wide_scoop", "wide_bore", "wide_mouth", "long_shaft"]:
					assert_gt(n, prev, "%s/%s level %d adds geometry" % [fid, m["id"], lvl])
				prev = n
	# animated parts the controller relies on
	var thumper := ToolModels.build("shovel", 3, {}, true)
	assert_true(thumper["piston"] != null, "power shovel has a moving head")
	(thumper["root"] as Node).free()
	var drill := ToolModels.build("drill", 1, {}, true)
	assert_true(drill["spin"] != null, "drill has a spinning bit")
	(drill["root"] as Node).free()
	var cannon := ToolModels.build("cannon", 1, {}, true)
	assert_true(cannon["recoil"] != null, "cannon has a recoiling barrel")
	(cannon["root"] as Node).free()


func _vertex_count(root: Node) -> int:
	var n := 0
	if root is MeshInstance3D and (root as MeshInstance3D).mesh != null:
		var mesh := (root as MeshInstance3D).mesh
		for s in mesh.get_surface_count():
			n += (mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	for c in root.get_children():
		n += _vertex_count(c)
	return n


func test_mesh_kit_hard_surface_primitives() -> void:
	var kit := MeshKit.new().paint()
	kit.hbox(Transform3D.IDENTITY, Vector3(1, 0.5, 0.25), Color.WHITE, 0.05)
	var mesh := kit.commit()
	var aabb := mesh.get_aabb()
	assert_near(aabb.size.x, 1.0, 0.001, "bevelled box keeps its outer width")
	assert_near(aabb.size.y, 0.5, 0.001, "bevelled box keeps its outer height")
	var arrays := mesh.surface_get_arrays(0)
	var uv2: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
	assert_eq(uv2.size(), (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(), "roughness/metal stored per vertex")
	assert_near(uv2[0].x, 0.48, 0.001, "paint() finish written to UV2")
	# every triangle of a closed convex shape must face outwards
	var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var n: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var inward := 0
	for i in range(0, idx.size(), 3):
		var c := (v[idx[i]] + v[idx[i + 1]] + v[idx[i + 2]]) / 3.0
		if (n[idx[i]] + n[idx[i + 1]] + n[idx[i + 2]]).dot(c) < 0.0:
			inward += 1
	assert_eq(inward, 0, "no inward-facing normals on a bevelled box")
	var rock_a := MeshKit.new()
	rock_a.rock(Transform3D.IDENTITY, 1.0, Color.GRAY, 42)
	var rock_b := MeshKit.new()
	rock_b.rock(Transform3D.IDENTITY, 1.0, Color.GRAY, 42)
	var rock_c := MeshKit.new()
	rock_c.rock(Transform3D.IDENTITY, 1.0, Color.GRAY, 43)
	assert_eq(rock_a.commit().get_aabb(), rock_b.commit().get_aabb(), "rocks are deterministic from their seed")
	assert_true(rock_a.commit().get_aabb() != rock_c.commit().get_aabb(), "different seeds give different rocks")
	var lathe := MeshKit.new()
	lathe.lathe(PackedVector2Array([Vector2(1.0, 0.0), Vector2(1.0, 2.0)]), Transform3D.IDENTITY, Color.WHITE, 6, false, true)
	assert_near(lathe.commit().get_aabb().size.y, 2.0, 0.001, "lathe height")


func test_palette_and_look_data_are_complete() -> void:
	for pid in GameData.planet_order:
		var cfg := GameData.planet(pid)
		var pal: Dictionary = cfg.get("palette", {})
		for key in ["grass", "sky_top", "sky_mid", "sky_horizon", "sky_glow", "sky_ground", "sun", "ambient", "fog", "rim", "from_space"]:
			assert_true(pal.has(key), "%s palette has %s" % [pid, key])
		assert_eq((pal["grass"] as Array).size(), 3, "%s has three ground-cover tones" % pid)
		assert_true(cfg.has("look"), "%s has a look block" % pid)
		var props: Dictionary = cfg.get("props", {})
		for key in ["foliage", "rock", "landmark"]:
			assert_true(props.has(key), "%s props define %s" % [pid, key])
		assert_true(str((cfg["core"] as Dictionary).get("style", "")) in ["seed", "crystal"], "%s heart style" % pid)
	# restraint: ordinary ground must not glow, and only genuinely exotic things glow strongly
	for m in GameData.materials:
		if str(m["category"]) in ["soil", "rock"]:
			assert_true(float(m.get("emission", 0.0)) <= 0.12, "%s (bulk) barely emits" % m["id"])
		if str(m["category"]) == "ore":
			assert_true(float(m.get("emission", 0.0)) <= 0.05, "%s (ore) relies on finish, not glow" % m["id"])


func test_balance_tables_are_sane() -> void:
	# costs rise with every level and every tier
	for g in GameData.gear:
		var costs: Array = g["costs"]
		for i in range(1, costs.size()):
			assert_gt(float(costs[i]), float(costs[i - 1]), "%s level %d costs more than level %d" % [g["id"], i + 1, i])
	for fam in GameData.tool_families:
		var tiers: Array = fam["tiers"]
		for i in range(1, tiers.size()):
			assert_gt(float(tiers[i]["cost"]), float(tiers[i - 1]["cost"]), "%s tier %d costs more" % [fam["id"], i + 1])
		var behavior := str(fam["behavior"])
		if behavior in ["swing", "drill"]:
			# each tier must move clearly more ground per second than the one before, or be able
			# to break something the previous one could not: no purchase that changes nothing
			for i in range(1, tiers.size()):
				var a := ShopUi.dig_rate(tiers[i - 1]["stats"], behavior)
				var b := ShopUi.dig_rate(tiers[i]["stats"], behavior)
				var stronger := int(tiers[i]["stats"]["power"]) > int(tiers[i - 1]["stats"]["power"])
				assert_true(b > a * 1.5 or stronger, "%s tier %d is a real step up (%.1f -> %.1f m3/s)" % [fam["id"], i + 1, a, b])
	# the first upgrade is within reach of the first minutes: tutorial rewards alone cover most of it
	var early := 0
	for i in 3:
		early += int(GameData.objectives[i]["reward"])
	var spade := int(GameData.family("shovel")["tiers"][1]["cost"])
	assert_gt(float(early), float(spade) * 0.5, "first three objectives pay for over half of the first upgrade")
	# valuable things are worth more per unit than the rock they sit in
	var soil := float(GameData.material("topsoil")["value"])
	for m in GameData.materials:
		if str(m["category"]) in ["ore", "crystal", "exotic"]:
			assert_gt(float(m["value"]), soil * 5.0, "%s is clearly worth more than dirt" % m["id"])
	# backpack capacity grows at every level
	var caps: Array = GameData.gear_by_id["backpack"]["values"]
	for i in range(1, caps.size()):
		assert_gt(float(caps[i]), float(caps[i - 1]) * 1.5, "backpack level %d is a real step" % i)


func test_old_saves_with_removed_flags_still_load() -> void:
	# A v2 save from the first build: old formation flag keys, old prices, an inventory larger
	# than today's starting backpack. Nothing may be lost or rejected.
	GameState.reset()
	var d := {"version": 2, "money": 1234, "tiers": {"shovel": 2, "vacuum": 1}, "mods": {"shovel/quick_hands": 2},
		"inventory": {"topsoil": 35, "copper": 4}, "gear": {"backpack": 1, "scanner": 1},
		"discoveries": ["dormant_bot", "crystal_grotto"], "visited": ["pipseed"],
		"flags": {"pipseed/formation_12": true, "pipseed/cav_crystal_grotto_3": true},
		"stats": {"digs": 420, "total_earned": 5000, "max_depth": 9.5}, "objective_index": 6, "equipped": "shovel"}
	assert_true(GameState.from_dict(SaveSystem.migrate(d, 2)), "old save loads")
	# loading re-checks objectives, so already-satisfied goals may pay out; money never drops
	assert_true(GameState.money >= 1234, "money kept")
	assert_eq(GameState.inventory_count(), 39, "inventory kept even if it exceeds a rebalanced capacity")
	assert_true(GameState.has_flag("pipseed/formation_12"), "obsolete flags are carried, not dropped")
	assert_true(GameState.has_flag("pipseed/cav_crystal_grotto_3"), "cavern crystal flags still apply")
	assert_eq(GameState.tier_of("vacuum"), 1, "owned tools kept")
	assert_eq(GameState.mod_level("shovel", "quick_hands"), 2, "mods kept")
	assert_true(int(GameState.sell_all()["total"]) > 0, "old inventory still sells")


func test_world_arrival_props_and_base() -> void:
	GameState.reset()
	var w := await make_world("pipseed")
	var geo := w.planet.geology
	# arrival: on the ground, outside the shielded pad, looking back at the outpost
	var p := w.player.global_position
	var from_base := (p - geo.landing_dir * p.dot(geo.landing_dir)).length()
	assert_gt(from_base, World.PROTECT_RADIUS, "player arrives outside the shielded pad")
	assert_true(from_base < 20.0, "but within a few steps of the outpost")
	assert_true(w.planet.sdf_at(p + w.player.up * 1.0) > 0.0, "arrival point is in open air")
	assert_true(w.planet.sdf_at(p - w.player.up * 0.8) < 0.0, "with ground underfoot")
	var to_base := (geo.spawn_position() - w.player.eye_position()).normalized()
	assert_gt(to_base.dot(w.player.aim_direction()), 0.7, "first view faces the outpost")
	# props: deterministic and independent of digging
	var props: PropField = w.props
	# props stream in cells around the player; make sure every cell around here is built
	props.update_now(w.player.global_position)
	assert_gt(float(props.prop_count), 1000.0, "ground cover placed")
	assert_gt(float(props.landmark_count), 4.0, "landmarks placed (mountain stones + cave cairns)")
	var before: Dictionary = {}
	for c in props.get_children():
		if c is Formation:
			before[(c as Formation).flag_key] = (c as Formation).global_position
	assert_gt(float(before.size()), 10.0, "surface crystals placed")
	for key: String in before:
		assert_true(key.contains("/crystal_"), "new crystal flag namespace")
	# dig a big hole somewhere else (in the loaded area, 35 m from the pad), then rebuild the
	# prop field from scratch around the same spot
	var side := geo.landing_dir.cross(Vector3.RIGHT).normalized()
	var dig_dir := (geo.landing_dir + side * (35.0 / geo.radius)).normalized()
	for i in 6:
		w.dig.dig_sphere(w.planet.ground_point(dig_dir) - dig_dir * float(i), 4.0, 9)
	await physics(4)
	var again := PropField.new()
	w.add_child(again)
	again.setup(w)
	again.enabled = false
	var moved := 0
	var missing := 0
	for c in again.get_children():
		if c is Formation:
			var k := (c as Formation).flag_key
			if not before.has(k):
				missing += 1
			elif ((before[k] as Vector3) - (c as Formation).global_position).length() > 0.01:
				moved += 1
	assert_eq(moved, 0, "digging elsewhere never moves a crystal (per-item seeding)")
	assert_eq(missing, 0, "and never creates one under a new index")
	again.queue_free()
	# landmarks are uprooted like any other prop when the ground under them is dug away
	var lms := props.live_items(true)
	assert_gt(float(lms.size()), 4.0, "landmarks are registered for removal")
	var lm: Dictionary = lms[0]
	var lm_node: Node = lm["body"]
	var lm_pos: Vector3 = lm["pos"]
	var lm_count := props.landmark_count
	props.on_dig(lm_pos, 2.0)
	await frames(2)
	assert_false(is_instance_valid(lm_node), "a landmark dug out from under is removed")
	assert_eq(props.landmark_count, lm_count - 1, "and no longer counted")
	# nothing grows through the outpost's pads
	var too_close := 0
	for e: Dictionary in props.live_items(false):
		var q: Vector3 = e["pos"]
		if (q - geo.landing_dir * q.dot(geo.landing_dir)).length() < 9.5 and q.dot(geo.landing_dir) > 0.0:
			too_close += 1
	assert_eq(too_close, 0, "no ground cover or pebbles inside the outpost")
	# everything the base builds stands on shielded ground
	for child in w.base.get_children():
		if child is Node3D and (child as Node3D).global_position.length() > 1.0:
			assert_true(w.is_protected((child as Node3D).global_position - w.player.up * 0.5) or child.name == "Progress",
				"%s stands on shielded ground" % child.name)
	# the outpost grows with progress
	var base: RocketBase = w.base
	var progress := base.get_node("Progress")
	var n0 := progress.get_child_count()
	GameState.money = 1000000
	GameState.buy_gear("backpack")
	GameState.buy_gear("scanner")
	await physics(3)
	assert_gt(float(progress.get_child_count()), float(n0), "buying gear adds installations to the base")
	for inst in progress.get_children():
		if inst is Node3D and not inst.is_queued_for_deletion():
			assert_true(w.is_protected((inst as Node3D).global_position - geo.landing_dir * 0.5), "progress installation %s is on shielded ground" % inst.name)
	assert_true(base.sell_pad_center.length() > 1.0 and base.dock_position.length() > 1.0, "depot pad and bot dock exist")
	await free_world(w)


func test_new_tool_is_shown_off_for_purchases_only() -> void:
	GameState.reset()
	var w := await make_world("pipseed")
	var tools: ToolController = w.tools
	await frames(4)
	assert_eq(tools._inspect, 0.0, "nothing to show at the start")
	# a discovery also emits tools_changed (it can unlock shop items) but is not a purchase
	GameState.discover("time_capsule")
	await frames(4)
	assert_eq(tools._inspect, 0.0, "a discovery does not trigger the new-tool presentation")
	assert_eq(tools._pending_inspect, "", "and queues nothing")
	# buying inside a menu: the presentation waits until the player can see it
	GameState.money = 100000
	w.player.controls_locked = true
	assert_true(GameState.buy_next_tier("shovel"), "buy the spade in the shop")
	await frames(4)
	assert_eq(tools._inspect, 0.0, "not shown while the menu is open")
	assert_eq(tools._pending_inspect, "shovel", "queued for the held tool")
	w.player.controls_locked = false
	await frames(3)
	assert_gt(tools._inspect, 0.0, "shown as soon as the menu closes")
	# an attachment for a tool that is not in hand is not shown off on the wrong model
	tools._inspect = 0.0
	assert_true(GameState.buy_next_tier("vacuum"), "buy a second family (it becomes equipped)")
	for i in 120:
		await get_tree().process_frame
		if tools.family_id == "vacuum" and tools._equip_t >= 1.0 and tools._pending_inspect == "":
			break
	assert_eq(tools.family_id, "vacuum", "new family equipped")
	tools._inspect = 0.0
	assert_true(GameState.buy_mod("shovel", "wide_scoop"), "buy a shovel attachment while holding the vacuum")
	await frames(4)
	assert_eq(tools._inspect, 0.0, "no presentation for a tool that is not in hand")
	await free_world(w)


func test_lucky_charm_is_a_perk_not_an_income() -> void:
	GameState.reset()
	assert_eq(World.luck_roll_chance(10.0), 0.0, "no charm, no luck")
	GameState.money = 1000000
	GameState.buy_gear("lucky")
	var small := World.luck_roll_chance(1.0)
	var big := World.luck_roll_chance(60.0)
	assert_gt(small, 0.0, "a small bite can be lucky")
	assert_near(big, GameState.luck_chance(), 0.0001, "a huge bite is no luckier than the listed chance")
	for pid in GameData.planet_order:
		var cfg := GameData.planet(pid)
		var gem := GameData.material(str(cfg.get("lucky_gem", cfg.get("bonus_gem", ""))))
		assert_false(gem.is_empty(), "%s has a lucky gem" % pid)
		# two gems per proc at the top charm level, four digs a second: still well under the
		# price of a mid-game tool per minute
		var per_minute := 1.5 * float(gem["value"]) * 0.14 * 4.0 * 60.0
		assert_lt(per_minute, 4000.0, "%s: lucky income stays modest (%.0f cr/min worst case)" % [pid, per_minute])


func test_shop_screen_builds_every_view() -> void:
	GameState.reset()
	var shop := ShopUi.new()
	add_child(shop)
	shop.open("tools")
	await frames(2)
	assert_true(shop.visible, "shop opens")
	for fam in GameData.tool_families:
		shop._select_family(str(fam["id"]))
		await frames(1)
		assert_eq(shop._family, str(fam["id"]), "family selected")
		assert_gt(float(shop._detail.get_child_count()), 0.0, "detail column filled for %s" % fam["id"])
		assert_eq(shop._tier_strip.get_child_count(), (fam["tiers"] as Array).size(), "one preview chip per tier")
	# buying through the screen's own state path updates the preview to the owned tier
	GameState.money = 100000
	shop._select_family("shovel")
	assert_eq(shop._preview_tier, 2, "preview defaults to the next upgrade")
	assert_true(GameState.buy_next_tier("shovel"), "buy")
	await frames(2)
	assert_gt(ShopUi.dig_rate(GameState.tool_stats("shovel"), "swing"), ShopUi.dig_rate(GameData.family("shovel")["tiers"][0]["stats"], "swing") * 2.0,
		"the first upgrade more than doubles the ground moved per second")
	shop.open("gear")
	await frames(2)
	assert_eq(shop._gear_grid.get_child_count(), GameData.gear.size(), "one card per gear line")
	shop.close_shop()
	assert_false(shop.visible, "closes")
	shop.queue_free()
