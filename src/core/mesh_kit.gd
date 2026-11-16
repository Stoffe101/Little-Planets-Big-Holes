class_name MeshKit
extends RefCounted
## Procedural modelling kit: combines chunky primitives into ONE vertex-coloured ArrayMesh.
## Every prop, tool, robot and machine in the game is modelled in code with this, so the
## whole world shares one material (res://shaders/prop.gdshader) and one visual language.
##
## Vertex data: COLOR = albedo, UV.x = emission amount, UV.y = sway weight.

const PROP_SHADER := preload("res://shaders/prop.gdshader")

var _verts := PackedVector3Array()
var _normals := PackedVector3Array()
var _colors := PackedColorArray()
var _uvs := PackedVector2Array()
var _indices := PackedInt32Array()

var emission := 0.0      ## applied to subsequently added parts
var sway := 0.0          ## applied to subsequently added parts (scaled by local height when sway_by_height)
var sway_by_height := true

static var _prim_cache: Dictionary = {}
static var _shared_material: ShaderMaterial
static var _sway_material: ShaderMaterial
static var _view_material: ShaderMaterial


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
	m.set_shader_parameter("rim_strength", 0.18)
	return m


static func new_material(emission_scale := 1.0, rim := 0.25) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = PROP_SHADER
	m.set_shader_parameter("emission_scale", emission_scale)
	m.set_shader_parameter("rim_strength", rim)
	return m


# ------------------------------------------------------------------ low level

func _append(arrays: Array, xform: Transform3D, color: Color) -> void:
	var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var n: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var idx: Variant = arrays[Mesh.ARRAY_INDEX]
	var base := _verts.size()
	var nb := xform.basis.inverse().transposed()
	var ymin := 0.0
	var ymax := 1.0
	if sway > 0.0 and sway_by_height:
		ymin = INF; ymax = -INF
		for p in v:
			var wp := xform * p
			ymin = minf(ymin, wp.y); ymax = maxf(ymax, wp.y)
	for i in v.size():
		var wp := xform * v[i]
		_verts.append(wp)
		_normals.append((nb * n[i]).normalized())
		_colors.append(color)
		var sw := sway
		if sway > 0.0 and sway_by_height:
			sw = sway * maxf(wp.y, 0.0)
		_uvs.append(Vector2(emission, sw))
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


# ------------------------------------------------------------------ primitives

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


## Cylinder / cone / tapered tube between two points.
func tube(a: Vector3, b: Vector3, radius_a: float, radius_b: float, color: Color, sides := 10, caps := true) -> MeshKit:
	var len := a.distance_to(b)
	if len < 0.0001:
		return self
	var key := "cyl_%d_%d_%d" % [sides, int(caps), int(round(radius_b / maxf(radius_a, 0.0001) * 100.0))]
	var ratio := radius_b / maxf(radius_a, 0.0001)
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


## Rounded box (a superellipsoid): reads as a chunky bevelled block with smooth shading.
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
		# normal of a superellipsoid: sign(p) * |p|^(2/e' - 1) with the implicit exponent 2/e... a
		# blend between sphere and face normal is plenty for a toy look.
		var face := Vector3.ZERO
		var ax := absf(q.x); var ay := absf(q.y); var az := absf(q.z)
		if ax >= ay and ax >= az: face = Vector3(signf(q.x), 0, 0)
		elif ay >= az: face = Vector3(0, signf(q.y), 0)
		else: face = Vector3(0, 0, signf(q.z))
		n[i] = p.lerp(face, 1.0 - e).normalized()
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = n
	return arr


func torus(xform: Transform3D, ring_radius: float, tube_radius: float, color: Color, segs := 16, sides := 8) -> MeshKit:
	var key := "torus_%d_%d_%d" % [segs, sides, int(round(tube_radius / ring_radius * 1000.0))]
	var ratio := tube_radius / ring_radius
	var arr := _prim(key, func() -> Mesh:
		var m := TorusMesh.new()
		m.inner_radius = 1.0 - ratio; m.outer_radius = 1.0 + ratio; m.rings = segs; m.ring_segments = sides
		return m)
	_append(arr, xform * Transform3D(Basis.from_scale(Vector3.ONE * ring_radius), Vector3.ZERO), color)
	return self


## Faceted crystal: a hexagonal prism with a pointed tip, flat shaded.
func crystal(base: Vector3, tip: Vector3, radius: float, color: Color, sides := 6) -> MeshKit:
	var axis := tip - base
	var basis := _basis_from_y(axis)
	var shoulder := base + axis * 0.72
	var ring_a: Array[Vector3] = []
	var ring_b: Array[Vector3] = []
	for i in sides:
		var ang := TAU * float(i) / float(sides)
		var off := (basis.x * cos(ang) + basis.z * sin(ang)) * radius
		ring_a.append(base + off * 0.85)
		ring_b.append(shoulder + off)
	for i in sides:
		var j := (i + 1) % sides
		var shade := 0.82 + 0.18 * float(i % 3) / 2.0
		var c := Color(color.r * shade, color.g * shade, color.b * shade, 1.0)
		var mid := base + axis * 0.5
		_tri_out(ring_a[i], ring_b[i], ring_b[j], c, mid)
		_tri_out(ring_a[i], ring_b[j], ring_a[j], c, mid)
		_tri_out(ring_b[i], tip, ring_b[j], c.lightened(0.18), mid)
	return self


## Adds a triangle wound so that it faces away from `inside`.
func _tri_out(a: Vector3, b: Vector3, c: Vector3, color: Color, inside: Vector3) -> void:
	var n := (c - a).cross(b - a)
	if n.dot((a + b + c) / 3.0 - inside) < 0.0:
		_tri(a, c, b, color)
	else:
		_tri(a, b, c, color)


func _tri(a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	var n := (c - a).cross(b - a).normalized()
	var base := _verts.size()
	for p: Vector3 in [a, b, c]:
		_verts.append(p)
		_normals.append(n)
		_colors.append(color)
		_uvs.append(Vector2(emission, sway * maxf(p.y, 0.0) if sway_by_height else sway))
	_indices.append(base); _indices.append(base + 1); _indices.append(base + 2)


## Flat double-sided leaf / petal / blade quad-fan (two triangles), slightly bent.
func leaf(base: Vector3, tip: Vector3, width: float, color: Color, normal_hint := Vector3.UP) -> MeshKit:
	var axis := tip - base
	var side := axis.cross(normal_hint).normalized() * width * 0.5
	if side.length() < 0.0001:
		side = axis.cross(Vector3.RIGHT).normalized() * width * 0.5
	var mid := base.lerp(tip, 0.45) + normal_hint * axis.length() * 0.12
	_tri(base, mid + side, tip, color)
	_tri(base, tip, mid - side, color)
	_tri(base, tip, mid + side, color.darkened(0.12))
	_tri(base, mid - side, tip, color.darkened(0.12))
	return self


func set_emission(e: float) -> MeshKit:
	emission = e
	return self


func set_sway(s: float) -> MeshKit:
	sway = s
	return self


## Appends another kit's geometry with a transform.
func merge(other: MeshKit, xform := Transform3D.IDENTITY) -> MeshKit:
	var base := _verts.size()
	var nb := xform.basis.inverse().transposed()
	for i in other._verts.size():
		_verts.append(xform * other._verts[i])
		_normals.append((nb * other._normals[i]).normalized())
		_colors.append(other._colors[i])
		_uvs.append(other._uvs[i])
	for i in other._indices:
		_indices.append(base + i)
	return self


func is_empty() -> bool:
	return _verts.is_empty()


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
