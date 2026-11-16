class_name PropField
extends Node3D
## Surface dressing: ground-cover tufts, low ferns, shrubs, a few slender trees, faceted
## boulders, pebbles, geological landmarks (standing stones / basalt columns, cairns at cave
## mouths) and harvestable crystal formations.
##
## Design rules (docs/ART_DIRECTION.md, "Environment"):
##   * Restraint: vegetation stays in the ground's own colour family; density follows the
##     planet's tint noise so there are open lawns, meadows and groves rather than even clutter.
##   * Landmarks are placed on purpose (mountain shoulders, cave mouths) so they mean something.
##   * Deterministic per item: every prop derives its random numbers from (seed, kind, index),
##     so digging one spot never reshuffles anything else and crystal flags stay valid.
## Placement respects existing holes, so a dug-up meadow stays dug up after reloading, and
## digging under a prop uproots it.

const CELL := 4.0

var world: World
var planet: Planet
var geo: Geology
var _multimeshes: Array[MultiMesh] = []
var _grid: Dictionary = {}          ## Vector3i cell -> Array of [mm_index, instance_index, pos, body]
var _rng := RandomNumberGenerator.new()
var _pending: Dictionary = {}       ## mm key -> {mesh, sway, shadow, xforms: Array[Transform3D]}
var prop_count := 0
var formation_count := 0
var landmark_count := 0
var _cfg: Dictionary = {}
var _foliage: Array[Color] = []
var _rocks: Array[Color] = []


func setup(w: World) -> void:
	world = w
	planet = w.planet
	geo = planet.geology
	_cfg = planet.config.get("props", {})
	for c: Variant in _cfg.get("foliage", ["#6f8f5a", "#5f8468", "#8f9a5e"]):
		_foliage.append(Color(str(c)))
	for c: Variant in _cfg.get("rock", ["#8d9097", "#978f86"]):
		_rocks.append(Color(str(c)))
	_scatter_tufts(int(_cfg.get("tuft", 0)))
	_scatter_ferns(int(_cfg.get("fern", 0)))
	_scatter_shrubs(int(_cfg.get("shrub", 0)))
	_scatter_trees(int(_cfg.get("tree", 0)))
	_scatter_boulders(int(_cfg.get("boulder", 0)))
	_scatter_pebbles(int(_cfg.get("pebble", 0)))
	_place_landmarks()
	_commit()
	_scatter_crystals(int(_cfg.get("crystal", 0)), _cfg.get("crystal_colors", []))


# ------------------------------------------------------------------ placement helpers

## Re-seeds the shared generator for one item. Everything about the item (direction, size,
## variant, rotation) must be drawn after this call and before the next one.
func _item(kind: int, index: int) -> void:
	_rng.seed = (geo.seed_value * 73856093) ^ (kind * 19349663) ^ (index * 83492791)


func _random_dir() -> Vector3:
	var z := _rng.randf_range(-1.0, 1.0)
	var a := _rng.randf() * TAU
	var r := sqrt(1.0 - z * z)
	return Vector3(r * cos(a), z, r * sin(a))


## Returns a surface transform for a direction, or null if the spot is unusable
## (already excavated, a cave mouth, too steep, or inside the launch pad).
func _site(dir: Vector3, pad_clearance: float, max_slope := 0.75, spin := 0.0) -> Variant:
	var ang := acos(clampf(dir.dot(geo.landing_dir), -1.0, 1.0))
	if ang * geo.radius < pad_clearance:
		return null
	var r := geo.surface_radius(dir)
	var p := dir * r
	# must still be the original ground: solid just below, air just above
	if planet.sdf_at(p - dir * 0.6) >= 0.0 or planet.sdf_at(p + dir * 0.7) < 0.0:
		return null
	# slope from the height field
	var t1 := dir.cross(Vector3(0.3, 1, 0.2)).normalized()
	var t2 := dir.cross(t1).normalized()
	var e := 0.03
	var h0 := geo.height_at(dir)
	var gx := (geo.height_at((dir + t1 * e).normalized()) - h0) / (e * geo.radius)
	var gz := (geo.height_at((dir + t2 * e).normalized()) - h0) / (e * geo.radius)
	if sqrt(gx * gx + gz * gz) > max_slope:
		return null
	var n := (dir - t1 * gx * 0.7 - t2 * gz * 0.7).normalized()
	var x := n.cross(Vector3(0.21, 0.34, 0.91)).normalized().rotated(n, spin)
	return Transform3D(Basis(x, n, x.cross(n).normalized()), p)


