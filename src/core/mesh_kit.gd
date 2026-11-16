class_name MeshKit
extends RefCounted
## Procedural modelling kit: combines primitives into ONE vertex-coloured ArrayMesh.
## Every prop, tool, robot and machine in the game is modelled in code with this, so the
## whole world shares one material (res://shaders/prop.gdshader) and one visual language.
##
## Vertex data: COLOR = albedo (sRGB), UV.x = emission, UV.y = sway weight,
##              UV2.x = roughness, UV2.y = metallic.
##
## Two families of primitives:
##   * hard-surface (hbox, prism, lathe, tube, pipe, spiral, louvre) - flat faces with small
##     bevels that catch the light; use these for anything manufactured.
##   * organic (sphere, blob, rbox, rock, crystal, leaf) - for terrain props and soft parts.
## Set the surface finish before adding parts: kit.paint() / bare() / cast() / rubber() / ...

const PROP_SHADER := preload("res://shaders/prop.gdshader")
const VIEWMODEL_FOV := 62.0

var _verts := PackedVector3Array()
var _normals := PackedVector3Array()
var _colors := PackedColorArray()
var _uvs := PackedVector2Array()
var _uv2s := PackedVector2Array()
var _indices := PackedInt32Array()

var emission := 0.0      ## applied to subsequently added parts
var sway := 0.0          ## applied to subsequently added parts (scaled by local height when sway_by_height)
var sway_by_height := true
var rough := 0.7         ## surface roughness of subsequently added parts
var metal := 0.0         ## surface metallic of subsequently added parts

static var _prim_cache: Dictionary = {}
static var _shared_material: ShaderMaterial
static var _sway_material: ShaderMaterial
static var _ico_verts := PackedVector3Array()
static var _ico_faces := PackedInt32Array()


# ------------------------------------------------------------------ materials

static func material() -> ShaderMaterial:
	if _shared_material == null:
		_shared_material = ShaderMaterial.new()
		_shared_material.shader = PROP_SHADER
	return _shared_material


static func sway_material() -> ShaderMaterial:
	if _sway_material == null:
		_sway_material = ShaderMaterial.new()
		_sway_material.shader = PROP_SHADER
		_sway_material.set_shader_parameter("sway_amount", 1.0)
	return _sway_material


## A fresh (non-shared) material for first-person tools so it can be flashed/tinted.
static func new_viewmodel_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = PROP_SHADER
	m.set_shader_parameter("viewmodel", true)
	m.set_shader_parameter("viewmodel_fov", VIEWMODEL_FOV)
	return m


static func new_material(emission_scale := 1.0, _unused := 0.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = PROP_SHADER
	m.set_shader_parameter("emission_scale", emission_scale)
	return m


# ------------------------------------------------------------------ surface finish

func surf(roughness: float, metallic := 0.0) -> MeshKit:
	rough = roughness
	metal = metallic
	return self


func paint() -> MeshKit:      ## satin painted panel
	return surf(0.48, 0.0)


func matte() -> MeshKit:      ## chalky / fabric / stone / wood
	return surf(0.86, 0.0)


func bare() -> MeshKit:       ## machined bare metal
	return surf(0.34, 0.62)


func cast() -> MeshKit:       ## rough cast or worn metal
	return surf(0.58, 0.6)


func rubber() -> MeshKit:
	return surf(0.93, 0.0)


func gloss() -> MeshKit:      ## glass, lenses, polished gems
	return surf(0.1, 0.0)


func set_emission(e: float) -> MeshKit:
	emission = e
	return self


func set_sway(s: float) -> MeshKit:
	sway = s
	return self


# ------------------------------------------------------------------ low level

func _push(p: Vector3, n: Vector3, color: Color) -> void:
	_verts.append(p)
	_normals.append(n)
	_colors.append(color)
	_uvs.append(Vector2(emission, sway * maxf(p.y, 0.0) if sway_by_height else sway))
	_uv2s.append(Vector2(rough, metal))


func _append(arrays: Array, xform: Transform3D, color: Color) -> void:
	var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var n: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var idx: Variant = arrays[Mesh.ARRAY_INDEX]
	var base := _verts.size()
	var nb := xform.basis.inverse().transposed()
	for i in v.size():
		_push(xform * v[i], (nb * n[i]).normalized(), color)
	if idx != null and (idx as PackedInt32Array).size() > 0:
		for i in (idx as PackedInt32Array):
			_indices.append(base + i)
	else:
		for i in v.size():
			_indices.append(base + i)


static func _prim(key: String, maker: Callable) -> Array:
	if not _prim_cache.has(key):
		var m: Mesh = maker.call()
		_prim_cache[key] = m.surface_get_arrays(0)
	return _prim_cache[key]


static func _basis_from_y(axis: Vector3) -> Basis:
	var y := axis.normalized()
	var x := y.cross(Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.95 else Vector3.RIGHT).normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)


