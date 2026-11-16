class_name SecretsManager
extends Node3D
## Everything hidden inside a planet: buried artifacts in sealed pockets, decorated caverns
## (crystal grottos, mushroom hollows, the vault) and the planet's Heart at the very centre.

var world: World
var planet: Planet
var geo: Geology
var artifacts: Array[Dictionary] = []      ## {id, node, pos}
var places: Array[Dictionary] = []         ## {id, center, radius}
var heart: Node3D
var heart_light: OmniLight3D
var _heart_mat: ShaderMaterial
var _check := 0.0
var _time := 0.0
var _core_id := ""
var formation_count := 0


func setup(w: World) -> void:
	world = w
	planet = w.planet
	geo = planet.geology
	for a in geo.artifacts:
		if GameState.has_discovery(a["id"]):
			continue
		_spawn_artifact(a)
	for c in geo.cavities:
		_decorate_cavity(c)
	_build_heart()


# ------------------------------------------------------------------ artifacts

func _spawn_artifact(a: Dictionary) -> void:
	var node := Node3D.new()
	node.name = "Artifact_" + str(a["id"])
	add_child(node)
	var pos: Vector3 = a["pos"]
	var up := planet.up_at(pos)
	var x := up.cross(Vector3(0.3, 0.2, 0.9)).normalized()
	node.global_transform = Transform3D(Basis(x, up, x.cross(up).normalized()), pos)
	var model := _artifact_model(str(a["model"]))
	model.name = "Model"
	node.add_child(model)
	var light := OmniLight3D.new()
	light.light_color = Color("#ffe9a0")
	light.light_energy = 0.8
	light.omni_range = 5.0
	light.position = Vector3(0, 0.5, 0)
	node.add_child(light)
	var body := StaticBody3D.new()
	body.collision_layer = 8
	body.collision_mask = 0
	var shape := SphereShape3D.new()
	shape.radius = 0.95
	var col := CollisionShape3D.new()
	col.shape = shape
	body.add_child(col)
	body.position = Vector3(0, 0.4, 0)
	var id := str(a["id"])
	body.set_meta("prompt", "Pick up the strange object")
	body.set_meta("action", func() -> void: collect(id))
	node.add_child(body)
	artifacts.append({"id": id, "node": node, "pos": pos})


func collect(id: String) -> void:
	for i in artifacts.size():
		if artifacts[i]["id"] == id:
			var node: Node3D = artifacts[i]["node"]
			var pos := node.global_position
			var up := planet.up_at(pos)
			world.fx.sparks(pos + up * 0.5, up, Color("#fff08a"), 30)
			world.fx.shock_ring(pos + up * 0.2, up, 3.0, Color("#fff08a"), 0.6)
			node.queue_free()
			artifacts.remove_at(i)
			world.discover(id)
			return