## Upright variant of a site transform (trees and standing stones follow gravity, not the slope).
func _upright(site: Transform3D, spin: float, sink := 0.12) -> Transform3D:
	var dir := site.origin.normalized()
	var x := dir.cross(Vector3(0.21, 0.34, 0.91)).normalized().rotated(dir, spin)
	return Transform3D(Basis(x, dir, x.cross(dir).normalized()), site.origin - dir * sink)


func _add(key: String, mesh: ArrayMesh, xf: Transform3D, scale: float, sway: bool, shadow: bool, body_radius := 0.0, body_height := 0.0) -> void:
	if not _pending.has(key):
		_pending[key] = {"mesh": mesh, "sway": sway, "shadow": shadow, "xforms": [], "bodies": []}
	var t := Transform3D(xf.basis.scaled(Vector3.ONE * scale), xf.origin)
	(_pending[key]["xforms"] as Array).append(t)
	var body: StaticBody3D = null
	if body_radius > 0.0:
		body = StaticBody3D.new()
		body.collision_layer = 4
		body.collision_mask = 0
		var shape := CapsuleShape3D.new()
		shape.radius = body_radius * scale
		shape.height = maxf(body_height * scale, shape.radius * 2.0)
		var col := CollisionShape3D.new()
		col.shape = shape
		col.position = Vector3(0, body_height * scale * 0.5, 0)
		body.add_child(col)
		add_child(body)
		body.global_transform = Transform3D(xf.basis, xf.origin)
	(_pending[key]["bodies"] as Array).append(body)
	prop_count += 1


func _commit() -> void:
	for key: String in _pending:
		var e: Dictionary = _pending[key]
		var xforms: Array = e["xforms"]
		if xforms.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = e["mesh"]
		mm.instance_count = xforms.size()
		var mm_index := _multimeshes.size()
		for i in xforms.size():
			var t: Transform3D = xforms[i]
			mm.set_instance_transform(i, t)
			var cell := Vector3i((t.origin / CELL).floor())
			if not _grid.has(cell):
				_grid[cell] = []
			(_grid[cell] as Array).append([mm_index, i, t.origin, (e["bodies"] as Array)[i]])
		_multimeshes.append(mm)
		var mmi := MultiMeshInstance3D.new()
		mmi.name = key
		mmi.multimesh = mm
		mmi.material_override = MeshKit.sway_material() if e["sway"] else MeshKit.material()
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if e["shadow"] else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.custom_aabb = AABB(Vector3.ONE * -(geo.max_surface_radius() + 12.0), Vector3.ONE * (geo.max_surface_radius() + 12.0) * 2.0)
		add_child(mmi)
	_pending.clear()


func _foliage_color(i: int) -> Color:
	return _foliage[i % _foliage.size()]


# ------------------------------------------------------------------ vegetation

## Thin ground-cover blades in the ground's own colours. Denser in meadows, absent on bare knolls.
func _scatter_tufts(count: int) -> void:
	if count <= 0:
		return
	var meshes: Array[ArrayMesh] = []
	for v in 3:
		var kit := MeshKit.new().matte()
		kit.sway = 0.22
		var base_col := _foliage_color(v).darkened(0.08)
		var blades := 5 + v
		for b in blades:
			var a := TAU * float(b) / float(blades) + float(v) * 0.7
			var lean := Vector3(cos(a), 0, sin(a))
			var h := 0.2 + 0.11 * float((b * 7 + v) % 4) / 3.0
			var c := base_col.lightened(0.1 * float(b % 3) / 2.0)
			kit.leaf(lean * 0.015, lean * (0.05 + 0.03 * float(b % 2)) + Vector3(0, h, 0), 0.022, c, lean)
		meshes.append(kit.commit())
	for i in count:
		_item(1, i)
		var dir := _random_dir()
		var scale := _rng.randf_range(0.8, 1.7)
		var spin := _rng.randf() * TAU
		var keep := _rng.randf()
		var tint := geo.tint_at(dir)
		# open lawns where tint.x is high, thicker cover in the damp low-tint zones
		if keep < smoothstep(0.42, 0.7, tint.x) * 0.85:
			continue
		var site: Variant = _site(dir, 2.5, 0.75, spin)
		if site == null:
			continue
		_add("tuft_%d" % (i % 3), meshes[i % 3], site, scale, true, false)


## Low rosettes of broad leaves; one variant carries a small muted bud (the only flower-like
## accent on the planet). They gather in meadow patches.
func _scatter_ferns(count: int) -> void:
	if count <= 0:
		return
	var accent := Color(str(_cfg.get("accent", "#c98a6a")))
	var meshes: Array[ArrayMesh] = []
	for v in 3:
		var kit := MeshKit.new().matte()
		kit.sway = 0.1
		var col := _foliage_color(v + 1).darkened(0.14)
		var leaves := 6 + v
		for l in leaves:
			var a := TAU * float(l) / float(leaves) + float(v)
			var out := Vector3(cos(a), 0, sin(a))
			var reach := 0.26 + 0.07 * float(l % 2)
			kit.leaf(out * 0.03 + Vector3(0, 0.02, 0), out * reach + Vector3(0, 0.1 + 0.05 * float(l % 3), 0), 0.11, col.lightened(0.07 * float(l % 2)), Vector3.UP)
		if v == 2:
			kit.sway = 0.14
			kit.tube(Vector3(0, 0.02, 0), Vector3(0.01, 0.3, 0.0), 0.008, 0.006, col.darkened(0.1), 4)
			kit.sphere(Vector3(0.01, 0.32, 0.0), 0.035, accent, Vector3(1, 1.25, 1), 6, 4)
		meshes.append(kit.commit())
	var placed := 0
	for i in count * 5:
		if placed >= count:
			break
		_item(2, i)
		var dir := _random_dir()
		var scale := _rng.randf_range(0.8, 1.5)
		var spin := _rng.randf() * TAU
		var v := _rng.randi() % meshes.size()
		if geo.tint_at(dir).y < 0.54:
			continue
		var site: Variant = _site(dir, 3.5, 0.6, spin)
		if site == null:
			continue
		_add("fern_%d" % v, meshes[v], site, scale, true, false)
		placed += 1


## Faceted low shrubs: two or three clipped foliage masses on a hidden stem.
func _scatter_shrubs(count: int) -> void:
	if count <= 0:
		return
	var meshes: Array[ArrayMesh] = []
	for v in 3:
		var kit := MeshKit.new().matte()
		var col := _foliage_color(v).darkened(0.2)
		kit.rock(Transform3D(Basis.from_scale(Vector3(1.0, 0.72, 1.0)), Vector3(0, 0.3, 0)), 0.4, col, 31 + v, 0.16, false)
		kit.rock(Transform3D(Basis.from_scale(Vector3(1.0, 0.7, 1.0)), Vector3(0.34, 0.2, 0.1)), 0.27, col.lightened(0.05), 47 + v, 0.16, false)
		if v > 0:
			kit.rock(Transform3D(Basis.from_scale(Vector3(1.0, 0.7, 1.0)), Vector3(-0.28, 0.18, -0.16)), 0.25, col.darkened(0.05), 59 + v, 0.16, false)
		meshes.append(kit.commit())
	for i in count:
		_item(3, i)
		var dir := _random_dir()
		var scale := _rng.randf_range(0.8, 1.6)
		var spin := _rng.randf() * TAU
		var v := _rng.randi() % meshes.size()
		if geo.tint_at(dir).x > 0.6:
			continue
		var site: Variant = _site(dir, 7.0, 0.6, spin)
		if site == null:
			continue
		_add("shrub_%d" % v, meshes[v], site, scale, false, true)


## Slender trees with flat, layered canopies. They stand in a few groves, never in rows.
func _scatter_trees(count: int) -> void:
	if count <= 0:
		return
	var canopy: Array = _cfg.get("tree_canopy", ["#5f8a6e", "#74935c"])
	var meshes: Array[ArrayMesh] = []
	for v in 4:
		var kit := MeshKit.new().matte()
		var col := Color(str(canopy[v % canopy.size()]))
		var tall := v >= 2
		var h := 3.6 if tall else 2.5
		var bend := Vector3(0.22 if v % 2 == 0 else -0.18, 0, 0.1)
		kit.tube(Vector3.ZERO, bend + Vector3(0, h * 0.55, 0), 0.11, 0.075, Pal.BARK, 7)
		kit.tube(bend + Vector3(0, h * 0.55, 0), bend * 0.4 + Vector3(0, h, 0), 0.075, 0.045, Pal.BARK.lightened(0.05), 7)
		kit.tube(bend * 0.9 + Vector3(0, h * 0.62, 0), bend * 0.9 + Vector3(0.55, h * 0.84, 0.25), 0.04, 0.025, Pal.BARK, 5)
		kit.sway = 0.01
		var top := bend * 0.4 + Vector3(0, h, 0)
		kit.rock(Transform3D(Basis.from_scale(Vector3(1.0, 0.3, 1.0)), top + Vector3(0, 0.1, 0)), 1.05, col, 11 + v, 0.14, false)
		kit.rock(Transform3D(Basis.from_scale(Vector3(1.0, 0.3, 1.0)), top + Vector3(0.25, 0.5, 0.1)), 0.7, col.lightened(0.06), 23 + v, 0.14, false)
		kit.rock(Transform3D(Basis.from_scale(Vector3(1.0, 0.32, 1.0)), bend * 0.9 + Vector3(0.62, h * 0.86, 0.28)), 0.52, col.darkened(0.05), 37 + v, 0.14, false)
		if tall:
			kit.rock(Transform3D(Basis.from_scale(Vector3(1.0, 0.32, 1.0)), top + Vector3(-0.2, 0.86, -0.1)), 0.42, col.lightened(0.1), 41 + v, 0.14, false)
		kit.sway = 0.0
		meshes.append(kit.commit())
	var placed := 0
	for i in count * 10:
		if placed >= count:
			break
		_item(4, i)
		var dir := _random_dir()
		var scale := _rng.randf_range(0.85, 1.3)
		var spin := _rng.randf() * TAU
		var v := _rng.randi() % meshes.size()
		if geo.tint_at(dir).x > 0.4:
			continue      # trees keep to the groves
		var site: Variant = _site(dir, 12.0, 0.45, spin)
		if site == null:
			continue
		_add("tree_%d" % v, meshes[v], _upright(site, spin), scale, true, true, 0.14, 2.6)
		placed += 1


# ------------------------------------------------------------------ rocks

func _rock_color(i: int) -> Color:
	return _rocks[i % _rocks.size()]


func _scatter_boulders(count: int) -> void:
	if count <= 0:
		return
	var meshes: Array[ArrayMesh] = []
	for v in 4:
		var kit := MeshKit.new().matte()
		var c := _rock_color(v)
		kit.rock(Transform3D(Basis.from_euler(Vector3(0.1, 0.5 * v, 0.05)) * Basis.from_scale(Vector3(1.15, 0.8, 0.95)), Vector3(0, 0.22, 0)), 0.55, c, 101 + v * 7, 0.24)
		if v % 2 == 1:
			kit.rock(Transform3D(Basis.from_euler(Vector3(0.2, 1.3, 0.1)), Vector3(0.52, 0.1, 0.2)), 0.28, c.darkened(0.05), 131 + v, 0.24)
		if v >= 2:
			kit.rock(Transform3D(Basis.from_euler(Vector3(0.0, 2.1, 0.15)), Vector3(-0.45, 0.08, -0.28)), 0.24, c.lightened(0.04), 151 + v, 0.24)
		meshes.append(kit.commit())
	for i in count:
		_item(5, i)
		var dir := _random_dir()
		var scale := _rng.randf_range(0.6, 2.0)
		var spin := _rng.randf() * TAU
		var v := _rng.randi() % meshes.size()
		var site: Variant = _site(dir, 9.0, 0.9, spin)
		if site == null:
			continue
		var xf: Transform3D = site
		xf.origin -= xf.basis.y * 0.08 * scale
		_add("boulder_%d" % v, meshes[v], xf, scale, false, true, 0.46, 0.5)


func _scatter_pebbles(count: int) -> void:
	if count <= 0:
		return
	var meshes: Array[ArrayMesh] = []
	for v in 2:
		var kit := MeshKit.new().matte()
		kit.rock(Transform3D(Basis.from_scale(Vector3(1.2, 0.7, 1.0)), Vector3(0, 0.03, 0)), 0.1, _rock_color(v), 201 + v, 0.22)
		kit.rock(Transform3D(Basis.from_scale(Vector3(1.0, 0.7, 1.1)), Vector3(0.2, 0.02, 0.09)), 0.065, _rock_color(v + 1).lightened(0.05), 211 + v, 0.22)
		if v == 1:
			kit.rock(Transform3D(Basis.from_scale(Vector3(1.1, 0.7, 0.9)), Vector3(-0.12, 0.015, -0.16)), 0.05, _rock_color(v).darkened(0.06), 223, 0.22)
		meshes.append(kit.commit())
	for i in count:
		_item(6, i)
		var dir := _random_dir()
		var scale := _rng.randf_range(0.7, 1.8)
		var spin := _rng.randf() * TAU
		var site: Variant = _site(dir, 2.0, 1.2, spin)
		if site == null:
			continue
		_add("pebble_%d" % (i % 2), meshes[i % 2], site, scale, false, false)


# ------------------------------------------------------------------ landmarks

## Purposeful geology: a ring of standing stones (or basalt columns) on each mountain's
## shoulder, and a cairn beside every natural cave mouth so entrances can be recognised and
## found again from a distance.
func _place_landmarks() -> void:
	var style := str(_cfg.get("landmark", "stones"))
	var idx := 0
	for m in geo.mountains:
		var top: Vector3 = m["dir"]
		var width := acos(clampf(float(m["cos_w"]), -1.0, 1.0))
		_item(7, idx)
		var bearing := _rng.randf() * TAU
		var t1 := top.cross(Vector3(0.3, 1, 0.2)).normalized()
		var around := t1.rotated(top, bearing)
		var dir := (top * cos(width * 0.55) + around * sin(width * 0.55)).normalized()
		_landmark_cluster(dir, style, idx)
		idx += 1
	for c in geo.cavities:
		var mouth: Vector3 = c["entrance"]
		if mouth == Vector3.ZERO:
			continue
		var cdir := mouth.normalized()
		var side := cdir.cross(c["dir"] as Vector3).normalized()
		for s: float in [-1.0, 1.0]:
			_item(8, idx)
			var dir2 := (cdir + side * s * (3.4 / geo.radius)).normalized()
			_cairn(dir2, idx)
			idx += 1


func _landmark_cluster(center_dir: Vector3, style: String, index: int) -> void:
	var t1 := center_dir.cross(Vector3(0.3, 1, 0.2)).normalized()
	var t2 := center_dir.cross(t1).normalized()
	var n := 5 if style == "stones" else 9
	for j in n:
		_item(9, index * 16 + j)
		var a := TAU * float(j) / float(n) + _rng.randf_range(-0.3, 0.3)
		var dist := (_rng.randf_range(1.6, 3.2) if style == "stones" else _rng.randf_range(0.4, 2.2)) / geo.radius
		var dir := (center_dir + (t1 * cos(a) + t2 * sin(a)) * dist).normalized()
		var spin := _rng.randf() * TAU
		var tall := _rng.randf_range(1.6, 3.4) if style == "stones" else _rng.randf_range(0.9, 3.6)
		var tilt := Vector3(_rng.randf_range(-0.12, 0.12), 0, _rng.randf_range(-0.12, 0.12))
		var seed_i := _rng.randi()
		var site: Variant = _site(dir, 14.0, 1.4, spin)
		if site == null:
			continue
		var kit := MeshKit.new().matte()
		var col := _rock_color(j)
		var girth := 0.0
		if style == "stones":
			girth = tall * 0.24
			kit.rock(Transform3D(Basis.from_euler(tilt) * Basis.from_scale(Vector3(1.0, tall / (girth * 2.0), 0.75)), Vector3(0, tall * 0.42, 0)), girth, col, seed_i, 0.2)
		else:
			# basalt column: a hexagonal prism with a slightly canted top
			girth = 0.42
			var prof := PackedVector2Array([Vector2(girth, -0.4), Vector2(girth, tall), Vector2(girth * 0.82, tall + 0.07), Vector2(0.0, tall + 0.1)])
			kit.lathe(prof, Transform3D(Basis.from_euler(tilt * 0.4), Vector3.ZERO), col.darkened(0.12), 6, false, true)
		var mi := kit.instance(MeshKit.material(), true)
		add_child(mi)
		mi.global_transform = _upright(site, spin, 0.3)
		var body := StaticBody3D.new()
		body.collision_layer = 4
		body.collision_mask = 0
		var shape := CapsuleShape3D.new()
		shape.radius = girth * 0.8
		shape.height = maxf(tall, shape.radius * 2.0)
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.position = Vector3(0, tall * 0.5, 0)
		body.add_child(cs)
		mi.add_child(body)
		landmark_count += 1


