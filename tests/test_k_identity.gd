extends TestSuite
## Guards for the project's own visual identity (docs/ART_DIRECTION.md). These check rules,
## not taste: whether the result looks good and original is for a human to judge.


static func _vertices(n: Node) -> int:
	var total := 0
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		var m := (n as MeshInstance3D).mesh
		for sidx in m.get_surface_count():
			total += (m.surface_get_arrays(sidx)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	for c in n.get_children():
		total += _vertices(c)
	return total


func test_palette_rules_keep_us_away_from_white_machines_and_orange_stripes() -> void:
	# the dominant machine colour is a mid-value enamel, not an off-white panel
	assert_lt(Pal.ENAMEL.get_luminance(), 0.55, "machine enamel is not near-white")
	assert_gt(Pal.ENAMEL.s, 0.35, "machine enamel is a real colour")
	# our accent is verdigris, not an amber/orange stripe colour
	var hue := Pal.JADE.h * 360.0
	assert_true(hue > 120.0 and hue < 190.0, "accent is jade/verdigris (hue %.0f)" % hue)
	assert_true(UiTheme.ACCENT.is_equal_approx(Pal.JADE), "UI accent matches the equipment accent")
	# frames are warm bronze, never neutral graphite
	assert_gt(Pal.BRONZE.r, Pal.BRONZE.b, "frames are warm (bronze), not cold graphite")
	for c: Color in [Pal.ENAMEL, Pal.ENAMEL_SHADE, Pal.JADE, Pal.ION]:
		var h := c.h * 360.0
		assert_false(h > 25.0 and h < 45.0 and c.s > 0.7 and c.v > 0.85, "no saturated amber in the core palette (%s)" % c.to_html(false))


func test_viewmodel_tools_have_gloved_hands_and_previews_do_not() -> void:
	for fam in GameData.tool_families:
		var fid := str(fam["id"])
		for t in (fam["tiers"] as Array).size():
			var vm := ToolModels.build(fid, t + 1, {}, true)
			var pv := ToolModels.build(fid, t + 1, {}, false)
			var with_hands := _vertices(vm["root"])
			var without := _vertices(pv["root"])
			assert_gt(float(with_hands - without), 300.0, "%s tier %d: the viewmodel adds glove geometry (%d vs %d)" % [fid, t + 1, with_hands, without])
			(vm["root"] as Node).free()
			(pv["root"] as Node).free()


func test_outpost_is_built_from_round_forms() -> void:
	use_sandbox("identity")
	GameState.reset()
	var w := await make_world("pipseed", false)
	var base: RocketBase = w.base
	for n: String in ["Rocket", "SellStation", "Kiosk_tools", "Kiosk_gear", "BotDock", "Pad"]:
		assert_true(base.get_node_or_null(n) != null, "%s exists" % n)
	# the stations collide as drums (cylinders), not boxes
	var cyl := 0
	var boxes := 0
	for n: String in ["SellStation", "Kiosk_tools", "Kiosk_gear"]:
		for c in base.get_node(n).get_children():
			if c is StaticBody3D and int((c as StaticBody3D).collision_layer) == 4:
				var sh := ((c as Node).get_child(0) as CollisionShape3D).shape
				if sh is CylinderShape3D:
					cyl += 1
				elif sh is BoxShape3D:
					boxes += 1
	assert_gt(float(cyl), float(boxes), "station bodies are cylinders (%d) rather than boxes (%d)" % [cyl, boxes])
	# the lander is squat: wider than it is tall-ish (no tall rocket)
	var rocket := base.get_node("Rocket") as Node3D
	var aabb := ((rocket.get_child(0) as MeshInstance3D).mesh as ArrayMesh).get_aabb()
	assert_lt(aabb.size.y / maxf(aabb.size.x, aabb.size.z), 1.3, "the lander is a squat pod (h/w %.2f)" % (aabb.size.y / maxf(aabb.size.x, aabb.size.z)))
	await free_world(w)