## Flat triangle (normal from winding).
func _tri(a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	var n := (c - a).cross(b - a).normalized()
	var base := _verts.size()
	_push(a, n, color); _push(b, n, color); _push(c, n, color)
	_indices.append(base); _indices.append(base + 1); _indices.append(base + 2)


## Flat triangle wound so that it faces away from `inside`.
func _tri_out(a: Vector3, b: Vector3, c: Vector3, color: Color, inside: Vector3) -> void:
	var n := (c - a).cross(b - a)
	if n.dot((a + b + c) / 3.0 - inside) < 0.0:
		_tri(a, c, b, color)
	else:
		_tri(a, b, c, color)


## Triangle with explicit vertex normals; winding is fixed up to agree with them.
func _tri_n(a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3, color: Color) -> void:
	var g := (c - a).cross(b - a)
	var base := _verts.size()
	if g.dot(na + nb + nc) < 0.0:
		_push(a, na, color); _push(c, nc, color); _push(b, nb, color)
	else:
		_push(a, na, color); _push(b, nb, color); _push(c, nc, color)
	_indices.append(base); _indices.append(base + 1); _indices.append(base + 2)


func _quad_n(a: Vector3, b: Vector3, c: Vector3, d: Vector3, na: Vector3, nb: Vector3, nc: Vector3, nd: Vector3, color: Color) -> void:
	_tri_n(a, b, c, na, nb, nc, color)
	_tri_n(a, c, d, na, nc, nd, color)


# ------------------------------------------------------------------ hard-surface primitives

## Bevelled box: flat faces with chamfered edges whose normals blend between the faces, the
## standard "manufactured part" look. `bevel` is in metres (clamped to the box).
func hbox(xform: Transform3D, size: Vector3, color: Color, bevel := 0.012) -> MeshKit:
	var h := size * 0.5
	var b := clampf(bevel, 0.0005, minf(h.x, minf(h.y, h.z)) * 0.9)
	var nb := xform.basis.inverse().transposed()
	var nx := (nb * Vector3.RIGHT).normalized()
	var ny := (nb * Vector3.UP).normalized()
	var nz := (nb * Vector3.BACK).normalized()
	# corner points: [sx][sy][sz] -> point on the X, Y and Z face
	var px := {}; var py := {}; var pz := {}
	for sx: int in [-1, 1]:
		for sy: int in [-1, 1]:
			for sz: int in [-1, 1]:
				var k := Vector3i(sx, sy, sz)
				px[k] = xform * Vector3(sx * h.x, sy * (h.y - b), sz * (h.z - b))
				py[k] = xform * Vector3(sx * (h.x - b), sy * h.y, sz * (h.z - b))
				pz[k] = xform * Vector3(sx * (h.x - b), sy * (h.y - b), sz * h.z)
	for s: int in [-1, 1]:
		var fx := nx * float(s); var fy := ny * float(s); var fz := nz * float(s)
		# faces
		_quad_n(px[Vector3i(s, -1, -1)], px[Vector3i(s, 1, -1)], px[Vector3i(s, 1, 1)], px[Vector3i(s, -1, 1)], fx, fx, fx, fx, color)
		_quad_n(py[Vector3i(-1, s, -1)], py[Vector3i(1, s, -1)], py[Vector3i(1, s, 1)], py[Vector3i(-1, s, 1)], fy, fy, fy, fy, color)
		_quad_n(pz[Vector3i(-1, -1, s)], pz[Vector3i(1, -1, s)], pz[Vector3i(1, 1, s)], pz[Vector3i(-1, 1, s)], fz, fz, fz, fz, color)
		for t: int in [-1, 1]:
			var gx := nx * float(s); var gy := ny * float(t); var gz := nz * float(t)
			# X-Y edges (s = x sign, t = y sign)
			_quad_n(px[Vector3i(s, t, -1)], px[Vector3i(s, t, 1)], py[Vector3i(s, t, 1)], py[Vector3i(s, t, -1)], gx, gx, gy, gy, color)
			# X-Z edges (s = x sign, t = z sign)
			_quad_n(px[Vector3i(s, -1, t)], px[Vector3i(s, 1, t)], pz[Vector3i(s, 1, t)], pz[Vector3i(s, -1, t)], gx, gx, gz, gz, color)
			# Y-Z edges (s = y sign, t = z sign)
			var hy := ny * float(s)
			_quad_n(py[Vector3i(-1, s, t)], py[Vector3i(1, s, t)], pz[Vector3i(1, s, t)], pz[Vector3i(-1, s, t)], hy, hy, gz, gz, color)
	for sx: int in [-1, 1]:
		for sy: int in [-1, 1]:
			for sz: int in [-1, 1]:
				var k := Vector3i(sx, sy, sz)
				_tri_n(px[k], py[k], pz[k], nx * float(sx), ny * float(sy), nz * float(sz), color)
	return self


## Shorthand: axis-aligned bevelled box at `center`.
func block(center: Vector3, size: Vector3, color: Color, bevel := 0.012, basis := Basis.IDENTITY) -> MeshKit:
	return hbox(Transform3D(basis, center), size, color, bevel)


## Extrudes a 2D outline (in the local XY plane) from z0 to z1. Flat shaded, hard edges.
## Good for blades, fins, brackets, plates and signs.
func prism(outline: PackedVector2Array, z0: float, z1: float, xform: Transform3D, color: Color) -> MeshKit:
	var n := outline.size()
	if n < 3:
		return self
	var area := 0.0
	for i in n:
		var p := outline[i]; var q := outline[(i + 1) % n]
		area += p.x * q.y - q.x * p.y
	var ccw := area > 0.0
	var nb := xform.basis.inverse().transposed()
	var tris := Geometry2D.triangulate_polygon(outline)
	var nz0 := (nb * (Vector3.FORWARD if z0 < z1 else Vector3.BACK)).normalized()
	for i in range(0, tris.size(), 3):
		var a := outline[tris[i]]; var b := outline[tris[i + 1]]; var c := outline[tris[i + 2]]
		_tri_n(xform * Vector3(a.x, a.y, z0), xform * Vector3(b.x, b.y, z0), xform * Vector3(c.x, c.y, z0), nz0, nz0, nz0, color)
		_tri_n(xform * Vector3(a.x, a.y, z1), xform * Vector3(b.x, b.y, z1), xform * Vector3(c.x, c.y, z1), -nz0, -nz0, -nz0, color)
	for i in n:
		var p := outline[i]; var q := outline[(i + 1) % n]
		var t := q - p
		var o := Vector2(t.y, -t.x) if ccw else Vector2(-t.y, t.x)
		var sn := (nb * Vector3(o.x, o.y, 0.0)).normalized()
		_quad_n(xform * Vector3(p.x, p.y, z0), xform * Vector3(q.x, q.y, z0), xform * Vector3(q.x, q.y, z1), xform * Vector3(p.x, p.y, z1), sn, sn, sn, sn, color)
	return self


## Revolves a profile of (radius, height) points around the local Y axis. List the profile
## from bottom to top for outward-facing walls. Smooth around the axis; each profile segment
## is a hard-edged band unless `smooth_profile` is set (domes, bulbs). `faceted` gives flat
## sides (hexagonal pads, nuts, basalt columns) instead of a round body.
func lathe(profile: PackedVector2Array, xform: Transform3D, color: Color, sides := 16, smooth_profile := false, faceted := false) -> MeshKit:
	var count := profile.size()
	if count < 2:
		return self
	var nb := xform.basis.inverse().transposed()
	var seg_n: Array[Vector2] = []
	for i in count - 1:
		var d := profile[i + 1] - profile[i]
		seg_n.append(Vector2(d.y, -d.x).normalized() if d.length() > 0.00001 else Vector2(1, 0))
	for i in count - 1:
		var p0 := profile[i]; var p1 := profile[i + 1]
		if p0.x < 0.00001 and p1.x < 0.00001:
			continue
		var n0 := seg_n[i]; var n1 := seg_n[i]
		if smooth_profile:
			if i > 0:
				n0 = (seg_n[i - 1] + seg_n[i]).normalized()
			if i < count - 2:
				n1 = (seg_n[i] + seg_n[i + 1]).normalized()
		for s in sides:
			var a0 := TAU * float(s) / float(sides)
			var a1 := TAU * float(s + 1) / float(sides)
			var c0 := Vector3(cos(a0), 0, sin(a0)); var c1 := Vector3(cos(a1), 0, sin(a1))
			var f0 := c0; var f1 := c1
			if faceted:
				f0 = Vector3(cos((a0 + a1) * 0.5), 0, sin((a0 + a1) * 0.5)); f1 = f0
			var v00 := xform * (c0 * p0.x + Vector3(0, p0.y, 0)); var v01 := xform * (c1 * p0.x + Vector3(0, p0.y, 0))
			var v10 := xform * (c0 * p1.x + Vector3(0, p1.y, 0)); var v11 := xform * (c1 * p1.x + Vector3(0, p1.y, 0))
			var m00 := (nb * (f0 * n0.x + Vector3(0, n0.y, 0))).normalized(); var m01 := (nb * (f1 * n0.x + Vector3(0, n0.y, 0))).normalized()
			var m10 := (nb * (f0 * n1.x + Vector3(0, n1.y, 0))).normalized(); var m11 := (nb * (f1 * n1.x + Vector3(0, n1.y, 0))).normalized()
			if p0.x < 0.00001:
				_tri_n(v00, v10, v11, m00, m10, m11, color)
			elif p1.x < 0.00001:
				_tri_n(v00, v10, v01, m00, m10, m01, color)
			else:
				_quad_n(v00, v10, v11, v01, m00, m10, m11, m01, color)
	return self


## Lathe between two points (profile heights are measured along a -> b in metres).
func turned(a: Vector3, b: Vector3, profile: PackedVector2Array, color: Color, sides := 16, smooth_profile := false, faceted := false) -> MeshKit:
	return lathe(profile, Transform3D(_basis_from_y(b - a), a), color, sides, smooth_profile, faceted)


## Flat ring / washer / disc lying in the local XZ plane (y = height of its top face).
func disc(xform: Transform3D, r_outer: float, r_inner: float, thickness: float, color: Color, sides := 20, faceted := false) -> MeshKit:
	var prof := PackedVector2Array([Vector2(r_outer, 0.0), Vector2(r_outer, thickness), Vector2(maxf(r_inner, 0.0), thickness)])
	if r_inner > 0.0:
		prof.append(Vector2(r_inner, 0.0))
	return lathe(prof, xform, color, sides, false, faceted)


## Cylinder / cone / tapered tube between two points.
func tube(a: Vector3, b: Vector3, radius_a: float, radius_b: float, color: Color, sides := 10, caps := true) -> MeshKit:
	var len := a.distance_to(b)
	if len < 0.0001:
		return self
	var ratio := radius_b / maxf(radius_a, 0.0001)
	var key := "cyl_%d_%d_%d" % [sides, int(caps), int(round(ratio * 1000.0))]
	var arr := _prim(key, func() -> Mesh:
		var m := CylinderMesh.new()
		m.bottom_radius = 1.0; m.top_radius = ratio; m.height = 1.0
		m.radial_segments = sides; m.rings = 1; m.cap_top = caps; m.cap_bottom = caps
		return m)
	var basis := _basis_from_y(b - a)
	basis = basis * Basis.from_scale(Vector3(radius_a, len, radius_a))
	_append(arr, Transform3D(basis, (a + b) * 0.5), color)
	return self


func cone(base: Vector3, tip: Vector3, radius: float, color: Color, sides := 10) -> MeshKit:
	return tube(base, tip, radius, 0.001, color, sides, true)


func capsule(a: Vector3, b: Vector3, radius: float, color: Color, sides := 10) -> MeshKit:
	tube(a, b, radius, radius, color, sides, false)
	sphere(a, radius, color, Vector3.ONE, sides, 5)
	sphere(b, radius, color, Vector3.ONE, sides, 5)
	return self


## Round pipe through a list of points (hoses, rails, handles). Joints are ball-capped.
func pipe(points: PackedVector3Array, radius: float, color: Color, sides := 8) -> MeshKit:
	for i in points.size() - 1:
		tube(points[i], points[i + 1], radius, radius, color, sides, i == 0 or i == points.size() - 2)
		if i > 0:
			sphere(points[i], radius, color, Vector3.ONE, sides, 4)
	return self


## A raised ridge wound around a (possibly tapering) shaft from a to b: drill flutes, threads.
func spiral(a: Vector3, b: Vector3, radius_a: float, radius_b: float, turns: float, width: float, height: float, color: Color, steps := 40, phase := 0.0) -> MeshKit:
	var basis := _basis_from_y(b - a)
	var len := a.distance_to(b)
	var prev: Array[Vector3] = []
	for i in steps + 1:
		var f := float(i) / float(steps)
		var ang := phase + TAU * turns * f
		var r := lerpf(radius_a, radius_b, f)
		var out := basis.x * cos(ang) + basis.z * sin(ang)
		var centre := a + basis.y * (len * f)
		var w := width * lerpf(1.0, maxf(radius_b / maxf(radius_a, 0.0001), 0.25), f)
		var lo := centre + out * r - basis.y * w * 0.5
		var hi := centre + out * r + basis.y * w * 0.5
		var top := centre + out * (r + height * lerpf(1.0, maxf(radius_b / maxf(radius_a, 0.0001), 0.3), f))
		if not prev.is_empty():
			var mid := (centre + a + basis.y * (len * float(i - 1) / float(steps))) * 0.5
			_tri_out(prev[0], lo, top, color, mid); _tri_out(prev[0], top, prev[2], color, mid)
			_tri_out(prev[1], prev[2], top, color, mid); _tri_out(prev[1], top, hi, color, mid)
		prev = [lo, hi, top]
	return self


## Louvred vent: a dark recess with evenly spaced slats. The panel lies in the local XY plane
## facing +Z; `size` is (width, height, depth).
func louvre(xform: Transform3D, size: Vector3, slats: int, frame_color: Color, slat_color: Color) -> MeshKit:
	hbox(xform, size, frame_color, minf(size.z * 0.4, 0.008))
	var inner_h := size.y * 0.8
	for i in slats:
		var y := -inner_h * 0.5 + inner_h * (float(i) + 0.5) / float(slats)
		var t := xform * Transform3D(Basis.from_euler(Vector3(deg_to_rad(-28.0), 0, 0)), Vector3(0, y, size.z * 0.5))
		hbox(t, Vector3(size.x * 0.86, inner_h / float(slats) * 0.5, size.z * 0.9), slat_color, 0.002)
	return self


func torus(xform: Transform3D, ring_radius: float, tube_radius: float, color: Color, segs := 16, sides := 8) -> MeshKit:
	var key := "torus_%d_%d_%d" % [segs, sides, int(round(tube_radius / ring_radius * 1000.0))]
	var ratio := tube_radius / ring_radius
	var arr := _prim(key, func() -> Mesh:
		var m := TorusMesh.new()
		m.inner_radius = 1.0 - ratio; m.outer_radius = 1.0 + ratio; m.rings = segs; m.ring_segments = sides
		return m)
	_append(arr, xform * Transform3D(Basis.from_scale(Vector3.ONE * ring_radius), Vector3.ZERO), color)
	return self


# ------------------------------------------------------------------ organic primitives

func sphere(pos: Vector3, radius: float, color: Color, scale := Vector3.ONE, segs := 12, rings := 7) -> MeshKit:
	var arr := _prim("sphere_%d_%d" % [segs, rings], func() -> Mesh:
		var m := SphereMesh.new(); m.radius = 1.0; m.height = 2.0; m.radial_segments = segs; m.rings = rings
		return m)
	_append(arr, Transform3D(Basis.from_scale(scale * radius), pos), color)
	return self


## Squashed/oriented ellipsoid.
func blob(xform: Transform3D, color: Color, segs := 12, rings := 7) -> MeshKit:
	var arr := _prim("sphere_%d_%d" % [segs, rings], func() -> Mesh:
		var m := SphereMesh.new(); m.radius = 1.0; m.height = 2.0; m.radial_segments = segs; m.rings = rings
		return m)
	_append(arr, xform, color)
	return self


## Rounded box (a superellipsoid) with smooth shading: soft organic blocks. For machined parts
## use hbox instead.
func rbox(xform: Transform3D, size: Vector3, color: Color, roundness := 0.35) -> MeshKit:
	var key := "rbox_%d" % int(roundness * 100.0)
	if not _prim_cache.has(key):
		_prim_cache[key] = _make_rbox(roundness)
	_append(_prim_cache[key], xform * Transform3D(Basis.from_scale(size * 0.5), Vector3.ZERO), color)
	return self


func box(center: Vector3, size: Vector3, color: Color, roundness := 0.35, basis := Basis.IDENTITY) -> MeshKit:
	return rbox(Transform3D(basis, center), size, color, roundness)


static func _make_rbox(roundness: float) -> Array:
	# Start from a sphere and push it towards a cube: p' = sign(p) * |p|^e  (e < 1 -> boxier)
	var m := SphereMesh.new()
	m.radius = 1.0; m.height = 2.0; m.radial_segments = 16; m.rings = 9
	var arr := m.surface_get_arrays(0)
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var e := clampf(roundness, 0.08, 1.0)
	for i in v.size():
		var p := v[i].normalized()
		var q := Vector3(signf(p.x) * pow(absf(p.x), e), signf(p.y) * pow(absf(p.y), e), signf(p.z) * pow(absf(p.z), e))
		var mx := maxf(absf(q.x), maxf(absf(q.y), absf(q.z)))
		v[i] = q / maxf(mx, 0.0001)
		var face := Vector3.ZERO
		var ax := absf(q.x); var ay := absf(q.y); var az := absf(q.z)
		if ax >= ay and ax >= az: face = Vector3(signf(q.x), 0, 0)
		elif ay >= az: face = Vector3(0, signf(q.y), 0)
		else: face = Vector3(0, 0, signf(q.z))
		n[i] = p.lerp(face, 1.0 - e).normalized()
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = n
	return arr


static func _ensure_ico() -> void:
	if not _ico_verts.is_empty():
		return
	var t := (1.0 + sqrt(5.0)) / 2.0
	var v: Array[Vector3] = [
		Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
		Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
		Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)]
	var f: Array[int] = [0, 11, 5, 0, 5, 1, 0, 1, 7, 0, 7, 10, 0, 10, 11, 1, 5, 9, 5, 11, 4, 11, 10, 2, 10, 7, 6, 7, 1, 8,
		3, 9, 4, 3, 4, 2, 3, 2, 6, 3, 6, 8, 3, 8, 9, 4, 9, 5, 2, 4, 11, 6, 2, 10, 8, 6, 7, 9, 8, 1]
	for i in v.size():
		v[i] = v[i].normalized()
	# one subdivision: 42 vertices, 80 faces
	var cache := {}
	var nf: Array[int] = []
	for i in range(0, f.size(), 3):
		var tri := [f[i], f[i + 1], f[i + 2]]
		var mids: Array[int] = []
		for e in 3:
			var a: int = tri[e]; var b: int = tri[(e + 1) % 3]
			var key := Vector2i(mini(a, b), maxi(a, b))
			if not cache.has(key):
				v.append(((v[a] + v[b]) * 0.5).normalized())
				cache[key] = v.size() - 1
			mids.append(cache[key])
		nf.append_array([tri[0], mids[0], mids[2], tri[1], mids[1], mids[0], tri[2], mids[2], mids[1], mids[0], mids[1], mids[2]])
	_ico_verts = PackedVector3Array(v)
	_ico_faces = PackedInt32Array(nf)


