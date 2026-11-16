extends TestSuite
## Deterministic planet description: shape, strata, ores, octahedral mapping.

var geo: Geology


func before_all() -> void:
	geo = Geology.new(GameData.planet("pipseed"))
	geo.bake()


func _dirs(n: int, seed_value := 5) -> Array[Vector3]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var out: Array[Vector3] = []
	for i in n:
		out.append(Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized())
	return out


func test_same_seed_same_planet() -> void:
	var other := Geology.new(GameData.planet("pipseed"))
	other.bake()
	for d in _dirs(60):
		assert_near(other.height_at(d), geo.height_at(d), 0.00001, "height deterministic")
		var p := d * (geo.radius - 8.0)
		assert_eq(other.material_at(p), geo.material_at(p), "material deterministic")
	assert_eq(other.noise_bytes[0].slice(0, 4096), geo.noise_bytes[0].slice(0, 4096), "noise bake deterministic")


func test_different_seed_different_planet() -> void:
	var other := Geology.new(GameData.planet("pipseed"), 1000)
	var diff := 0
	for d in _dirs(40):
		if absf(other.height_at(d) - geo.height_at(d)) > 0.05:
			diff += 1
	assert_gt(diff, 25, "most heights change with the seed")


func test_landing_pad_is_flat() -> void:
	var l := geo.landing_dir
	var side := l.cross(Vector3.RIGHT).normalized()
	for k in 8:
		var d := (l + side.rotated(l, TAU * k / 8.0) * 0.1).normalized()
		assert_near(geo.height_at(d), geo.landing_height, 0.05, "pad height")


func test_strata_get_harder_with_depth() -> void:
	var hardness_sum := [0.0, 0.0, 0.0]
	var depths := [2.0, 16.0, 38.0]
	for d in _dirs(80):
		for i in 3:
			var p := d * (geo.surface_radius(d) - float(depths[i]))
			hardness_sum[i] += float(geo.hardness_of(geo.material_at(p)))
	assert_lt(hardness_sum[0], hardness_sum[1], "16 m is harder than 2 m")
	assert_lt(hardness_sum[1], hardness_sum[2], "38 m is harder than 16 m")


func test_surface_is_soft_enough_for_the_starting_shovel() -> void:
	for d in _dirs(120):
		var p := d * (geo.surface_radius(d) - 0.4)
		assert_true(geo.hardness_of(geo.material_at(p)) <= 1, "top 0.4 m is diggable with power 1")


func test_ore_abundance_matches_config() -> void:
	# Sample inside each ore's depth band (away from its faded edges) and compare with the design value.
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	for o in geo.ores:
		var lo: float = o["min"] + Geology.EDGE_FADE
		var hi: float = o["max"] - Geology.EDGE_FADE
		var hits := 0
		var n := 4000
		for i in n:
			var d := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized()
			var depth := rng.randf_range(lo, hi)
			var p := d * (geo.surface_radius(d) - depth)
			if geo.sample_noise(o["channel"], p * float(o["scale"]) + (o["offset"] as Vector3)) > float(o["thr"]):
				hits += 1
		var frac := float(hits) / float(n)
		var want: float = o["abundance"]
		assert_true(frac > want * 0.45 and frac < want * 2.2, "ore %s abundance %.3f near %.3f" % [GameData.mat_id(o["mat"]), frac, want])


func test_octahedral_mapping_round_trips() -> void:
	for d in _dirs(100):
		var back := Geology.oct_decode(Geology.oct_encode(d))
		assert_gt(back.dot(d), 0.9999, "oct encode/decode")
	for uv: Vector2 in [Vector2(0.5, 0.5), Vector2(0.1, 0.9), Vector2(0.99, 0.01)]:
		var uv2 := Geology.oct_encode(Geology.oct_decode(uv))
		assert_lt(uv2.distance_to(uv), 0.0005, "oct decode/encode")


func test_noise_sampling_wraps() -> void:
	var a := geo.sample_noise(0, Vector3(3.3, 7.7, 11.1))
	var b := geo.sample_noise(0, Vector3(3.3 + Geology.NOISE_N, 7.7 - Geology.NOISE_N, 11.1 + 2 * Geology.NOISE_N))
	assert_near(a, b, 0.0001, "tileable noise")
	assert_true(a >= 0.0 and a <= 1.0, "noise normalised")


func test_scanner_search_only_returns_valuables() -> void:
	var origin := geo.landing_dir * (geo.radius - 6.0)
	var found := geo.find_ore_near(origin, 16.0, 2.0, 40)
	assert_gt(found.size(), 0, "some ore within 16 m of a point 6 m under the pad")
	for f in found:
		var cat := str(GameData.materials[int(f["mat"])]["category"])
		assert_true(cat in ["ore", "crystal", "exotic"], "only ore-like materials")
		assert_lt(float(f["dist"]), 16.01, "within range")


func test_generator_graph_compiles_and_matches_cpu_shape() -> void:
	var gen := geo.build_generator()
	var buf := VoxelBuffer.new()
	buf.create(8, 8, 8)
	for d in _dirs(12, 21):
		# skip directions near caverns / entrances where the SDF is intentionally carved
		var r_surface := geo.surface_radius(d)
		var inside := Vector3i((d * (r_surface - 1.5) * geo.inv_voxel).floor())
		var outside := Vector3i((d * (r_surface + 1.5) * geo.inv_voxel).floor())
		gen.generate_block(buf, inside, 0)
		var sdf_in := buf.get_voxel_f(0, 0, 0, VoxelBuffer.CHANNEL_SDF)
		gen.generate_block(buf, outside, 0)
		var sdf_out := buf.get_voxel_f(0, 0, 0, VoxelBuffer.CHANNEL_SDF)
		assert_gt(sdf_out, 0.0, "air just above the CPU surface")
		var near_cavity := false
		for c in geo.cavities:
			for s: Array in c["spheres"]:
				if (s[0] as Vector3).distance_to(d * (r_surface - 1.5)) < float(s[1]) + 2.0:
					near_cavity = true
		if not near_cavity:
			assert_lt(sdf_in, 0.0, "ground just below the CPU surface")