## Three stacked stones: the "someone was here" marker beside a cave mouth.
func _cairn(dir: Vector3, index: int) -> void:
	_item(10, index)
	var spin := _rng.randf() * TAU
	var site: Variant = _site(dir, 10.0, 1.6, spin)
	if site == null:
		return
	var kit := MeshKit.new().matte()
	var y := 0.0
	for k in 3:
		var r := 0.42 - 0.11 * float(k)
		kit.rock(Transform3D(Basis.from_euler(Vector3(0, _rng.randf() * TAU, 0)) * Basis.from_scale(Vector3(1.15, 0.62, 1.0)), Vector3(_rng.randf_range(-0.05, 0.05), y + r * 0.45, _rng.randf_range(-0.05, 0.05))), r, _rock_color(k + index), _rng.randi(), 0.18)
		y += r * 0.86
	var mi := kit.instance(MeshKit.material(), true)
	add_child(mi)
	mi.global_transform = _upright(site, spin, 0.05)
	landmark_count += 1


# ------------------------------------------------------------------ crystals

func _scatter_crystals(count: int, colors: Array) -> void:
	var mat_id := str(planet.config.get("surface_crystal", ""))
	if mat_id == "" or count <= 0:
		return
	var mat := GameData.mat_index(mat_id)
	for i in count:
		_item(11, i)
		var dir := _random_dir()
		var size := _rng.randf_range(0.6, 1.5)
		var seed_i := _rng.randi()
		var spin := _rng.randf() * TAU
		var site: Variant = _site(dir, 12.0, 1.1, spin)
		var key := "%s/crystal_%d" % [geo.id, i]
		if site == null or GameState.has_flag(key):
			continue
		var f := Formation.new()
		f.flag_key = key
		f.setup(mat, int(round(2.0 + size * 2.5)), size, colors, seed_i, false)
		add_child(f)
		f.global_transform = site
		formation_count += 1


# ------------------------------------------------------------------ digging interaction

## Uproots every prop whose base was inside the excavated sphere.
func on_dig(pos: Vector3, radius: float) -> void:
	var reach := radius + 0.4
	var lo := Vector3i(((pos - Vector3.ONE * reach) / CELL).floor())
	var hi := Vector3i(((pos + Vector3.ONE * reach) / CELL).floor())
	var removed := 0
	for cx in range(lo.x, hi.x + 1):
		for cy in range(lo.y, hi.y + 1):
			for cz in range(lo.z, hi.z + 1):
				var cell := Vector3i(cx, cy, cz)
				if not _grid.has(cell):
					continue
				var list: Array = _grid[cell]
				var i := list.size() - 1
				while i >= 0:
					var e: Array = list[i]
					if (e[2] as Vector3).distance_to(pos) < reach:
						_multimeshes[int(e[0])].set_instance_transform(int(e[1]), Transform3D(Basis.from_scale(Vector3.ZERO), e[2]))
						if e[3] != null and is_instance_valid(e[3]):
							(e[3] as Node).queue_free()
						list.remove_at(i)
						removed += 1
					i -= 1
	if removed > 0 and not _foliage.is_empty():
		world.fx.dig_burst(pos, planet.up_at(pos), _foliage[0].darkened(0.1), 0.4, false)
	for child in get_children():
		if child is Formation and (child as Formation).global_position.distance_to(pos) < radius:
			# ground dug away beneath a crystal: let it settle onto the new floor
			var f := child as Formation
			var up := planet.up_at(f.global_position)
			f.global_position = planet.ground_point(up, f.global_position.length() + 0.5)
