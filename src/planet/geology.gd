class_name Geology
extends RefCounted
## Deterministic description of a planet's shape and what it is made of.
##
## One Geology instance is the single source of truth for:
##   * the voxel generator graph (terrain SDF: hills, mountains, caves, cavities, core chamber)
##   * CPU material queries used by gameplay (`material_at`)
##   * the data handed to the terrain shader so that what you SEE is what you DIG
##
## Everything derives from the planet config + seed, so the same seed always produces the
## same planet (and the same in multiplayer on every peer).

const NOISE_N := 96                 ## edge length of the tileable 3D material-noise textures
const NOISE_CHANNELS := 3
const HEIGHT_MAP_N := 256           ## octahedral height map resolution
const MAX_LAYERS := 8
const MAX_ORES := 12
const EDGE_FADE := 1.5              ## metres over which an ore band fades out at its depth limits

var cfg: Dictionary
var id: String
var seed_value: int
var radius: float                   ## nominal planet radius in metres
var voxel_size: float
var inv_voxel: float

# terrain shape
var hill_noise: ZN_FastNoiseLite
var detail_noise: ZN_FastNoiseLite
var hill_amp := 3.0
var hill_freq := 1.7
var detail_amp := 0.6
var detail_freq := 5.5
var mountains: Array[Dictionary] = []     ## {dir: Vector3, height: float, cos_w: float}
var basins: Array[Dictionary] = []
var landing_dir := Vector3.UP
var landing_cos_in := 0.98
var landing_cos_out := 0.94
var landing_height := 0.5

# geology
var layer_bottom := PackedFloat32Array()
var layer_mat := PackedInt32Array()
var layer_warp := 1.5
var ores: Array[Dictionary] = []          ## {mat, min, max, thr, scale, offset: Vector3, channel}
var cavities: Array[Dictionary] = []      ## {id, center: Vector3, radius, spheres: Array[[Vector3, float]], cfg}
var artifacts: Array[Dictionary] = []     ## {id, pos: Vector3, pocket, model, cfg}
var core_radius := 5.0

# baked data
var noise_bytes: Array[PackedByteArray] = []
var noise_textures: Array[ImageTexture3D] = []
var height_image: Image
var height_texture: ImageTexture
var _material_hardness := PackedInt32Array()


func _init(config: Dictionary, seed_offset := 0) -> void:
	cfg = config
	id = str(cfg.get("id", "planet"))
	seed_value = int(cfg.get("seed", 1)) + seed_offset
	radius = float(cfg.get("radius", 48.0))
	voxel_size = float(cfg.get("voxel_size", 0.5))
	inv_voxel = 1.0 / voxel_size
	_setup_terrain()
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
	for m: Dictionary in t.get("mountains", []):
		mountains.append({"dir": _vec(m["dir"]).normalized(), "height": float(m["height"]), "cos_w": cos(float(m["width"]))})
	for b: Dictionary in t.get("basins", []):
		basins.append({"dir": _vec(b["dir"]).normalized(), "height": -float(b["depth"]), "cos_w": cos(float(b["width"]))})
	var l: Dictionary = t.get("landing", {})
	landing_dir = _vec(l.get("dir", [0, 1, 0])).normalized()
	var flat := float(l.get("flat_radius", 0.17))
	landing_cos_in = cos(flat)
	landing_cos_out = cos(flat + float(l.get("blend", 0.15)))
	landing_height = float(l.get("height", 0.5))


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
			"thr": 0.75,   # replaced by _calibrate_ores() once the noise is baked
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
		var center := dir * (surface_radius(dir) - float(c["depth"]))
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
			var arc := float(c["depth"]) * 1.25 / radius
			var out_dir := (dir * cos(arc) + tangent * sin(arc)).normalized()
			var mouth := out_dir * (surface_radius(out_dir) + 0.4)
			var start: Vector3 = center + (mouth - center).normalized() * rad * 0.6
			var steps := int(ceil(start.distance_to(mouth) / 1.6))
			for s in steps + 1:
				var f := float(s) / float(steps)
				spheres.append([start.lerp(mouth, f), lerpf(2.1, 1.75, f) + rng.randf() * 0.25])
			entrance_pos = mouth
		cavities.append({"id": str(c["id"]), "center": center, "radius": rad, "spheres": spheres, "dir": dir, "entrance": entrance_pos, "cfg": c})
	for a: Dictionary in cfg.get("artifacts", []):
		var dir := _vec(a["dir"]).normalized()
		var pos := dir * (surface_radius(dir) - float(a["depth"]))
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


# ------------------------------------------------------------------ terrain shape (CPU mirror of the generator graph)

## Height of the original (un-dug) surface above the nominal radius, for a unit direction.
func height_at(dir: Vector3) -> float:
	var h := hill_amp * hill_noise.get_noise_3dv(dir * hill_freq) + detail_amp * detail_noise.get_noise_3dv(dir * detail_freq)
	for m in mountains:
		h += float(m["height"]) * smoothstep(float(m["cos_w"]), 1.0, dir.dot(m["dir"]))
	for b in basins:
		h += float(b["height"]) * smoothstep(float(b["cos_w"]), 1.0, dir.dot(b["dir"]))
	var f := smoothstep(landing_cos_out, landing_cos_in, dir.dot(landing_dir))
	return lerpf(h, landing_height, f)


