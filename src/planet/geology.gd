class_name Geology
extends RefCounted
## Deterministic description of a planet's shape and what it is made of.
##
## One Geology instance is the single source of truth for:
##   * the voxel generator graph (terrain SDF: hills, landforms, caves, cavities, core chamber)
##   * CPU material queries used by gameplay (`material_at`)
##   * the data handed to the terrain shader so that what you SEE is what you DIG
##
## Everything derives from the planet config + seed, so the same seed always produces the
## same planet (and the same in multiplayer on every peer).
##
## Shape = hills + detail + regional roughness + landforms (domes, basins, plateaus, craters,
## ridges) + a flattened landing site. `height_exact()` evaluates that function directly (the
## generator graph builds the same function in C++); `height_at()` reads it from a baked
## octahedral height map, which is exactly what the terrain shader samples, so gameplay and
## rendering agree on depth and therefore on materials.
##
## Regions are soft areas on the sphere (centre direction + angular radius) that change how a
## place looks and what it holds: extra roughness, lifted strata (rock near the surface), less
## ground cover, their own ground-cover colours and prop densities, and richer ore.

const NOISE_N := 96                 ## edge length of the tileable 3D material-noise textures
const NOISE_CHANNELS := 3
const MAX_LAYERS := 8
const MAX_ORES := 12
const MAX_REGIONS := 8
const EDGE_FADE := 1.5              ## metres over which an ore band fades out at its depth limits
const BAKE_VERSION := 3             ## bump when the height function changes (invalidates caches)

var cfg: Dictionary
var id: String
var seed_value: int
var generation := 1
var radius: float                   ## nominal planet radius in metres
var voxel_size: float
var inv_voxel: float
var height_map_n := 256

# terrain shape
var hill_noise: ZN_FastNoiseLite
var detail_noise: ZN_FastNoiseLite
var rough_noise: ZN_FastNoiseLite
var hill_amp := 3.0
var hill_freq := 1.7
var detail_amp := 0.6
var detail_freq := 5.5
var rough_freq := 24.0
var features: Array[Dictionary] = []     ## {type, dir, ...} see _add_feature
var landing_dir := Vector3.UP
var landing_cos_in := 0.98
var landing_cos_out := 0.94
var landing_height := 0.5
var regions: Array[Dictionary] = []      ## {id, name, dir, cos_in, cos_out, rough, lift, cover, cfg}

# geology
var layer_bottom := PackedFloat32Array()
var layer_mat := PackedInt32Array()
var layer_warp := 1.5
var ores: Array[Dictionary] = []          ## {mat, min, max, thr, thr_boost, region, scale, offset, channel}
var cavities: Array[Dictionary] = []      ## {id, center, radius, spheres, dir, entrance, cfg}
var artifacts: Array[Dictionary] = []     ## {id, pos, pocket, model, cfg}
var core_radius := 5.0

# baked data
var noise_bytes: Array[PackedByteArray] = []
var noise_textures: Array[ImageTexture3D] = []
var height_data := PackedFloat32Array()   ## height_map_n^2 heights (metres), octahedral
var tint_data := PackedFloat32Array()     ## height_map_n^2 * 2 tint channels
var height_image: Image
var height_texture: ImageTexture
var bake_ms := 0
var bake_from_cache := false
var _material_hardness := PackedInt32Array()


func _init(config: Dictionary, seed_offset := 0) -> void:
	cfg = config
	id = str(cfg.get("id", "planet"))
	seed_value = int(cfg.get("seed", 1)) + seed_offset
	generation = int(cfg.get("generation", 1))
	radius = float(cfg.get("radius", 48.0))
	voxel_size = float(cfg.get("voxel_size", 0.5))
	inv_voxel = 1.0 / voxel_size
	# ~1.4 m per texel at any radius, between 256 and 1024 texels wide
	height_map_n = clampi(int(pow(2.0, ceil(log(radius * 2.5) / log(2.0)))), 256, 1024)
	if cfg.has("height_map_size"):
		height_map_n = int(cfg["height_map_size"])
	_setup_terrain()
	_setup_regions()
	_setup_layers()
	_setup_cavities()
	for m in GameData.materials:
		_material_hardness.append(int(m["hardness"]))


# ------------------------------------------------------------------ setup

func _setup_terrain() -> void:
	var t: Dictionary = cfg.get("terrain", {})
	hill_amp = float(t.get("hill_amp", 3.0))
	hill_freq = float(t.get("hill_freq", 1.7))
	detail_amp = float(t.get("detail_amp", 0.6))
	detail_freq = float(t.get("detail_freq", 5.5))
	rough_freq = float(t.get("rough_freq", detail_freq * 3.0))
	hill_noise = ZN_FastNoiseLite.new()
	hill_noise.noise_type = ZN_FastNoiseLite.TYPE_OPEN_SIMPLEX_2
	hill_noise.seed = seed_value
	hill_noise.period = 1.0
	hill_noise.fractal_type = ZN_FastNoiseLite.FRACTAL_FBM
	hill_noise.fractal_octaves = 3
	hill_noise.fractal_gain = 0.45
	detail_noise = ZN_FastNoiseLite.new()
	detail_noise.noise_type = ZN_FastNoiseLite.TYPE_OPEN_SIMPLEX_2
	detail_noise.seed = seed_value + 101
	detail_noise.period = 1.0
	detail_noise.fractal_type = ZN_FastNoiseLite.FRACTAL_NONE
	rough_noise = ZN_FastNoiseLite.new()
	rough_noise.noise_type = ZN_FastNoiseLite.TYPE_OPEN_SIMPLEX_2
	rough_noise.seed = seed_value + 211
	rough_noise.period = 1.0
	rough_noise.fractal_type = ZN_FastNoiseLite.FRACTAL_FBM
	rough_noise.fractal_octaves = 2
	rough_noise.fractal_gain = 0.5
	# legacy keys
	for m: Dictionary in t.get("mountains", []):
		_add_feature({"type": "dome", "dir": m["dir"], "height": float(m["height"]), "width": float(m["width"])})
	for b: Dictionary in t.get("basins", []):
		_add_feature({"type": "dome", "dir": b["dir"], "height": -float(b["depth"]), "width": float(b["width"])})
	for f: Dictionary in t.get("features", []):
		_add_feature(f)
	# crater fields: a deterministic scatter of craters inside an area
	for field: Dictionary in t.get("crater_fields", []):
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value * 977 + int(field.get("seed", 1))
		var centre := _vec(field["dir"]).normalized()
		var spread := float(field.get("radius", 0.2))
		var t1 := centre.cross(Vector3(0.3, 0.8, 0.5)).normalized()
		var t2 := centre.cross(t1).normalized()
		for i in int(field.get("count", 6)):
			var a := rng.randf() * TAU
			var d := sqrt(rng.randf()) * spread
			var dir := (centre * cos(d) + (t1 * cos(a) + t2 * sin(a)) * sin(d)).normalized()
			var size := rng.randf_range(float(field.get("min", 0.01)), float(field.get("max", 0.03)))
			var depth_m := size * radius * float(field.get("depth_ratio", 0.22))
			_add_feature({"type": "crater", "dir": [dir.x, dir.y, dir.z], "radius": size, "depth": depth_m, "rim": depth_m * 0.35})
	var l: Dictionary = t.get("landing", {})
	landing_dir = _vec(l.get("dir", [0, 1, 0])).normalized()
	var flat := float(l.get("flat_radius", 0.17))
	landing_cos_in = cos(flat)
	landing_cos_out = cos(flat + float(l.get("blend", 0.15)))
	landing_height = float(l.get("height", 0.5))


## Landforms. Every type is a function of dot(n, dir) (and for ridges a second axis), which the
## generator graph can reproduce exactly with smoothstep / abs / multiply nodes.
func _add_feature(f: Dictionary) -> void:
	var e := {"type": str(f.get("type", "dome")), "dir": _vec(f["dir"]).normalized(), "src": f}
	match e["type"]:
		"dome":
			# a rounded hill or (negative height) a basin
			e["height"] = float(f["height"])
			e["c0"] = cos(float(f["width"]))
			e["c1"] = 1.0
		"plateau":
			# flat-topped table with a steep rim
			var r := float(f.get("radius", 0.1))
			var edge := float(f.get("edge", 0.02))
			e["height"] = float(f["height"])
			e["c0"] = cos(r + edge)
			e["c1"] = cos(r)
		"crater":
			# bowl with a raised rim; t = (1 - dot) / (1 - cos r) is 0 at the centre, 1 at the rim
			var r2 := float(f.get("radius", 0.03))
			e["k"] = 1.0 / maxf(1.0 - cos(r2), 0.000001)
			e["depth"] = float(f.get("depth", r2 * radius * 0.2))
			e["rim"] = float(f.get("rim", float(e["depth"]) * 0.3))
		"ridge":
			# a long crest along the great circle from `dir` to `dir2`
			var a := _vec(f["dir"]).normalized()
			var b := _vec(f["dir2"]).normalized()
			e["axis"] = a.cross(b).normalized()            # plane normal of the great circle
			e["mid"] = (a + b).normalized()
			e["c_len"] = cos(a.angle_to(b) * 0.5 + float(f.get("taper", 0.03)))
			e["c_len_in"] = cos(a.angle_to(b) * 0.5)
			e["w"] = sin(float(f.get("width", 0.02)))
			e["height"] = float(f["height"])
		_:
			push_warning("Geology: unknown feature type %s" % e["type"])
			return
	features.append(e)


func _setup_regions() -> void:
	for r: Dictionary in cfg.get("regions", []):
		if regions.size() >= MAX_REGIONS:
			push_warning("Geology: more than %d regions, extra ignored" % MAX_REGIONS)
			break
		var rad := float(r.get("radius", 0.2))
		var blend := float(r.get("blend", 0.06))
		regions.append({
			"id": str(r["id"]), "name": str(r.get("name", r["id"])),
			"dir": _vec(r["dir"]).normalized(),
			"cos_in": cos(rad), "cos_out": cos(rad + blend),
			"rough": float(r.get("rough", 0.0)),
			"lift": float(r.get("strata_lift", 0.0)),
			"cover": float(r.get("cover", 1.0)),
			"cfg": r,
		})


func region_index(rid: String) -> int:
	for i in regions.size():
		if regions[i]["id"] == rid:
			return i
	return -1


func _setup_layers() -> void:
	var bottom := 0.0
	for l: Dictionary in cfg.get("layers", []):
		bottom += float(l["thickness"])
		layer_bottom.append(bottom)
		layer_mat.append(GameData.mat_index(l["material"]))
	layer_warp = float(cfg.get("layer_warp", 1.5))
	core_radius = float((cfg.get("core", {}) as Dictionary).get("chamber_radius", 5.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 7919 + 13
	var i := 0
	for o: Dictionary in cfg.get("ores", []):
		var blob := float(o.get("blob", 3.0))
		ores.append({
			"mat": GameData.mat_index(o["material"]),
			"min": float(o["min_depth"]), "max": float(o["max_depth"]),
			"abundance": float(o.get("abundance", 0.05)),
			"boost": float(o.get("boost", 1.0)),
			"region": region_index(str(o.get("region", ""))),
			"thr": 0.75,        # replaced by _calibrate_ores() once the noise is baked
			"thr_boost": 0.75,
			"scale": 6.0 / blob,
			"offset": Vector3(rng.randf() * NOISE_N, rng.randf() * NOISE_N, rng.randf() * NOISE_N),
			"channel": i % NOISE_CHANNELS,
		})
		i += 1


func _setup_cavities() -> void:
	for c: Dictionary in cfg.get("cavities", []):
		var dir := _vec(c["dir"]).normalized()
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(str(c["id"])) + seed_value
		var rad := float(c["radius"])
		var center := dir * (surface_radius_exact(dir) - float(c["depth"]))
		var spheres: Array = [[center, rad]]
		for j in int(c.get("lobes", 3)):
			var off := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized() * rad * rng.randf_range(0.55, 0.95)
			off -= dir * off.dot(dir) * 0.55      # flatten lobes so caverns are wider than tall
			spheres.append([center + off, rad * rng.randf_range(0.45, 0.72)])
		var entrance_pos := Vector3.ZERO
		if bool(c.get("entrance", false)):
			# A sloped tunnel from the cavern up to a point on the surface.
			var tangent := dir.cross(Vector3(0.31, 0.77, -0.55)).normalized()
			tangent = tangent.rotated(dir, rng.randf() * TAU)
			if c.has("entrance_bearing"):
				tangent = dir.cross(Vector3(0.31, 0.77, -0.55)).normalized().rotated(dir, deg_to_rad(float(c["entrance_bearing"])))
			var arc := float(c["depth"]) * float(c.get("entrance_slope", 1.25)) / radius
			var out_dir := (dir * cos(arc) + tangent * sin(arc)).normalized()
			var mouth := out_dir * (surface_radius_exact(out_dir) + 0.4)
			var start: Vector3 = center + (mouth - center).normalized() * rad * 0.6
			var tunnel_r := float(c.get("entrance_radius", 2.0))
			var steps := int(ceil(start.distance_to(mouth) / (tunnel_r * 0.8)))
			for s in steps + 1:
				var f := float(s) / float(steps)
				spheres.append([start.lerp(mouth, f), lerpf(tunnel_r * 1.05, tunnel_r * 0.88, f) + rng.randf() * 0.25])
			entrance_pos = mouth
		cavities.append({"id": str(c["id"]), "center": center, "radius": rad, "spheres": spheres, "dir": dir, "entrance": entrance_pos, "cfg": c})
	for a: Dictionary in cfg.get("artifacts", []):
		var dir := _vec(a["dir"]).normalized()
		var pos := dir * (surface_radius_exact(dir) - float(a["depth"]))
		var in_cav := str(a.get("in_cavity", ""))
		if in_cav != "":
			for c in cavities:
				if c["id"] == in_cav:
					# Sit on the cavern floor (the side towards the planet centre).
					pos = (c["center"] as Vector3) - (c["dir"] as Vector3) * (float(c["radius"]) - 1.3)
		artifacts.append({"id": str(a["id"]), "pos": pos, "pocket": float(a.get("pocket", 0.0)), "model": str(a.get("model", "capsule")), "cfg": a})


static func _vec(a: Variant) -> Vector3:
	if a is Vector3:
		return a
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


# ------------------------------------------------------------------ terrain shape

## Region weights at a unit direction (0..1 each, not normalised).
func region_weights(dir: Vector3) -> PackedFloat32Array:
	var w := PackedFloat32Array()
	w.resize(regions.size())
	for i in regions.size():
		var r := regions[i]
		w[i] = smoothstep(float(r["cos_out"]), float(r["cos_in"]), dir.dot(r["dir"]))
	return w


## The region a direction belongs to most (or {} for the planet's open land).
func region_at(dir: Vector3) -> Dictionary:
	var best := {}
	var best_w := 0.35
	var w := region_weights(dir)
	for i in w.size():
		if w[i] > best_w:
			best_w = w[i]
			best = regions[i]
	return best


func _feature_height(f: Dictionary, n: Vector3) -> float:
	var d := n.dot(f["dir"])
	match str(f["type"]):
		"dome", "plateau":
			return float(f["height"]) * smoothstep(float(f["c0"]), float(f["c1"]), d)
		"crater":
			var t := (1.0 - d) * float(f["k"])
			var bowl := -float(f["depth"]) * (1.0 - smoothstep(0.0, 1.0, t))
			var rim := float(f["rim"]) * smoothstep(0.55, 1.0, t) * (1.0 - smoothstep(1.0, 1.9, t))
			return bowl + rim
		"ridge":
			var off := absf(n.dot(f["axis"]))
			var across := 1.0 - smoothstep(0.0, float(f["w"]), off)
			var along := smoothstep(float(f["c_len"]), float(f["c_len_in"]), n.dot(f["mid"]))
			return float(f["height"]) * across * across * along
	return 0.0


## Height of the original (un-dug) surface above the nominal radius, evaluated directly.
## This is the function the voxel generator graph reproduces.
func height_exact(dir: Vector3) -> float:
	var h := hill_amp * hill_noise.get_noise_3dv(dir * hill_freq) + detail_amp * detail_noise.get_noise_3dv(dir * detail_freq)
	var rough := 0.0
	for r in regions:
		if float(r["rough"]) != 0.0:
			rough += float(r["rough"]) * smoothstep(float(r["cos_out"]), float(r["cos_in"]), dir.dot(r["dir"]))
	if rough != 0.0:
		h += rough * rough_noise.get_noise_3dv(dir * rough_freq)
	for f in features:
		h += _feature_height(f, dir)
	var lf := smoothstep(landing_cos_out, landing_cos_in, dir.dot(landing_dir))
	return lerpf(h, landing_height, lf)


func surface_radius_exact(dir: Vector3) -> float:
	return radius + height_exact(dir)


## Height of the original surface from the baked map (bilinear, mirrors the GPU sampler).
## Falls back to the exact function before the map is baked.
func height_at(dir: Vector3) -> float:
	if height_data.is_empty():
		return height_exact(dir)
	var uv := oct_encode(dir)
	var n := height_map_n
	var fx := uv.x * n - 0.5
	var fy := uv.y * n - 0.5
	var x0 := int(floor(fx)); var y0 := int(floor(fy))
	var tx := fx - float(x0); var ty := fy - float(y0)
	var x1 := clampi(x0 + 1, 0, n - 1); var y1 := clampi(y0 + 1, 0, n - 1)
	x0 = clampi(x0, 0, n - 1); y0 = clampi(y0, 0, n - 1)
	var a := lerpf(height_data[y0 * n + x0], height_data[y0 * n + x1], tx)
	var b := lerpf(height_data[y1 * n + x0], height_data[y1 * n + x1], tx)
	return lerpf(a, b, ty)


func surface_radius(dir: Vector3) -> float:
	return radius + height_at(dir)


## Depth below the ORIGINAL surface in metres (negative = above ground).
func depth_at(p: Vector3) -> float:
	var r := p.length()
	if r < 0.001:
		return radius
	return surface_radius(p / r) - r


## Upper bound of the surface radius (used for bounds, ray starts and props).
func max_surface_radius() -> float:
	var tallest := 0.0
	for f in features:
		if f.has("height"):
			tallest += maxf(float(f["height"]), 0.0) * 0.0
			tallest = maxf(tallest, float(f["height"]))
		elif f.has("rim"):
			tallest = maxf(tallest, float(f["rim"]))
	var rough_max := 0.0
	for r in regions:
		rough_max = maxf(rough_max, absf(float(r["rough"])))
	return radius + hill_amp + detail_amp + rough_max + tallest


func spawn_position() -> Vector3:
	return landing_dir * (surface_radius(landing_dir) + 1.2)


## Great-circle distance in metres between two directions (at the nominal radius).
func surface_distance(a: Vector3, b: Vector3) -> float:
	return a.normalized().angle_to(b.normalized()) * radius


# ------------------------------------------------------------------ materials

func bake() -> void:
	var t0 := Time.get_ticks_msec()
	_bake_noise()
	_calibrate_ores()
	_bake_height_map()
	bake_ms = Time.get_ticks_msec() - t0


func _bake_noise() -> void:
	noise_bytes.clear()
	noise_textures.clear()
	for c in NOISE_CHANNELS:
		var n := FastNoiseLite.new()
		n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		n.seed = seed_value * 31 + c * 977 + 5
		n.frequency = 1.0 / 12.0
		n.fractal_type = FastNoiseLite.FRACTAL_FBM
		n.fractal_octaves = 2
		n.fractal_gain = 0.4
		var images: Array[Image] = n.get_seamless_image_3d(NOISE_N, NOISE_N, NOISE_N, false, 0.2, true)
		var bytes := PackedByteArray()
		for img in images:
			if img.get_format() != Image.FORMAT_L8:
				img.convert(Image.FORMAT_L8)
			bytes.append_array(img.get_data())
		noise_bytes.append(bytes)
		var tex := ImageTexture3D.new()
		tex.create(Image.FORMAT_L8, NOISE_N, NOISE_N, NOISE_N, false, images)
		noise_textures.append(tex)


## Converts each ore's designer-facing `abundance` (fraction of rock inside its depth band)
## into a noise threshold using the actual histogram of the baked noise. Ores tied to a region
## get a second, lower threshold that applies inside it (`boost` x the abundance).
func _calibrate_ores() -> void:
	var hist: Array[PackedInt32Array] = []
	var totals := PackedInt32Array()
	for c in NOISE_CHANNELS:
		var h := PackedInt32Array()
		h.resize(256)
		var b := noise_bytes[c]
		var n := 0
		for i in range(0, b.size(), 7):
			h[b[i]] += 1
			n += 1
		hist.append(h)
		totals.append(n)
	for o in ores:
		var h := hist[int(o["channel"])]
		var total := float(totals[int(o["channel"])])
		o["thr"] = _threshold_for(h, total, float(o["abundance"]))
		o["thr_boost"] = _threshold_for(h, total, minf(float(o["abundance"]) * float(o["boost"]), 0.45))


static func _threshold_for(h: PackedInt32Array, total: float, abundance: float) -> float:
	var want := abundance * total
	var acc := 0.0
	var level := 255
	while level > 0 and acc < want:
		acc += float(h[level])
		level -= 1
	return (float(level) + 0.5) / 255.0


func _cache_key() -> String:
	var src := {"v": BAKE_VERSION, "n": height_map_n, "r": radius, "seed": seed_value, "t": cfg.get("terrain", {}), "regions": cfg.get("regions", [])}
	return "%s_g%d_%s" % [id, generation, str(hash(JSON.stringify(src, "", true)))]


func _bake_height_map() -> void:
	var n := height_map_n
	var path := "user://planet_cache/%s.heights" % _cache_key()
	bake_from_cache = false
	if FileAccess.file_exists(path):
		var f := FileAccess.open(path, FileAccess.READ)
		if f != null and f.get_length() == n * n * 3 * 4:
			var all := f.get_buffer(n * n * 3 * 4).to_float32_array()
			height_data = all.slice(0, n * n)
			tint_data = all.slice(n * n)
			bake_from_cache = true
	if not bake_from_cache:
		var rows: Array = []
		rows.resize(n)
		var tint := FastNoiseLite.new()
		tint.seed = seed_value + 77
		tint.frequency = 1.0
		tint.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		var job := func(y: int) -> void:
			var row := PackedFloat32Array()
			row.resize(n * 3)
			for x in n:
				var dir := oct_decode(Vector2((float(x) + 0.5) / float(n), (float(y) + 0.5) / float(n)))
				row[x] = height_exact(dir)
				row[n + x * 2] = tint.get_noise_3dv(dir * 1.9) * 0.5 + 0.5
				row[n + x * 2 + 1] = tint.get_noise_3dv(dir * 4.3 + Vector3(9.1, 3.3, 7.7)) * 0.5 + 0.5
			rows[y] = row
		var task := WorkerThreadPool.add_group_task(job, n, -1, true, "height map bake")
		WorkerThreadPool.wait_for_group_task_completion(task)
		height_data = PackedFloat32Array()
		height_data.resize(n * n)
		tint_data = PackedFloat32Array()
		tint_data.resize(n * n * 2)
		for y in n:
			var row: PackedFloat32Array = rows[y]
			for x in n:
				height_data[y * n + x] = row[x]
				tint_data[(y * n + x) * 2] = row[n + x * 2]
				tint_data[(y * n + x) * 2 + 1] = row[n + x * 2 + 1]
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://planet_cache"))
		var out := FileAccess.open(path, FileAccess.WRITE)
		if out != null:
			out.store_buffer(height_data.to_byte_array())
			out.store_buffer(tint_data.to_byte_array())
	var data := PackedFloat32Array()
	data.resize(n * n * 3)
	for i in n * n:
		data[i * 3] = height_data[i]
		data[i * 3 + 1] = tint_data[i * 2]
		data[i * 3 + 2] = tint_data[i * 2 + 1]
	height_image = Image.create_from_data(n, n, false, Image.FORMAT_RGBF, data.to_byte_array())
	# Half-float is used for the GPU copy: unlike RGB32F it is linearly filterable on every desktop GPU.
	var gpu_image: Image = height_image.duplicate()
	gpu_image.convert(Image.FORMAT_RGBAH)
	height_texture = ImageTexture.create_from_image(gpu_image)


## Octahedral mapping (y = pole). Mirrored exactly in terrain.gdshader.
static func oct_encode(n: Vector3) -> Vector2:
	var a := n / (absf(n.x) + absf(n.y) + absf(n.z))
	var o := Vector2(a.x, a.z)
	if a.y < 0.0:
		o = Vector2((1.0 - absf(a.z)) * (1.0 if a.x >= 0.0 else -1.0), (1.0 - absf(a.x)) * (1.0 if a.z >= 0.0 else -1.0))
	return o * 0.5 + Vector2(0.5, 0.5)


static func oct_decode(uv: Vector2) -> Vector3:
	var f := uv * 2.0 - Vector2.ONE
	var n := Vector3(f.x, 1.0 - absf(f.x) - absf(f.y), f.y)
	var t := maxf(-n.y, 0.0)
	n.x += -t if n.x >= 0.0 else t
	n.z += -t if n.z >= 0.0 else t
	return n.normalized()


## Surface tint channels (0..1) used for meadow colouring and prop placement.
func tint_at(dir: Vector3) -> Vector2:
	if tint_data.is_empty():
		return Vector2(0.5, 0.5)
	var uv := oct_encode(dir)
	var i := clampi(int(uv.y * height_map_n), 0, height_map_n - 1) * height_map_n + clampi(int(uv.x * height_map_n), 0, height_map_n - 1)
	return Vector2(tint_data[i * 2], tint_data[i * 2 + 1])


## Trilinear sample of a tileable noise channel; `q` is in texel units. Mirrors GPU filtering.
func sample_noise(channel: int, q: Vector3) -> float:
	var b := noise_bytes[channel]
	var n := NOISE_N
	var fx := q.x - 0.5
	var fy := q.y - 0.5
	var fz := q.z - 0.5
	var x0 := int(floor(fx)); var y0 := int(floor(fy)); var z0 := int(floor(fz))
	var tx := fx - float(x0); var ty := fy - float(y0); var tz := fz - float(z0)
	x0 = posmod(x0, n); y0 = posmod(y0, n); z0 = posmod(z0, n)
	var x1 := (x0 + 1) % n; var y1 := (y0 + 1) % n; var z1 := (z0 + 1) % n
	var r00 := (z0 * n + y0) * n; var r01 := (z0 * n + y1) * n
	var r10 := (z1 * n + y0) * n; var r11 := (z1 * n + y1) * n
	var c00 := lerpf(float(b[r00 + x0]), float(b[r00 + x1]), tx)
	var c01 := lerpf(float(b[r01 + x0]), float(b[r01 + x1]), tx)
	var c10 := lerpf(float(b[r10 + x0]), float(b[r10 + x1]), tx)
	var c11 := lerpf(float(b[r11 + x0]), float(b[r11 + x1]), tx)
	return lerpf(lerpf(c00, c01, ty), lerpf(c10, c11, ty), tz) / 255.0


## Strata shift (metres) at a direction: regions with lifted strata expose deeper rock.
func strata_lift(dir: Vector3) -> float:
	var lift := 0.0
	for r in regions:
		if float(r["lift"]) != 0.0:
			lift += float(r["lift"]) * smoothstep(float(r["cos_out"]), float(r["cos_in"]), dir.dot(r["dir"]))
	return lift


## Layer depth: depth below the original surface plus a gentle warp so strata are not perfect
## shells, plus the regional strata lift.
func layer_depth(p: Vector3, depth: float) -> float:
	var w := (sin(p.x * 0.21 + 1.3) + sin(p.y * 0.17 + 4.1) + sin(p.z * 0.19 + 2.2)) * (layer_warp / 3.0)
	var lift := strata_lift(p.normalized()) if not regions.is_empty() else 0.0
	return depth + w * smoothstep(1.0, 5.0, depth) + lift * smoothstep(0.0, 1.5, depth)


## Material index at a point (planet-local metres). Does not know about digging - combine with the voxel SDF.
func material_at(p: Vector3) -> int:
	return material_for(p, depth_at(p))


func material_for(p: Vector3, depth: float) -> int:
	var dl := layer_depth(p, depth)
	var dir := p.normalized()
	for o in ores:
		var lo: float = o["min"]
		var hi: float = o["max"]
		if dl > lo and dl < hi:
			var edge := maxf(1.0 - (dl - lo) / EDGE_FADE, 1.0 - (hi - dl) / EDGE_FADE)
			var base_thr: float = o["thr"]
			var ri: int = o["region"]
			if ri >= 0:
				var rg := regions[ri]
				base_thr = lerpf(base_thr, o["thr_boost"], smoothstep(float(rg["cos_out"]), float(rg["cos_in"]), dir.dot(rg["dir"])))
			var thr: float = lerpf(base_thr, 1.01, clampf(edge, 0.0, 1.0))
			if sample_noise(o["channel"], p * (o["scale"] as float) + (o["offset"] as Vector3)) > thr:
				return o["mat"]
	for i in layer_bottom.size():
		if dl < layer_bottom[i]:
			return layer_mat[i]
	return layer_mat[layer_mat.size() - 1]


func hardness_of(mat: int) -> int:
	return _material_hardness[mat]


## Nearest ore-bearing points around `origin` (used by the scanner). Coarse grid search.
func find_ore_near(origin: Vector3, max_range: float, step := 2.0, limit := 40) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var n := int(ceil(max_range / step))
	for ix in range(-n, n + 1):
		for iy in range(-n, n + 1):
			for iz in range(-n, n + 1):
				var p := origin + Vector3(ix, iy, iz) * step
				var dist := p.distance_to(origin)
				if dist > max_range:
					continue
				var d := depth_at(p)
				if d < 0.2:
					continue
				var m := material_for(p, d)
				var cat: String = GameData.materials[m]["category"]
				if cat == "ore" or cat == "crystal" or cat == "exotic":
					out.append({"pos": p, "mat": m, "dist": dist})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var va := float(GameData.materials[a["mat"]]["value"]) / (4.0 + float(a["dist"]))
		var vb := float(GameData.materials[b["mat"]]["value"]) / (4.0 + float(b["dist"]))
		return va > vb)
	if out.size() > limit:
		out.resize(limit)
	return out


# ------------------------------------------------------------------ voxel generator graph

## Builds the Voxel Tools generator graph. All distances inside the graph are in VOXELS.
func build_generator() -> VoxelGeneratorGraph:
	var gen := VoxelGeneratorGraph.new()
	var g: VoxelGraphFunction = gen.get_main_function()
	var b := _GraphBuilder.new(g)
	var x := b.node(VoxelGraphFunction.NODE_INPUT_X)
	var y := b.node(VoxelGraphFunction.NODE_INPUT_Y)
	var z := b.node(VoxelGraphFunction.NODE_INPUT_Z)
	var norm := b.node(VoxelGraphFunction.NODE_NORMALIZE_3D, [x, y, z])
	var nx := [norm[0], 0]; var ny := [norm[0], 1]; var nz := [norm[0], 2]; var length := [norm[0], 3]

	# hills
	var hn := b.node(VoxelGraphFunction.NODE_FAST_NOISE_3D, [b.mul(nx, hill_freq), b.mul(ny, hill_freq), b.mul(nz, hill_freq)])
	g.set_node_param(hn[0], 0, hill_noise)
	var dn := b.node(VoxelGraphFunction.NODE_FAST_NOISE_3D, [b.mul(nx, detail_freq), b.mul(ny, detail_freq), b.mul(nz, detail_freq)])
	g.set_node_param(dn[0], 0, detail_noise)
	var h: Variant = b.add(b.mul(hn, hill_amp), b.mul(dn, detail_amp))
	# regional roughness
	var rough: Variant = null
	for r in regions:
		if float(r["rough"]) == 0.0:
			continue
		var w := b.smoothstep(b.dot3(nx, ny, nz, r["dir"]), float(r["cos_out"]), float(r["cos_in"]))
		var term: Variant = b.mul(w, float(r["rough"]))
		rough = term if rough == null else b.add(rough, term)
	if rough != null:
		var rn := b.node(VoxelGraphFunction.NODE_FAST_NOISE_3D, [b.mul(nx, rough_freq), b.mul(ny, rough_freq), b.mul(nz, rough_freq)])
		g.set_node_param(rn[0], 0, rough_noise)
		h = b.add(h, b.mul(rough, rn))
	# landforms
	for f in features:
		var dot: Variant = b.dot3(nx, ny, nz, f["dir"])
		match str(f["type"]):
			"dome", "plateau":
				h = b.add(h, b.mul(b.smoothstep(dot, float(f["c0"]), float(f["c1"])), float(f["height"])))
			"crater":
				var t: Variant = b.mul(b.sub(1.0, dot), float(f["k"]))
				var bowl: Variant = b.mul(b.sub(1.0, b.smoothstep(t, 0.0, 1.0)), -float(f["depth"]))
				var rim: Variant = b.mul(b.mul(b.smoothstep(t, 0.55, 1.0), b.sub(1.0, b.smoothstep(t, 1.0, 1.9))), float(f["rim"]))
				h = b.add(h, b.add(bowl, rim))
			"ridge":
				var off := b.node(VoxelGraphFunction.NODE_ABS, [b.dot3(nx, ny, nz, f["axis"])])
				var across: Variant = b.sub(1.0, b.smoothstep(off, 0.0, float(f["w"])))
				var along := b.smoothstep(b.dot3(nx, ny, nz, f["mid"]), float(f["c_len"]), float(f["c_len_in"]))
				h = b.add(h, b.mul(b.mul(b.mul(across, across), along), float(f["height"])))
	# landing pad flattening
	var lf := b.smoothstep(b.dot3(nx, ny, nz, landing_dir), landing_cos_out, landing_cos_in)
	h = b.node(VoxelGraphFunction.NODE_MIX, [h, landing_height, lf])

	# surface radius (voxels) and base sdf
	var surf_v: Variant = b.mul(b.add(h, radius), inv_voxel)
	var sdf: Variant = b.sub(length, surf_v)

	# worm caves
	var cv: Dictionary = cfg.get("caves", {})
	if not cv.is_empty():
		var period_v := float(cv.get("period", 22.0)) * inv_voxel
		var n1 := ZN_FastNoiseLite.new()
		n1.noise_type = ZN_FastNoiseLite.TYPE_OPEN_SIMPLEX_2
		n1.seed = seed_value + 501
		n1.period = period_v
		n1.fractal_type = ZN_FastNoiseLite.FRACTAL_NONE
		var n2: ZN_FastNoiseLite = n1.duplicate()
		n2.seed = seed_value + 907
		var c1 := b.node(VoxelGraphFunction.NODE_FAST_NOISE_3D, [x, y, z])
		g.set_node_param(c1[0], 0, n1)
		var c2 := b.node(VoxelGraphFunction.NODE_FAST_NOISE_3D, [x, y, z])
		g.set_node_param(c2[0], 0, n2)
		var w := b.node(VoxelGraphFunction.NODE_MAX, [b.node(VoxelGraphFunction.NODE_ABS, [c1]), b.node(VoxelGraphFunction.NODE_ABS, [c2])])
		# depth in metres below the original surface
		var depth_m: Variant = b.mul(b.sub(surf_v, length), voxel_size)
		var min_d := float(cv.get("min_depth", 7.0))
		var max_d := float(cv.get("max_depth", 30.0))
		var band: Variant = b.mul(b.smoothstep(depth_m, min_d, min_d + 3.0), b.sub(1.0, b.smoothstep(depth_m, max_d - 4.0, max_d)))
		var width_eff: Variant = b.mul(band, float(cv.get("width", 0.08)))
		var cave_neg: Variant = b.mul(b.sub(width_eff, w), period_v * 0.42)
		sdf = b.node(VoxelGraphFunction.NODE_MAX, [sdf, cave_neg])

	# hand-placed caverns, entrances and artifact pockets
	var spheres: Array = []
	for c in cavities:
		spheres.append_array(c["spheres"])
	for a in artifacts:
		if float(a["pocket"]) > 0.0:
			spheres.append([a["pos"], float(a["pocket"])])
	spheres.append([Vector3.ZERO, core_radius])
	for s: Array in spheres:
		var c: Vector3 = (s[0] as Vector3) * inv_voxel
		# NOTE: NODE_DISTANCE_3D ignores constant default inputs in Voxel Tools 1.7, so cavities are
		# carved with a translated SdfSphere + smooth subtraction instead (also gives softer edges).
		var sph := b.node(VoxelGraphFunction.NODE_SDF_SPHERE, [b.sub(x, c.x), b.sub(y, c.y), b.sub(z, c.z), float(s[1]) * inv_voxel])
		var cut := b.node(VoxelGraphFunction.NODE_SDF_SMOOTH_SUBTRACT, [sdf, sph])
		g.set_node_param(cut[0], 0, 1.5)
		sdf = cut

	b.node(VoxelGraphFunction.NODE_OUTPUT_SDF, [sdf])
	var result: Dictionary = gen.compile()
	if not bool(result.get("success", false)):
		push_error("Geology: generator graph failed to compile: %s" % str(result))
	return gen


## Tiny helper that makes building VoxelGraphFunction graphs readable.
## A "port" is [node_id, output_index]; plain numbers are used as constant default inputs.
class _GraphBuilder:
	var g: VoxelGraphFunction
	var _n := 0

	func _init(graph: VoxelGraphFunction) -> void:
		g = graph

	func node(type: int, inputs: Array = []) -> Array:
		_n += 1
		var nid: int = g.create_node(type, Vector2(_n % 12 * 180, _n / 12 * 120))
		for i in inputs.size():
			var v: Variant = inputs[i]
			if v is Array:
				g.add_connection(int(v[0]), int(v[1]), nid, i)
			else:
				g.set_node_default_input(nid, i, float(v))
		return [nid, 0]

	func add(a: Variant, b: Variant) -> Array:
		return node(VoxelGraphFunction.NODE_ADD, [a, b])

	func sub(a: Variant, b: Variant) -> Array:
		return node(VoxelGraphFunction.NODE_SUBTRACT, [a, b])

	func mul(a: Variant, b: Variant) -> Array:
		return node(VoxelGraphFunction.NODE_MULTIPLY, [a, b])

	func dot3(nx: Variant, ny: Variant, nz: Variant, d: Vector3) -> Array:
		return add(add(mul(nx, d.x), mul(ny, d.y)), mul(nz, d.z))

	func smoothstep(x: Variant, edge0: float, edge1: float) -> Array:
		var n := node(VoxelGraphFunction.NODE_SMOOTHSTEP, [x])
		g.set_node_param(n[0], 0, edge0)
		g.set_node_param(n[0], 1, edge1)
		return n


# ------------------------------------------------------------------ shader parameters

func apply_to_material(mat: ShaderMaterial) -> void:
	mat.set_shader_parameter("voxel_size", voxel_size)
	mat.set_shader_parameter("planet_radius", radius)
	mat.set_shader_parameter("height_map", height_texture)
	mat.set_shader_parameter("noise_a", noise_textures[0])
	mat.set_shader_parameter("noise_b", noise_textures[1])
	mat.set_shader_parameter("noise_c", noise_textures[2])
	mat.set_shader_parameter("noise_n", float(NOISE_N))
	mat.set_shader_parameter("layer_warp", layer_warp)
	mat.set_shader_parameter("edge_fade", EDGE_FADE)
	var lb := PackedFloat32Array(); lb.resize(MAX_LAYERS); lb.fill(99999.0)
	var lm := PackedInt32Array(); lm.resize(MAX_LAYERS)
	for i in mini(layer_bottom.size(), MAX_LAYERS):
		lb[i] = layer_bottom[i]
		lm[i] = layer_mat[i]
	mat.set_shader_parameter("layer_count", mini(layer_bottom.size(), MAX_LAYERS))
	mat.set_shader_parameter("layer_bottom", lb)
	mat.set_shader_parameter("layer_mat", lm)
	var oa: Array[Vector4] = []; var ob: Array[Vector4] = []; var oc: Array[Vector4] = []
	var om := PackedInt32Array(); om.resize(MAX_ORES)
	for i in MAX_ORES:
		if i < ores.size():
			var o := ores[i]
			var off: Vector3 = o["offset"]
			oa.append(Vector4(o["min"], o["max"], o["scale"], o["thr"]))
			ob.append(Vector4(off.x, off.y, off.z, float(o["channel"])))
			var ri: int = o["region"]
			oc.append(Vector4(float(ri), o["thr_boost"], 0.0, 0.0))
			om[i] = o["mat"]
		else:
			oa.append(Vector4.ZERO); ob.append(Vector4.ZERO); oc.append(Vector4(-1, 0, 0, 0))
	mat.set_shader_parameter("ore_count", mini(ores.size(), MAX_ORES))
	mat.set_shader_parameter("ore_a", oa)
	mat.set_shader_parameter("ore_b", ob)
	mat.set_shader_parameter("ore_c", oc)
	mat.set_shader_parameter("ore_mat", om)
	# regions: direction + cos edges, then (lift, cover, rough, 0), then their ground-cover colours
	var ra: Array[Vector4] = []; var rb: Array[Vector4] = []
	var rg0: Array[Color] = []; var rg1: Array[Color] = []
	for i in MAX_REGIONS:
		if i < regions.size():
			var r := regions[i]
			var d: Vector3 = r["dir"]
			ra.append(Vector4(d.x, d.y, d.z, float(r["cos_in"])))
			rb.append(Vector4(float(r["cos_out"]), float(r["lift"]), float(r["cover"]), 0.0))
			var cols: Array = (r["cfg"] as Dictionary).get("grass", [])
			rg0.append(Color(str(cols[0])) if cols.size() > 0 else Color(0, 0, 0, 0))
			rg1.append(Color(str(cols[1])) if cols.size() > 1 else Color(0, 0, 0, 0))
		else:
			ra.append(Vector4(0, 1, 0, 2.0)); rb.append(Vector4(2.0, 0, 1, 0)); rg0.append(Color(0, 0, 0, 0)); rg1.append(Color(0, 0, 0, 0))
	mat.set_shader_parameter("region_count", mini(regions.size(), MAX_REGIONS))
	mat.set_shader_parameter("region_a", ra)
	mat.set_shader_parameter("region_b", rb)
	mat.set_shader_parameter("region_grass_a", rg0)
	mat.set_shader_parameter("region_grass_b", rg1)
	var colors: Array[Color] = []; var colors2: Array[Color] = []; var fx: Array[Vector4] = []; var pbr: Array[Vector4] = []
	# roughness, metallic, strata strength, relief strength - by category unless the material overrides
	var finish := {"soil": Vector4(0.95, 0.0, 1.0, 1.0), "rock": Vector4(0.86, 0.0, 0.7, 1.35),
		"ore": Vector4(0.42, 0.75, 0.0, 1.0), "crystal": Vector4(0.2, 0.0, 0.0, 0.6), "exotic": Vector4(0.14, 0.25, 0.0, 0.5)}
	for i in GameData.MAX_MATERIALS:
		if i < GameData.materials.size():
			var m := GameData.materials[i]
			colors.append((m["color_c"] as Color))
			colors2.append((m["color2_c"] as Color))
			var is_ore := 1.0 if str(m["category"]) in ["ore", "crystal", "exotic"] else 0.0
			var kind := 1.0 if str(m["category"]) == "rock" else (2.0 if str(m["category"]) in ["crystal", "exotic"] else 0.0)
			fx.append(Vector4(float(m.get("emission", 0.0)), float(m.get("sparkle", 0.0)), is_ore, kind))
			var f: Vector4 = finish.get(str(m["category"]), Vector4(0.9, 0.0, 1.0, 1.0))
			pbr.append(Vector4(float(m.get("roughness", f.x)), float(m.get("metallic", f.y)), f.z, f.w))
		else:
			colors.append(Color.MAGENTA); colors2.append(Color.MAGENTA); fx.append(Vector4.ZERO); pbr.append(Vector4(0.9, 0, 0, 0))
	mat.set_shader_parameter("mat_color", colors)
	mat.set_shader_parameter("mat_color2", colors2)
	mat.set_shader_parameter("mat_fx", fx)
	mat.set_shader_parameter("mat_pbr", pbr)
	var pal: Dictionary = cfg.get("palette", {})
	var grass: Array = pal.get("grass", ["#7d9a5e", "#6b8f66", "#a3a868"])
	mat.set_shader_parameter("grass_a", Color(str(grass[0])))
	mat.set_shader_parameter("grass_b", Color(str(grass[1])))
	mat.set_shader_parameter("grass_c", Color(str(grass[2])))
	mat.set_shader_parameter("rim_color", Color(str(pal.get("rim", "#39c4b4"))))
	var look: Dictionary = cfg.get("look", {})
	mat.set_shader_parameter("turf_depth", float(look.get("turf_depth", 0.34)))
	mat.set_shader_parameter("cover_relief", float(look.get("cover_relief", 0.55)))
	mat.set_shader_parameter("cover_roughness", float(look.get("cover_roughness", 0.92)))