## Faceted boulder: a jittered, flat-shaded icosphere. Deterministic from `seed_value`.
func rock(xform: Transform3D, radius: float, color: Color, seed_value: int, jitter := 0.26, flat_base := true) -> MeshKit:
	_ensure_ico()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var pts := PackedVector3Array()
	for p in _ico_verts:
		var r := radius * (1.0 + rng.randf_range(-jitter, jitter))
		var q := p * r
		if flat_base and q.y < -radius * 0.35:
			q.y = -radius * 0.35      # sits on the ground instead of balancing on a point
		pts.append(xform * q)
	var centre := xform * Vector3.ZERO
	var up := xform.basis.y.normalized()
	for i in range(0, _ico_faces.size(), 3):
		var a := pts[_ico_faces[i]]; var b := pts[_ico_faces[i + 1]]; var c := pts[_ico_faces[i + 2]]
		var fn := (c - a).cross(b - a).normalized()
		if fn.dot((a + b + c) / 3.0 - centre) < 0.0:
			fn = -fn
		# top faces are a touch lighter (dust / bleaching), with a little per-face variation
		var shade := 0.93 + 0.1 * maxf(fn.dot(up), 0.0) + rng.randf_range(-0.03, 0.03)
		_tri_out(a, b, c, Color(color.r * shade, color.g * shade, color.b * shade), centre)
	return self