func surface_radius(dir: Vector3) -> float:
	return radius + height_at(dir)


## Depth below the ORIGINAL surface in metres (negative = above ground).
func depth_at(p: Vector3) -> float:
	var r := p.length()
	if r < 0.001:
		return radius
	return surface_radius(p / r) - r


func max_surface_radius() -> float:
	var extra := hill_amp + detail_amp
	var top := 0.0
	for m in mountains:
		top = maxf(top, float(m["height"]))
	return radius + extra + top


func spawn_position() -> Vector3:
	return landing_dir * (surface_radius(landing_dir) + 1.2)


# ------------------------------------------------------------------ materials

func bake() -> void:
	_bake_noise()
	_calibrate_ores()
	_bake_height_map()


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
## into a noise threshold using the actual histogram of the baked noise.
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
		var want := float(o["abundance"]) * float(totals[int(o["channel"])])
		var acc := 0.0
		var level := 255
		while level > 0 and acc < want:
			acc += float(h[level])
			level -= 1
		o["thr"] = (float(level) + 0.5) / 255.0


func _bake_height_map() -> void:
	var n := HEIGHT_MAP_N
	var data := PackedFloat32Array()
	data.resize(n * n * 3)
	var tint := FastNoiseLite.new()
	tint.seed = seed_value + 77
	tint.frequency = 1.0
	tint.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	var k := 0
	for y in n:
		for x in n:
			var dir := oct_decode(Vector2((float(x) + 0.5) / float(n), (float(y) + 0.5) / float(n)))
			data[k] = height_at(dir)
			data[k + 1] = tint.get_noise_3dv(dir * 1.9) * 0.5 + 0.5
			data[k + 2] = tint.get_noise_3dv(dir * 4.3 + Vector3(9.1, 3.3, 7.7)) * 0.5 + 0.5
			k += 3
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
	if height_image == null:
		return Vector2(0.5, 0.5)
	var uv := oct_encode(dir)
	var c := height_image.get_pixel(clampi(int(uv.x * HEIGHT_MAP_N), 0, HEIGHT_MAP_N - 1), clampi(int(uv.y * HEIGHT_MAP_N), 0, HEIGHT_MAP_N - 1))
	return Vector2(c.g, c.b)


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


## Layer depth: depth below the original surface plus a gentle warp so strata are not perfect shells.
func layer_depth(p: Vector3, depth: float) -> float:
	var w := (sin(p.x * 0.21 + 1.3) + sin(p.y * 0.17 + 4.1) + sin(p.z * 0.19 + 2.2)) * (layer_warp / 3.0)
	return depth + w * smoothstep(1.0, 5.0, depth)


## Material index at a point (planet-local metres). Does not know about digging - combine with the voxel SDF.
func material_at(p: Vector3) -> int:
	return material_for(p, depth_at(p))


func material_for(p: Vector3, depth: float) -> int:
	var dl := layer_depth(p, depth)
	for o in ores:
		var lo: float = o["min"]
		var hi: float = o["max"]
		if dl > lo and dl < hi:
			var edge := maxf(1.0 - (dl - lo) / EDGE_FADE, 1.0 - (hi - dl) / EDGE_FADE)
			var thr: float = lerpf(o["thr"], 1.01, clampf(edge, 0.0, 1.0))
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
	for m: Dictionary in mountains + basins:
		var d: Vector3 = m["dir"]
		var dot: Variant = b.add(b.add(b.mul(nx, d.x), b.mul(ny, d.y)), b.mul(nz, d.z))
		var s := b.smoothstep(dot, float(m["cos_w"]), 1.0)
		h = b.add(h, b.mul(s, float(m["height"])))
	# landing pad flattening
	var ldot: Variant = b.add(b.add(b.mul(nx, landing_dir.x), b.mul(ny, landing_dir.y)), b.mul(nz, landing_dir.z))
	var lf := b.smoothstep(ldot, landing_cos_out, landing_cos_in)
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
	var oa: Array[Vector4] = []; var ob: Array[Vector4] = []
	var om := PackedInt32Array(); om.resize(MAX_ORES)
	for i in MAX_ORES:
		if i < ores.size():
			var o := ores[i]
			var off: Vector3 = o["offset"]
			oa.append(Vector4(o["min"], o["max"], o["scale"], o["thr"]))
			ob.append(Vector4(off.x, off.y, off.z, float(o["channel"])))
			om[i] = o["mat"]
		else:
			oa.append(Vector4.ZERO); ob.append(Vector4.ZERO)
	mat.set_shader_parameter("ore_count", mini(ores.size(), MAX_ORES))
	mat.set_shader_parameter("ore_a", oa)
	mat.set_shader_parameter("ore_b", ob)
	mat.set_shader_parameter("ore_mat", om)
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
			var rocky := 1.0 if str(m["category"]) == "rock" else (2.0 if str(m["category"]) in ["crystal", "exotic"] else 0.0)
			fx.append(Vector4(float(m.get("emission", 0.0)), float(m.get("sparkle", 0.0)), is_ore, rocky))
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
