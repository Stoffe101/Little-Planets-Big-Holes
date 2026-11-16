class_name PropField
extends Node3D
## Scatters the planet's surface decoration: grass tufts, flowers, mushrooms, bushes,
## cotton-candy trees, boulders and pebbles (MultiMesh instanced), plus harvestable crystal
## formations. Placement is deterministic from the planet seed and respects existing holes,
## so a dug-up meadow stays dug up after reloading. Digging under a prop uproots it.

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


func setup(w: World) -> void:
	world = w
	planet = w.planet
	geo = planet.geology
	_rng.seed = geo.seed_value * 131 + 7
	var cfg: Dictionary = planet.config.get("props", {})
	var pal: Dictionary = planet.config.get("palette", {})
	var grass_cols: Array = pal.get("grass", ["#7fdc5a"])
	_scatter_grass(int(cfg.get("grass_tuft", 0)), grass_cols)
	_scatter_flowers(int(cfg.get("flower", 0)), cfg.get("flower_colors", ["#ff7fb0"]))
	_scatter_mushrooms(int(cfg.get("mushroom", 0)), cfg.get("mushroom_colors", ["#ff5d73"]))
	_scatter_bushes(int(cfg.get("bush", 0)), grass_cols)
	_scatter_trees(int(cfg.get("tree", 0)), cfg.get("tree_colors", ["#ff8fb8"]))
	_scatter_rocks(int(cfg.get("rock", 0)))
	_scatter_pebbles(int(cfg.get("pebble", 0)))
	_commit()
	_scatter_crystals(int(cfg.get("crystal", 0)), cfg.get("crystal_colors", []))


# ------------------------------------------------------------------ placement helpers

func _random_dir() -> Vector3:
	var z := _rng.randf_range(-1.0, 1.0)
	var a := _rng.randf() * TAU
	var r := sqrt(1.0 - z * z)
	return Vector3(r * cos(a), z, r * sin(a))


## Returns a surface transform for a direction, or null if the spot is unusable
## (already excavated, a cave mouth, too steep, or inside the launch pad).
func _site(dir: Vector3, pad_clearance: float, max_slope := 0.75) -> Variant:
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
	var x := n.cross(Vector3(0.21, 0.34, 0.91)).normalized().rotated(n, _rng.randf() * TAU)
	return Transform3D(Basis(x, n, x.cross(n).normalized()), p)


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


# ------------------------------------------------------------------ prop types

func _scatter_grass(count: int, colors: Array) -> void:
	var meshes: Array[ArrayMesh] = []
	for v in 3:
		var kit := MeshKit.new()
		kit.sway = 0.3
		var base_col := Color(str(colors[v % colors.size()])).darkened(0.12)
		base_col.s = minf(1.0, base_col.s * 1.15)
		for b in 6:
			var a := TAU * float(b) / 6.0 + v
			var lean := Vector3(cos(a), 0, sin(a))
			var h := 0.16 + 0.09 * float((b + v) % 3)
			kit.leaf(lean * 0.02, lean * 0.09 + Vector3(0, h, 0), 0.035, base_col.lightened(0.12 * float(b % 2)), lean)
		meshes.append(kit.commit())
	for i in count:
		var dir := _random_dir()
		var site: Variant = _site(dir, 2.5)
		if site == null:
			continue
		var tint := geo.tint_at(dir)
		if tint.x > 0.72 and _rng.randf() < 0.6:
			continue
		_add("grass_%d" % (i % 3), meshes[i % 3], site, _rng.randf_range(0.8, 1.6), true, false)


func _scatter_flowers(count: int, colors: Array) -> void:
	var meshes: Array[ArrayMesh] = []
	for v in colors.size():
		var kit := MeshKit.new()
		kit.sway = 0.2
		var col := Color(str(colors[v]))
		kit.tube(Vector3.ZERO, Vector3(0.02, 0.34, 0), 0.014, 0.011, Color("#4cae5a"), 5)
		kit.leaf(Vector3(0, 0.08, 0), Vector3(0.13, 0.16, 0.02), 0.07, Color("#5cc468"), Vector3.UP)
		for p in 5:
			var a := TAU * float(p) / 5.0
			kit.sphere(Vector3(0.02 + cos(a) * 0.065, 0.36, sin(a) * 0.065), 0.05, col, Vector3(1, 0.45, 1), 6, 4)
		kit.sphere(Vector3(0.02, 0.375, 0), 0.04, Color("#ffe36b") if col != Color("#ffe36b") else Color("#ff9d5c"), Vector3(1, 0.7, 1), 6, 4)
		meshes.append(kit.commit())
	var placed := 0
	var tries := 0
	while placed < count and tries < count * 6:
		tries += 1
		var dir := _random_dir()
		if geo.tint_at(dir).y < 0.5:
			continue      # flowers gather in meadow patches
		var site: Variant = _site(dir, 3.0)
		if site == null:
			continue
		var v := _rng.randi() % meshes.size()
		_add("flower_%d" % v, meshes[v], site, _rng.randf_range(0.9, 1.6), true, false)
		placed += 1


func _scatter_mushrooms(count: int, colors: Array) -> void:
	var meshes: Array[ArrayMesh] = []
	for v in colors.size():
		var kit := MeshKit.new()
		var col := Color(str(colors[v]))
		kit.tube(Vector3.ZERO, Vector3(0, 0.3, 0), 0.075, 0.055, Color("#fff3df"), 8)
		kit.sphere(Vector3(0, 0.3, 0), 0.2, col, Vector3(1, 0.62, 1), 10, 6)
		for s in 5:
			var a := TAU * float(s) / 5.0 + 0.4
			kit.sphere(Vector3(cos(a) * 0.12, 0.37, sin(a) * 0.12), 0.035, Color("#fff8ec"), Vector3(1, 0.5, 1), 5, 3)
		# a little buddy mushroom
		kit.tube(Vector3(0.2, 0, 0.08), Vector3(0.2, 0.14, 0.08), 0.04, 0.03, Color("#fff3df"), 6)
		kit.sphere(Vector3(0.2, 0.14, 0.08), 0.1, col.lightened(0.15), Vector3(1, 0.62, 1), 8, 5)
		meshes.append(kit.commit())
	for i in count * 2:
		var dir := _random_dir()
		if geo.tint_at(dir).x > 0.5:
			continue
		var site: Variant = _site(dir, 5.0)
		if site == null:
			continue
		var v := _rng.randi() % meshes.size()
		_add("mushroom_%d" % v, meshes[v], site, _rng.randf_range(0.8, 2.4), false, true)


func _scatter_bushes(count: int, colors: Array) -> void:
	var meshes: Array[ArrayMesh] = []
	for v in 2:
		var kit := MeshKit.new()
		var col := Color(str(colors[v % colors.size()])).darkened(0.18)
		kit.sphere(Vector3(0, 0.3, 0), 0.42, col, Vector3(1, 0.8, 1), 9, 6)
		kit.sphere(Vector3(0.35, 0.22, 0.1), 0.3, col.lightened(0.08), Vector3(1, 0.8, 1), 8, 5)
		kit.sphere(Vector3(-0.3, 0.2, -0.15), 0.28, col.darkened(0.06), Vector3(1, 0.8, 1), 8, 5)
		kit.sphere(Vector3(0.05, 0.25, 0.36), 0.26, col.lightened(0.04), Vector3(1, 0.8, 1), 8, 5)
		var berry := Color("#ff5d73") if v == 0 else Color("#ffe36b")
		for b in 6:
			var a := TAU * float(b) / 6.0
			kit.sphere(Vector3(cos(a) * 0.36, 0.38 + 0.1 * sin(a * 2.0), sin(a) * 0.34), 0.05, berry, Vector3.ONE, 5, 3)
		meshes.append(kit.commit())
	for i in count:
		var site: Variant = _site(_random_dir(), 6.0, 0.6)
		if site == null:
			continue
		_add("bush_%d" % (i % 2), meshes[i % 2], site, _rng.randf_range(0.8, 1.5), false, true)


func _scatter_trees(count: int, colors: Array) -> void:
	if count <= 0:
		return
	var meshes: Array[ArrayMesh] = []
	for v in colors.size() * 2:
		var kit := MeshKit.new()
		var col := Color(str(colors[v % colors.size()]))
		var tall := v >= colors.size()
		var trunk := Color("#8a5a3a")
		var h := 2.6 if tall else 1.7
		kit.tube(Vector3.ZERO, Vector3(0.1, h * 0.55, 0.0), 0.2, 0.15, trunk, 8)
		kit.tube(Vector3(0.1, h * 0.55, 0.0), Vector3(0.0, h, 0.05), 0.15, 0.1, trunk.lightened(0.06), 8)
		kit.sphere(Vector3(0, 0.05, 0), 0.26, trunk.darkened(0.1), Vector3(1.2, 0.5, 1.2), 8, 4)
		kit.sway = 0.012
		if tall:
			kit.sphere(Vector3(0.0, h + 0.5, 0.05), 0.85, col, Vector3(1, 1.15, 1), 10, 7)
			kit.sphere(Vector3(0.1, h + 1.4, 0.0), 0.6, col.lightened(0.1), Vector3(1, 1.1, 1), 9, 6)
			kit.sphere(Vector3(0.0, h + 2.05, 0.0), 0.36, col.lightened(0.2), Vector3.ONE, 8, 5)
		else:
			kit.sphere(Vector3(0.0, h + 0.55, 0.05), 1.05, col, Vector3(1, 0.85, 1), 11, 7)
			kit.sphere(Vector3(0.75, h + 0.35, 0.2), 0.65, col.darkened(0.07), Vector3(1, 0.85, 1), 9, 6)
			kit.sphere(Vector3(-0.65, h + 0.45, -0.3), 0.7, col.lightened(0.08), Vector3(1, 0.85, 1), 9, 6)
			kit.sphere(Vector3(0.1, h + 1.15, -0.1), 0.6, col.lightened(0.15), Vector3(1, 0.85, 1), 9, 6)
		kit.sway = 0.0
		meshes.append(kit.commit())
	var placed := 0
	var tries := 0
	while placed < count and tries < count * 8:
		tries += 1
		var dir := _random_dir()
		if geo.tint_at(dir).x > 0.56:
			continue      # trees grow in groves
		var site: Variant = _site(dir, 11.0, 0.5)
		if site == null:
			continue
		var v := _rng.randi() % meshes.size()
		# keep trunks upright (planet up) rather than tilted with the slope
		var xf: Transform3D = site
		var x := dir.cross(Vector3(0.21, 0.34, 0.91)).normalized().rotated(dir, _rng.randf() * TAU)
		xf = Transform3D(Basis(x, dir, x.cross(dir).normalized()), xf.origin - dir * 0.15)
		_add("tree_%d" % v, meshes[v], xf, _rng.randf_range(0.85, 1.35), true, true, 0.22, 2.2)
		placed += 1