## Faceted crystal: a prism with a pointed tip, flat shaded.
func crystal(base: Vector3, tip: Vector3, radius: float, color: Color, sides := 6, shoulder_at := 0.72) -> MeshKit:
	var axis := tip - base
	var basis := _basis_from_y(axis)
	var shoulder := base + axis * shoulder_at
	var ring_a: Array[Vector3] = []
	var ring_b: Array[Vector3] = []
	for i in sides:
		var ang := TAU * float(i) / float(sides)
		var off := (basis.x * cos(ang) + basis.z * sin(ang)) * radius
		ring_a.append(base + off * 0.85)
		ring_b.append(shoulder + off)
	for i in sides:
		var j := (i + 1) % sides
		var shade := 0.86 + 0.14 * float(i % 3) / 2.0
		var c := Color(color.r * shade, color.g * shade, color.b * shade, 1.0)
		var mid := base + axis * 0.5
		_tri_out(ring_a[i], ring_b[i], ring_b[j], c, mid)
		_tri_out(ring_a[i], ring_b[j], ring_a[j], c, mid)
		_tri_out(ring_b[i], tip, ring_b[j], c.lightened(0.12), mid)
	return self


## Flat double-sided leaf / blade (two triangles per side), slightly bent.
func leaf(base: Vector3, tip: Vector3, width: float, color: Color, normal_hint := Vector3.UP) -> MeshKit:
	var axis := tip - base
	var side := axis.cross(normal_hint).normalized() * width * 0.5
	if side.length() < 0.0001:
		side = axis.cross(Vector3.RIGHT).normalized() * width * 0.5
	var mid := base.lerp(tip, 0.45) + normal_hint * axis.length() * 0.12
	_tri(base, mid + side, tip, color)
	_tri(base, tip, mid - side, color)
	_tri(base, tip, mid + side, color.darkened(0.1))
	_tri(base, mid - side, tip, color.darkened(0.1))
	return self