func _artifact_model(kind: String) -> Node3D:
	var kit := MeshKit.new()
	var gold := Color("#ffcf4a")
	var steel := Color("#b9c2dc")
	var ink := Color("#2a2540")
	match kind:
		"robot":
			kit.rbox(Transform3D(Basis.from_euler(Vector3(0.2, 0.4, 0.3)), Vector3(0, 0.38, 0)), Vector3(0.7, 0.55, 0.6), Color("#e8e2f7"), 0.5)
			kit.set_emission(1.4)
			kit.sphere(Vector3(0.1, 0.45, 0.3), 0.14, Color("#8ffcff"), Vector3(1, 1, 0.5), 10, 6)
			kit.set_emission(0.0)
			kit.sphere(Vector3(-0.42, 0.42, 0), 0.16, Color("#ff9438"), Vector3(0.6, 1, 1), 8, 5)
			kit.sphere(Vector3(0.42, 0.3, 0), 0.16, Color("#ff9438"), Vector3(0.6, 1, 1), 8, 5)
			kit.tube(Vector3(0, 0.64, 0), Vector3(0.1, 0.92, 0.05), 0.02, 0.02, steel, 5)
			kit.sphere(Vector3(0.1, 0.94, 0.05), 0.05, Color("#ff5d6c"), Vector3.ONE, 6, 4)
		"capsule":
			kit.capsule(Vector3(-0.25, 0.3, 0), Vector3(0.25, 0.3, 0), 0.24, steel, 12)
			kit.torus(Transform3D(Basis.from_euler(Vector3(0, 0, PI * 0.5)), Vector3(0, 0.3, 0)), 0.25, 0.04, gold, 14, 6)
			kit.torus(Transform3D(Basis.from_euler(Vector3(0, 0, PI * 0.5)), Vector3(0.22, 0.3, 0)), 0.245, 0.025, Color("#ff5d6c"), 14, 6)
		"chart":
			kit.rbox(Transform3D(Basis.from_euler(Vector3(-0.5, 0.3, 0.1)), Vector3(0, 0.45, 0)), Vector3(0.75, 0.04, 0.55), Color("#2c2a6e"), 0.3)
			kit.set_emission(2.0)
			for i in 7:
				var p := Vector3(-0.28 + 0.09 * i, 0.47 + 0.03 * sin(i * 1.7), -0.12 + 0.06 * cos(i * 2.3))
				kit.sphere(p, 0.025 + 0.01 * (i % 3), Color("#8ffcff") if i % 2 == 0 else Color("#fff08a"), Vector3.ONE, 6, 4)
			kit.set_emission(0.0)
			kit.tube(Vector3(-0.4, 0.2, 0.1), Vector3(-0.36, 0.7, -0.14), 0.035, 0.035, gold, 6)
		"drillbit":
			kit.cone(Vector3(0, 0.1, 0), Vector3(0.15, 1.0, 0.05), 0.24, Color("#8a7a9c"), 9)
			for r in 5:
				var f := float(r) / 5.0
				kit.torus(Transform3D(Basis.from_euler(Vector3(0.1, 0, 0.5)), Vector3(0.15 * f, 0.15 + 0.85 * f * 0.9, 0.05 * f)), 0.23 * (1.0 - f) + 0.02, 0.03, Color("#c9b8e0"), 10, 5)
			kit.set_emission(1.2)
			kit.sphere(Vector3(0.15, 1.0, 0.05), 0.05, Color("#ff7fb0"), Vector3.ONE, 6, 4)
			kit.set_emission(0.0)
		"seed":
			kit.sphere(Vector3(0, 0.55, 0), 0.55, Color("#c98f5a"), Vector3(0.8, 1.15, 0.8), 12, 8)
			for i in 5:
				var a := TAU * float(i) / 5.0
				kit.torus(Transform3D(Basis.from_euler(Vector3(0, a, PI * 0.5)), Vector3(0, 0.55, 0)), 0.5, 0.025, Color("#8a5a3a"), 14, 4)
			kit.set_emission(0.8)
			kit.leaf(Vector3(0, 1.15, 0), Vector3(0.22, 1.55, 0.05), 0.2, Color("#9be36b"), Vector3.UP)
			kit.set_emission(0.0)
		"helmet":
			kit.sphere(Vector3(0, 0.4, 0), 0.42, Color("#f6f0ff"), Vector3(1, 0.95, 1), 12, 8)
			kit.set_emission(0.5)
			kit.sphere(Vector3(0, 0.42, 0.2), 0.3, Color("#ffb347"), Vector3(1, 0.8, 0.7), 10, 6)
			kit.set_emission(0.0)
			kit.torus(Transform3D(Basis.IDENTITY, Vector3(0, 0.1, 0)), 0.36, 0.06, Color("#ff5d6c"), 14, 6)
			kit.tube(Vector3(0.3, 0.6, -0.1), Vector3(0.42, 0.95, -0.15), 0.02, 0.02, steel, 5)
		"idol":
			kit.set_emission(0.5)
			kit.rbox(Transform3D(Basis.IDENTITY, Vector3(0, 0.3, 0)), Vector3(0.4, 0.5, 0.3), gold, 0.5)
			kit.sphere(Vector3(0, 0.75, 0), 0.24, gold, Vector3.ONE, 10, 6)
			kit.set_emission(2.0)
			kit.sphere(Vector3(-0.09, 0.78, 0.2), 0.045, Color("#ff5d6c"), Vector3.ONE, 6, 4)
			kit.sphere(Vector3(0.09, 0.78, 0.2), 0.045, Color("#ff5d6c"), Vector3.ONE, 6, 4)
			kit.set_emission(0.5)
			kit.cone(Vector3(0, 0.95, 0), Vector3(0, 1.25, 0), 0.12, gold.lightened(0.2), 5)
			kit.set_emission(0.0)
			kit.rbox(Transform3D(Basis.IDENTITY, Vector3(0, 0.03, 0)), Vector3(0.6, 0.1, 0.5), ink, 0.4)
		"bell":
			kit.set_emission(0.5)
			kit.tube(Vector3(0, 0.15, 0), Vector3(0, 0.75, 0), 0.42, 0.2, Color("#9fe8ff"), 12, false)
			kit.sphere(Vector3(0, 0.75, 0), 0.2, Color("#9fe8ff"), Vector3.ONE, 10, 6)
			kit.torus(Transform3D(Basis.IDENTITY, Vector3(0, 0.15, 0)), 0.42, 0.045, Color("#ffffff"), 16, 6)
			kit.set_emission(1.5)
			kit.sphere(Vector3(0, 0.18, 0), 0.09, Color("#ff9df5"), Vector3.ONE, 8, 5)
			kit.set_emission(0.0)
		"lens":
			kit.torus(Transform3D(Basis.from_euler(Vector3(PI * 0.5, 0.3, 0)), Vector3(0, 0.55, 0)), 0.38, 0.06, gold, 18, 6)
			kit.set_emission(1.3)
			kit.sphere(Vector3(0, 0.55, 0), 0.36, Color("#c9f5ff"), Vector3(1, 1, 0.22), 12, 7)
			kit.set_emission(0.0)
			kit.tube(Vector3(0, 0, 0), Vector3(0, 0.2, 0), 0.05, 0.04, gold, 6)
		"bird":
			kit.set_emission(0.8)
			kit.sphere(Vector3(0, 0.35, 0), 0.22, Color("#a8f3ff"), Vector3(1, 0.9, 1.3), 8, 5)
			kit.sphere(Vector3(0, 0.55, 0.2), 0.14, Color("#d6fbff"), Vector3.ONE, 8, 5)
			kit.cone(Vector3(0, 0.55, 0.32), Vector3(0, 0.53, 0.46), 0.04, Color("#ffd23f"), 5)
			kit.crystal(Vector3(0, 0.35, -0.2), Vector3(0, 0.5, -0.55), 0.09, Color("#ff9df5"), 4)
			kit.set_emission(0.0)
		_:
			kit.sphere(Vector3(0, 0.4, 0), 0.35, gold, Vector3.ONE, 10, 6)
	return kit.instance(MeshKit.material(), false)


# ------------------------------------------------------------------ caverns

func _decorate_cavity(c: Dictionary) -> void:
	var cfg: Dictionary = c["cfg"]
	var center: Vector3 = c["center"]
	var radius: float = c["radius"]
	var decor := str(cfg.get("decor", ""))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(c["id"])) * 3 + geo.seed_value
	if cfg.has("discovery"):
		places.append({"id": str(cfg["discovery"]), "center": center, "radius": radius})
	var up: Vector3 = c["dir"]
	var light := OmniLight3D.new()
	light.omni_range = radius * 2.4
	light.omni_attenuation = 1.2
	light.light_energy = 0.9
	add_child(light)
	light.global_position = center + up * radius * 0.2
	match decor:
		"crystals":
			light.light_color = GameData.material(str(planet.config.get("bonus_gem", "amethyst")))["color_c"]
			_cavity_crystals(c, rng, 13)
		"mushrooms":
			light.light_color = Color("#8ff0c0")
			_cavity_mushrooms(c, rng, 22)
		"vault":
			light.light_color = Color("#ffcf6a")
			_cavity_vault(c)


## Marches from the cavern centre along `dir` until it hits rock. Returns the wall point or null.
func _wall(center: Vector3, dir: Vector3, max_dist: float) -> Variant:
	var d := 0.5
	while d < max_dist:
		if planet.sdf_at(center + dir * d) < 0.0:
			return center + dir * (d - 0.3)
		d += 0.4
	return null


func _cavity_crystals(c: Dictionary, rng: RandomNumberGenerator, count: int) -> void:
	var center: Vector3 = c["center"]
	var radius: float = c["radius"]
	var gem := GameData.mat_index(str(planet.config.get("bonus_gem", "amethyst")))
	var common := GameData.mat_index(str(planet.config.get("surface_crystal", "pipquartz")))
	var colors: Array = (planet.config.get("props", {}) as Dictionary).get("crystal_colors", [])
	for i in count:
		var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized()
		var size := rng.randf_range(1.1, 2.9)
		var seed_i := rng.randi()
		var rich := rng.randf() < 0.6
		var key := "%s/cav_%s_%d" % [geo.id, c["id"], i]
		var wall: Variant = _wall(center, dir, radius * 1.9)
		if wall == null or GameState.has_flag(key):
			continue
		var f := Formation.new()
		f.flag_key = key
		var mat := gem if rich else common
		f.setup(mat, int(round(2.0 + size * 2.2)), size, [] if rich else colors, seed_i, i % 4 == 0)
		add_child(f)
		var n := -dir
		var x := n.cross(Vector3(0.3, 0.8, 0.5)).normalized()
		f.global_transform = Transform3D(Basis(x, n, x.cross(n).normalized()), wall)
		formation_count += 1


func _cavity_mushrooms(c: Dictionary, rng: RandomNumberGenerator, count: int) -> void:
	var center: Vector3 = c["center"]
	var radius: float = c["radius"]
	var down: Vector3 = -(c["dir"] as Vector3)
	var kit := MeshKit.new()
	var placed := 0
	for i in count * 2:
		if placed >= count:
			break
		var dir := (down + Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * 0.9).normalized()
		var wall: Variant = _wall(center, dir, radius * 1.8)
		if wall == null:
			continue
		var p: Vector3 = wall
		var n := -dir
		var x := n.cross(Vector3(0.3, 0.8, 0.5)).normalized()
		var xf := Transform3D(Basis(x, n, x.cross(n).normalized()), p - n * 0.25)
		var s := rng.randf_range(0.7, 2.6)
		var col: Color = [Color("#7dffd0"), Color("#9d8cff"), Color("#ff9df5")][rng.randi() % 3]
		var sub := MeshKit.new()
		sub.tube(Vector3.ZERO, Vector3(0, 0.45, 0) * s, 0.07 * s, 0.05 * s, Color("#f3ecff"), 7)
		sub.emission = 1.1
		sub.sphere(Vector3(0, 0.45, 0) * s, 0.24 * s, col, Vector3(1, 0.55, 1), 9, 5)
		kit.merge(sub, xf)
		placed += 1
	var mi := kit.instance(MeshKit.material(), false)
	add_child(mi)


func _cavity_vault(c: Dictionary) -> void:
	var center: Vector3 = c["center"]
	var radius: float = c["radius"]
	var up: Vector3 = c["dir"]
	var x := up.cross(Vector3(0.3, 0.2, 0.9)).normalized()
	var floor_p: Vector3 = center - up * (radius - 1.4)
	var node := Node3D.new()
	add_child(node)
	node.global_transform = Transform3D(Basis(x, up, x.cross(up).normalized()), floor_p)
	var kit := MeshKit.new()
	var stone := Color("#7a6fa6")
	kit.tube(Vector3(0, -0.3, 0), Vector3(0, 0.1, 0), 3.2, 3.0, stone.darkened(0.2), 20)
	kit.tube(Vector3(0, 0.1, 0), Vector3(0, 0.45, 0), 0.9, 0.75, stone, 10)
	for i in 6:
		var a := TAU * float(i) / 6.0
		var p := Vector3(cos(a), 0, sin(a)) * 2.6
		kit.tube(p, p + Vector3(0, 3.0, 0), 0.26, 0.2, stone, 8)
		kit.rbox(Transform3D(Basis.IDENTITY, p + Vector3(0, 3.05, 0)), Vector3(0.7, 0.25, 0.7), stone.lightened(0.1), 0.4)
		kit.set_emission(1.6)
		kit.sphere(p + Vector3(0, 3.4, 0), 0.14, Color("#ffcf6a"), Vector3.ONE, 8, 5)
		kit.set_emission(0.0)
	node.add_child(kit.instance(MeshKit.material(), false))


# ------------------------------------------------------------------ heart

func _build_heart() -> void:
	var core: Dictionary = planet.config.get("core", {})
	_core_id = str(core.get("discovery", ""))
	if _core_id == "":
		return
	var c1 := Color(str(core.get("color", "#ffe36b")))
	var c2 := Color(str(core.get("color2", "#ff8fb8")))
	heart = Node3D.new()
	heart.name = "Heart"
	add_child(heart)
	var kit := MeshKit.new()
	kit.emission = 1.6
	kit.sphere(Vector3.ZERO, 1.0, c1, Vector3(0.85, 1.1, 0.85), 16, 10)
	kit.emission = 2.4
	for i in 6:
		var a := TAU * float(i) / 6.0
		kit.torus(Transform3D(Basis.from_euler(Vector3(0, a, PI * 0.5)), Vector3.ZERO), 1.02, 0.035, c2, 20, 5)
	kit.leaf(Vector3(0, 1.05, 0), Vector3(0.45, 1.75, 0.1), 0.4, Color("#9be36b"), Vector3.UP)
	kit.leaf(Vector3(0, 1.05, 0), Vector3(-0.35, 1.55, -0.1), 0.3, Color("#7fdc5a"), Vector3.UP)
	_heart_mat = MeshKit.new_material(1.0, 0.4)
	heart.add_child(kit.instance(_heart_mat, false))
	# orbiting motes
	var motes := MeshKit.new()
	motes.emission = 3.0
	for i in 10:
		var a := TAU * float(i) / 10.0
		motes.sphere(Vector3(cos(a) * 2.1, sin(a * 3.0) * 0.6, sin(a) * 2.1), 0.07, c2 if i % 2 == 0 else c1, Vector3.ONE, 6, 4)
	var mote_node := motes.instance(MeshKit.material(), false)
	mote_node.name = "Motes"
	heart.add_child(mote_node)
	heart_light = OmniLight3D.new()
	heart_light.light_color = c1
	heart_light.light_energy = 2.5
	heart_light.omni_range = geo.core_radius * 3.0
	heart.add_child(heart_light)
	var body := StaticBody3D.new()
	body.collision_layer = 8 | 4
	body.collision_mask = 0
	var shape := SphereShape3D.new()
	shape.radius = 1.25
	var col := CollisionShape3D.new()
	col.shape = shape
	body.add_child(col)
	body.set_meta("prompt", "Touch the Heart")
	body.set_meta("action", func() -> void: touch_heart())
	heart.add_child(body)


func touch_heart() -> void:
	if _core_id == "" or GameState.has_discovery(_core_id):
		Audio.play("heart", -6.0)
		return
	Audio.play("heart", 2.0)
	for i in 4:
		world.fx.shock_ring(Vector3.ZERO, [Vector3.UP, Vector3.RIGHT, Vector3.FORWARD, Vector3(1, 1, 0).normalized()][i], geo.core_radius * (1.2 + 0.4 * i), Color("#fff3b0"), 0.9 + 0.2 * i)
	world.fx.sparks(Vector3.ZERO, world.player.up, Color("#fff08a"), 40)
	world.player.add_trauma(0.6)
	var tw := create_tween()
	tw.tween_property(world, "bloom", 1.0, 3.5)
	world.discover(_core_id)


# ------------------------------------------------------------------ runtime

func _process(delta: float) -> void:
	_time += delta
	for a in artifacts:
		var model := (a["node"] as Node3D).get_node_or_null("Model") as Node3D
		if model != null:
			model.rotation.y = _time * 0.8
			model.position.y = 0.15 + sin(_time * 1.7) * 0.07
	if heart != null:
		var found := GameState.has_discovery(_core_id)
		var beat := 0.5 + 0.5 * sin(_time * (2.4 if found else 1.3))
		beat = beat * beat
		heart.scale = Vector3.ONE * (1.0 + beat * 0.07)
		heart.rotation.y = _time * 0.25
		heart_light.light_energy = (3.4 if found else 2.0) + beat * 1.6
		var motes := heart.get_node_or_null("Motes") as Node3D
		if motes != null:
			motes.rotation = Vector3(_time * 0.3, _time * 0.9, 0)
	_check -= delta
	if _check <= 0.0 and world != null and world.player != null:
		_check = 0.3
		var p := world.player.global_position
		for pl in places:
			if not GameState.has_discovery(pl["id"]) and p.distance_to(pl["center"]) < float(pl["radius"]) * 0.9:
				world.discover(pl["id"])


func on_dig(_pos: Vector3, _radius: float) -> void:
	pass


## Undiscovered secrets for the scanner: [{pos: Vector3, kind: "artifact"|"place"|"core"}].
func scan_targets() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for a in artifacts:
		out.append({"pos": a["pos"], "kind": "artifact"})
	for pl in places:
		if not GameState.has_discovery(pl["id"]):
			out.append({"pos": pl["center"], "kind": "place"})
	if _core_id != "" and not GameState.has_discovery(_core_id):
		out.append({"pos": Vector3.ZERO, "kind": "core"})
	return out