func _scatter_rocks(count: int) -> void:
	var meshes: Array[ArrayMesh] = []
	var cols := [Color("#9aa3bd"), Color("#8790ad"), Color("#b0a8c8")]
	for v in 3:
		var kit := MeshKit.new()
		var c: Color = cols[v]
		kit.rbox(Transform3D(Basis.from_euler(Vector3(0.2, 0.4 * v, 0.1)), Vector3(0, 0.25, 0)), Vector3(1.0, 0.75, 0.85), c, 0.5)
		kit.rbox(Transform3D(Basis.from_euler(Vector3(0.5, 1.0, 0.3)), Vector3(0.45, 0.16, 0.2)), Vector3(0.55, 0.45, 0.5), c.darkened(0.08), 0.5)
		if v > 0:
			kit.rbox(Transform3D(Basis.from_euler(Vector3(0.1, 2.0, 0.4)), Vector3(-0.4, 0.14, -0.25)), Vector3(0.5, 0.4, 0.45), c.lightened(0.06), 0.55)
		if v == 2:
			kit.rbox(Transform3D(Basis.from_euler(Vector3(0.3, 0.2, 0.2)), Vector3(0.05, 0.75, 0.0)), Vector3(0.6, 0.5, 0.55), c.lightened(0.1), 0.5)
		meshes.append(kit.commit())
	for i in count:
		var site: Variant = _site(_random_dir(), 9.0, 0.9)
		if site == null:
			continue
		var s := _rng.randf_range(0.6, 2.2)
		_add("rock_%d" % (i % 3), meshes[i % 3], site, s, false, true, 0.42, 0.6)


func _scatter_pebbles(count: int) -> void:
	var kit := MeshKit.new()
	kit.rbox(Transform3D(Basis.from_euler(Vector3(0.3, 0.2, 0.1)), Vector3(0, 0.03, 0)), Vector3(0.2, 0.12, 0.16), Color("#a9b0c8"), 0.6)
	kit.rbox(Transform3D(Basis.from_euler(Vector3(0.1, 1.2, 0.3)), Vector3(0.2, 0.02, 0.1)), Vector3(0.12, 0.08, 0.1), Color("#c4bcd8"), 0.6)
	var mesh := kit.commit()
	for i in count:
		var site: Variant = _site(_random_dir(), 2.0, 1.2)
		if site == null:
			continue
		_add("pebble", mesh, site, _rng.randf_range(0.7, 1.8), false, false)


func _scatter_crystals(count: int, colors: Array) -> void:
	var mat_id := str(planet.config.get("surface_crystal", ""))
	if mat_id == "" or count <= 0:
		return
	var mat := GameData.mat_index(mat_id)
	for i in count:
		# Always consume the same random numbers so indices stay stable between sessions.
		var dir := _random_dir()
		var size := _rng.randf_range(0.7, 1.9)
		var seed_i := _rng.randi()
		var site: Variant = _site(dir, 12.0, 1.1)
		var key := "%s/formation_%d" % [geo.id, i]
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
	if removed > 0:
		world.fx.dig_burst(pos, planet.up_at(pos), Color("#7fdc5a"), 0.5, false)
	for child in get_children():
		if child is Formation and (child as Formation).global_position.distance_to(pos) < radius:
			# ground dug away beneath a crystal: let it settle onto the new floor
			var f := child as Formation
			var up := planet.up_at(f.global_position)
			f.global_position = planet.ground_point(up, f.global_position.length() + 0.5)