# ------------------------------------------------------------------ assembly

## Appends another kit's geometry with a transform.
func merge(other: MeshKit, xform := Transform3D.IDENTITY) -> MeshKit:
	var base := _verts.size()
	var nb := xform.basis.inverse().transposed()
	for i in other._verts.size():
		_verts.append(xform * other._verts[i])
		_normals.append((nb * other._normals[i]).normalized())
		_colors.append(other._colors[i])
		_uvs.append(other._uvs[i])
		_uv2s.append(other._uv2s[i])
	for i in other._indices:
		_indices.append(base + i)
	return self


func is_empty() -> bool:
	return _verts.is_empty()


func vertex_count() -> int:
	return _verts.size()


func commit() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	if _verts.is_empty():
		return mesh
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _verts
	arrays[Mesh.ARRAY_NORMAL] = _normals
	arrays[Mesh.ARRAY_COLOR] = _colors
	arrays[Mesh.ARRAY_TEX_UV] = _uvs
	arrays[Mesh.ARRAY_TEX_UV2] = _uv2s
	arrays[Mesh.ARRAY_INDEX] = _indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Convenience: commit into a MeshInstance3D using the shared prop material.
func instance(mat: Material = null, cast_shadow := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = commit()
	mi.material_override = mat if mat != null else material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi
