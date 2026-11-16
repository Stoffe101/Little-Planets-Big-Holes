class_name SecretsManager
extends Node3D
## Everything hidden inside a planet: buried artifacts in sealed pockets, dressed caverns
## (crystal grottos, a glow-cap hollow, the vault) and the planet's Heart at the very centre.
##
## Presentation rules (docs/ART_DIRECTION.md, "Discoveries"): a find is staged, not announced.
## Each artifact sits in a small scene that says how it got there (a cairn, a dropped tool, a
## half-buried shell) under one warm work-light; places have a composed focal point; the Heart
## is the single object in the game that is allowed to truly glow.

var world: World
var planet: Planet
var geo: Geology
var artifacts: Array[Dictionary] = []      ## {id, node, pos}
var places: Array[Dictionary] = []         ## {id, center, radius}
var heart: Node3D
var heart_light: OmniLight3D
var _heart_mat: ShaderMaterial
var _heart_rings: Array[Node3D] = []
var _heart_spin := 0.0
var _heart_awake := 0.0
var _check := 0.0
var _time := 0.0
var _core_id := ""
var formation_count := 0
var _undecorated: Array[Dictionary] = []   ## cavities waiting for their terrain to stream in
const DECORATE_RANGE := 70.0               ## metres from the cavern edge where dressing is built


func setup(w: World) -> void:
	world = w
	planet = w.planet
	geo = planet.geology
	for a in geo.artifacts:
		if GameState.has_discovery(a["id"]):
			continue
		_spawn_artifact(a)
	for c in geo.cavities:
		var cfg: Dictionary = c["cfg"]
		if cfg.has("discovery"):
			places.append({"id": str(cfg["discovery"]), "center": c["center"], "radius": c["radius"]})
		_undecorated.append(c)
	_build_heart()
	_decorate_ready()


## Cavern dressing needs the real cavern walls, which only exist where the terrain is loaded at
## full resolution. Each cavern is dressed once, the first time the player comes near enough.
func _decorate_ready() -> void:
	var p := world.player.global_position if world != null and world.player != null else geo.spawn_position()
	for i in range(_undecorated.size() - 1, -1, -1):
		var c := _undecorated[i]
		var center: Vector3 = c["center"]
		var r: float = c["radius"]
		if p.distance_to(center) > r + DECORATE_RANGE:
			continue
		if not planet.is_area_ready(center, r * 1.6):
			continue
		_undecorated.remove_at(i)
		_decorate_cavity(c)


func decorated_count() -> int:
	return geo.cavities.size() - _undecorated.size()


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
	node.add_child(_artifact_setting(str(a["model"]), hash(str(a["id"]))))
	var light := OmniLight3D.new()
	light.light_color = Pal.LAMP_WARM
	light.light_energy = 0.7
	light.omni_range = 4.5
	light.omni_attenuation = 1.3
	light.position = Vector3(0, 0.9, 0)
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
	body.set_meta("prompt", "Recover the object")
	body.set_meta("action", func() -> void: collect(id))
	node.add_child(body)
	artifacts.append({"id": id, "node": node, "pos": pos})


func collect(id: String) -> void:
	for i in artifacts.size():
		if artifacts[i]["id"] == id:
			var node: Node3D = artifacts[i]["node"]
			var pos := node.global_position
			var up := planet.up_at(pos)
			world.fx.sparks(pos + up * 0.5, up, Pal.LAMP_WARM, 10)
			world.fx.shock_ring(pos + up * 0.2, up, 2.4, Pal.TEAL, 0.6)
			node.queue_free()
			artifacts.remove_at(i)
			world.discover(id)
			return


## The little scene around an artifact: a rough stone plinth plus one or two props that hint
## at who left it. Static - only the artifact itself moves.
func _artifact_setting(kind: String, seed_value: int) -> Node3D:
	var kit := MeshKit.new().matte()
	kit.rock(Transform3D(Basis.from_scale(Vector3(1.3, 0.34, 1.2)), Vector3(0, -0.04, 0)), 0.55, Pal.ROCK_DARK, seed_value, 0.16)
	match kind:
		"robot", "helmet", "capsule", "probe":
			# an expedition marker: a short survey stake with an amber tag
			kit.bare()
			kit.tube(Vector3(0.62, -0.1, -0.3), Vector3(0.66, 0.7, -0.32), 0.014, 0.012, Pal.STEEL_DARK, 6)
			kit.paint()
			kit.hbox(Transform3D(Basis.from_euler(Vector3(0, 0.5, 0.05)), Vector3(0.72, 0.6, -0.33)), Vector3(0.16, 0.1, 0.008), Pal.AMBER, 0.002)
		"drillbit", "idol", "chart":
			# old work: two cut stone blocks, one toppled
			kit.matte()
			kit.hbox(Transform3D(Basis.from_euler(Vector3(0, 0.4, 0)), Vector3(-0.72, 0.1, 0.2)), Vector3(0.34, 0.3, 0.3), Pal.ROCK_WARM, 0.02)
			kit.hbox(Transform3D(Basis.from_euler(Vector3(0.9, 1.1, 0.2)), Vector3(-0.5, 0.06, 0.62)), Vector3(0.3, 0.26, 0.26), Pal.ROCK_WARM.darkened(0.08), 0.02)
		_:
			kit.rock(Transform3D(Basis.IDENTITY, Vector3(0.6, 0.0, 0.3)), 0.16, Pal.ROCK, seed_value + 3, 0.2)
			kit.rock(Transform3D(Basis.IDENTITY, Vector3(-0.55, 0.0, -0.4)), 0.12, Pal.ROCK_WARM, seed_value + 4, 0.2)
	return kit.instance(MeshKit.material(), false)


func _artifact_model(kind: String) -> Node3D:
	var kit := MeshKit.new()
	match kind:
		"robot":
			# a dormant helper bot, dusty, canted over, one eye faintly alive
			var tilt := Basis.from_euler(Vector3(0.25, 0.4, 0.35))
			kit.paint()
			kit.hbox(Transform3D(tilt, Vector3(0, 0.42, 0)), Vector3(0.62, 0.4, 0.54), Pal.HULL_SHADE.darkened(0.1), 0.12)
			kit.hbox(Transform3D(tilt, Vector3(0, 0.42, 0)), Vector3(0.63, 0.06, 0.55), Pal.AMBER_DARK, 0.02)
			kit.cast()
			kit.hbox(Transform3D(tilt, tilt * Vector3(0, -0.2, 0) + Vector3(0, 0.42, 0)), Vector3(0.44, 0.1, 0.4), Pal.GRAPHITE, 0.04)
			kit.surf(0.25).set_emission(0.9)
			kit.hbox(Transform3D(tilt, tilt * Vector3(0.0, 0.05, 0.275) + Vector3(0, 0.42, 0)), Vector3(0.3, 0.07, 0.02), Pal.TEAL, 0.008)
			kit.set_emission(0.0)
		"capsule":
			kit.bare()
			kit.turned(Vector3(-0.3, 0.3, 0), Vector3(0.3, 0.3, 0), PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.14, 0.02), Vector2(0.2, 0.1), Vector2(0.2, 0.5), Vector2(0.14, 0.58), Vector2(0.0, 0.6)]), Pal.STEEL, 14, true)
			kit.surf(0.4, 0.7)
			for z: float in [0.12, 0.3, 0.48]:
				kit.turned(Vector3(-0.3 + z, 0.3, 0), Vector3(-0.3 + z + 0.03, 0.3, 0), PackedVector2Array([Vector2(0.205, 0.0), Vector2(0.205, 0.03)]), Pal.BRASS, 14)
			kit.paint()
			kit.block(Vector3(0.0, 0.5, 0.0), Vector3(0.08, 0.04, 0.1), Pal.AMBER, 0.01)
		"chart":
			# half of a star chart: a dark slate tablet with inlaid points of light
			var cb := Basis.from_euler(Vector3(-0.9, 0.3, 0.0))
			kit.surf(0.35, 0.3)
			kit.prism(PackedVector2Array([Vector2(-0.34, -0.24), Vector2(0.3, -0.24), Vector2(0.36, -0.05), Vector2(0.24, 0.06), Vector2(0.3, 0.24), Vector2(-0.34, 0.24)]), -0.02, 0.02,
				Transform3D(cb, Vector3(0, 0.5, 0)), Pal.GLASS_DARK.darkened(0.3))
			kit.surf(0.3).set_emission(1.6)
			for i in 9:
				var p := Vector3(-0.26 + 0.065 * i, -0.14 + 0.25 * absf(sin(i * 1.9)), 0.022)
				kit.hbox(Transform3D(cb, cb * p + Vector3(0, 0.5, 0)), Vector3(0.016, 0.016, 0.004) * (1.0 + 0.5 * float(i % 3)), Pal.TEAL if i % 3 != 0 else Pal.LAMP_WARM, 0.002)
			kit.set_emission(0.5)
			kit.hbox(Transform3D(cb, cb * Vector3(-0.04, 0.0, 0.022) + Vector3(0, 0.5, 0)), Vector3(0.5, 0.004, 0.003), Pal.TEAL_DARK, 0.001)
			kit.set_emission(0.0)
			kit.surf(0.4, 0.7)
			kit.tube(Vector3(-0.2, 0.0, -0.12), Vector3(-0.12, 0.42, -0.2), 0.016, 0.016, Pal.BRASS, 6)
			kit.tube(Vector3(0.2, 0.0, -0.12), Vector3(0.12, 0.42, -0.2), 0.016, 0.016, Pal.BRASS, 6)
		"drillbit":
			# an ancient boring bit, far too large for any tool you own
			kit.cast()
			kit.turned(Vector3(0, 0.05, 0), Vector3(0.18, 1.1, 0.06), PackedVector2Array([Vector2(0.2, 0.0), Vector2(0.2, 0.14), Vector2(0.14, 0.2), Vector2(0.12, 0.7), Vector2(0.0, 1.07)]), Pal.STEEL_DARK.darkened(0.15), 10)
			kit.surf(0.4, 0.7)
			for k in 2:
				kit.spiral(Vector3(0.03, 0.26, 0.01), Vector3(0.175, 1.08, 0.058), 0.14, 0.012, 2.4, 0.07, 0.07, Pal.BRASS, 46, PI * float(k))
			_bolt_ring(kit, Vector3(0, 0.12, 0), 0.2, 6)
		"seed":
			kit.matte()
			kit.lathe(PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.3, 0.08), Vector2(0.46, 0.4), Vector2(0.4, 0.82), Vector2(0.16, 1.14), Vector2(0.0, 1.22)]), Transform3D(Basis.from_euler(Vector3(0.12, 0, 0.1)), Vector3.ZERO), Color("#7d5f45"), 12, true)
			for i in 6:
				var a := TAU * float(i) / 6.0
				kit.pipe(PackedVector3Array([Vector3(cos(a), 0, sin(a)) * 0.3 + Vector3(0, 0.1, 0), Vector3(cos(a), 0, sin(a)) * 0.47 + Vector3(0.03, 0.45, 0.0),
					Vector3(cos(a), 0, sin(a)) * 0.4 + Vector3(0.08, 0.84, 0.0), Vector3(0.13, 1.2, 0.0)]), 0.014, Color("#5d4634"), 5)
			kit.set_emission(0.25)
			kit.leaf(Vector3(0.14, 1.2, 0), Vector3(0.34, 1.56, 0.05), 0.18, Color("#7d9a5e"), Vector3.UP)
			kit.set_emission(0.0)
		"helmet":
			kit.paint()
			kit.lathe(PackedVector2Array([Vector2(0.3, 0.0), Vector2(0.36, 0.1), Vector2(0.36, 0.34), Vector2(0.26, 0.58), Vector2(0.0, 0.68)]), Transform3D(Basis.from_euler(Vector3(0.0, 0.0, 0.3)), Vector3(0, 0.04, 0)), Pal.HULL, 16, true)
			kit.cast()
			kit.lathe(PackedVector2Array([Vector2(0.31, 0.0), Vector2(0.38, 0.0), Vector2(0.38, 0.07), Vector2(0.31, 0.07)]), Transform3D(Basis.from_euler(Vector3(0.0, 0.0, 0.3)), Vector3(0, 0.02, 0)), Pal.GRAPHITE, 16)
			kit.gloss().set_emission(0.2)
			kit.sphere(Basis.from_euler(Vector3(0.0, 0.0, 0.3)) * Vector3(0, 0.34, 0.2) + Vector3(0, 0.04, 0), 0.25, Pal.AMBER_DARK, Vector3(1, 0.8, 0.7), 12, 7)
			kit.set_emission(0.0)
		"idol":
			kit.matte()
			kit.block(Vector3(0, 0.08, 0), Vector3(0.5, 0.16, 0.42), Pal.ROCK_DARK, 0.03)
			kit.surf(0.34, 0.75).set_emission(0.12)
			kit.lathe(PackedVector2Array([Vector2(0.17, 0.16), Vector2(0.2, 0.3), Vector2(0.12, 0.56), Vector2(0.15, 0.62), Vector2(0.17, 0.78), Vector2(0.1, 0.94), Vector2(0.0, 0.98)]), Transform3D.IDENTITY, Pal.BRASS, 8, false, true)
			kit.surf(0.25).set_emission(1.2)
			kit.block(Vector3(0, 0.76, 0.16), Vector3(0.12, 0.025, 0.02), Pal.TEAL, 0.004)
			kit.set_emission(0.0)
		"bell":
			kit.gloss().set_emission(0.25)
			kit.lathe(PackedVector2Array([Vector2(0.38, 0.12), Vector2(0.34, 0.2), Vector2(0.26, 0.5), Vector2(0.16, 0.74), Vector2(0.0, 0.8)]), Transform3D.IDENTITY, Color("#8fd6d0"), 8, false, true)
			kit.set_emission(0.0)
			kit.surf(0.4, 0.7)
			kit.torus(Transform3D(Basis.from_euler(Vector3(0, 0, PI * 0.5)), Vector3(0, 0.86, 0)), 0.07, 0.016, Pal.BRASS, 12, 5)
			kit.sphere(Vector3(0, 0.16, 0), 0.06, Pal.BRASS, Vector3.ONE, 8, 5)
		"lens":
			kit.surf(0.4, 0.7)
			kit.tube(Vector3(0, 0, 0), Vector3(0, 0.26, 0), 0.03, 0.022, Pal.BRASS, 8)
			kit.disc(Transform3D(Basis.IDENTITY, Vector3(0, 0.0, 0)), 0.14, 0.0, 0.03, Pal.BRASS, 8, true)
			kit.torus(Transform3D(Basis.from_euler(Vector3(PI * 0.5, 0.35, 0)), Vector3(0, 0.6, 0)), 0.34, 0.035, Pal.BRASS, 22, 6)
			kit.gloss().set_emission(0.3)
			kit.blob(Transform3D(Basis.from_euler(Vector3(0, 0.35, 0)) * Basis.from_scale(Vector3(0.32, 0.32, 0.05)), Vector3(0, 0.6, 0)), Color("#bfe8ee"), 14, 7)
			kit.set_emission(0.0)
		"bird":
			kit.gloss().set_emission(0.3)
			kit.crystal(Vector3(0, 0.3, -0.24), Vector3(0, 0.4, 0.26), 0.16, Color("#9fe0d8"), 5, 0.5)
			kit.crystal(Vector3(0, 0.42, 0.14), Vector3(0, 0.66, 0.34), 0.09, Color("#c5efe9"), 5, 0.5)
			kit.crystal(Vector3(0, 0.36, -0.14), Vector3(0.0, 0.52, -0.6), 0.06, Color("#d9799f"), 4, 0.3)
			for sx: float in [-1.0, 1.0]:
				kit.crystal(Vector3(0.08 * sx, 0.36, 0.0), Vector3(0.44 * sx, 0.5, -0.2), 0.05, Color("#9fe0d8"), 4, 0.3)
			kit.set_emission(0.0)
			kit.surf(0.4, 0.7)
			kit.tube(Vector3(0, 0, 0), Vector3(0, 0.28, 0), 0.012, 0.012, Pal.BRASS, 5)
		"probe":
			# a survey penetrator from an earlier expedition: a finned dart driven into the ground,
			# its sample core still clipped to the side
			var tilt := Basis.from_euler(Vector3(0.18, 0.0, -0.22))
			kit.cast()
			kit.turned(tilt * Vector3(0, -0.1, 0), tilt * Vector3(0, 0.95, 0), PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.09, 0.12), Vector2(0.11, 0.3), Vector2(0.11, 0.8), Vector2(0.08, 0.92), Vector2(0.0, 1.0)]), Pal.STEEL_DARK, 12, true)
			kit.bare()
			for k in 3:
				var fin := tilt * Basis.from_euler(Vector3(0, TAU * float(k) / 3.0, 0))
				kit.hbox(Transform3D(fin, tilt * Vector3(0, 0.78, 0) + fin * Vector3(0.15, 0, 0)), Vector3(0.12, 0.24, 0.014), Pal.STEEL, 0.004)
			kit.gloss()
			kit.tube(tilt * Vector3(0.1, 0.25, 0.04), tilt * Vector3(0.1, 0.62, 0.04), 0.032, 0.032, Pal.ROCK_WARM.darkened(0.15), 8)
			kit.surf(0.3).set_emission(0.9)
			kit.block(tilt * Vector3(0.0, 0.7, 0.105), Vector3(0.05, 0.05, 0.01), Pal.TEAL, 0.003, tilt)
			kit.set_emission(0.0)
		_:
			kit.surf(0.34, 0.75)
			kit.rock(Transform3D.IDENTITY.translated(Vector3(0, 0.4, 0)), 0.3, Pal.BRASS, 3, 0.1, false)
	return kit.instance(MeshKit.material(), false)


static func _bolt_ring(kit: MeshKit, center: Vector3, radius: float, count: int) -> void:
	kit.bare()
	for i in count:
		var a := TAU * float(i) / float(count)
		var p := center + Vector3(cos(a), 0, sin(a)) * radius
		kit.tube(p, p + Vector3(cos(a), 0, sin(a)) * 0.012, 0.014, 0.014, Pal.STEEL, 6)


# ------------------------------------------------------------------ caverns

func _decorate_cavity(c: Dictionary) -> void:
	var cfg: Dictionary = c["cfg"]
	var center: Vector3 = c["center"]
	var radius: float = c["radius"]
	var decor := str(cfg.get("decor", ""))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(c["id"])) * 3 + geo.seed_value
	var up: Vector3 = c["dir"]
	# One soft key light per cavern, high and off-centre, so the space has a lit side and a
	# shaded side instead of a flat wash.
	var light := OmniLight3D.new()
	light.omni_range = radius * 2.6
	light.omni_attenuation = 1.1
	light.light_energy = 0.9
	light.shadow_enabled = false
	add_child(light)
	var side := up.cross(Vector3(0.4, 0.2, 0.9)).normalized()
	light.global_position = center + up * radius * 0.35 + side * radius * 0.3
	match decor:
		"crystals":
			var gem: Color = GameData.material(str(planet.config.get("bonus_gem", "amethyst")))["color2_c"]
			light.light_color = Pal.LAMP_COOL.lerp(gem, 0.35)
			_cavity_crystals(c, rng, 12)
		"mushrooms":
			light.light_color = Color("#bfe6d8")
			light.light_energy = 0.6
			_cavity_glowcaps(c, rng, 26)
		"vault":
			light.light_color = Pal.LAMP_WARM
			_cavity_vault(c)
		"workings":
			light.light_color = Pal.LAMP_WARM
			light.light_energy = 0.55
			_cavity_workings(c, rng)


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
		# a few hero clusters, the rest modest: composition instead of a wall of spikes
		var size := rng.randf_range(0.8, 1.5) if i % 4 != 0 else rng.randf_range(1.7, 2.3)
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


## Small pale glow-caps on slender stems, in drifts on the cavern floor and lower walls.
func _cavity_glowcaps(c: Dictionary, rng: RandomNumberGenerator, count: int) -> void:
	var center: Vector3 = c["center"]
	var radius: float = c["radius"]
	var down: Vector3 = -(c["dir"] as Vector3)
	var kit := MeshKit.new()
	var cap := Color("#a9dccd")
	var placed := 0
	for i in count * 2:
		if placed >= count:
			break
		var dir := (down + Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * 0.8).normalized()
		var wall: Variant = _wall(center, dir, radius * 1.8)
		if wall == null:
			continue
		var p: Vector3 = wall
		var n := -dir
		var x := n.cross(Vector3(0.3, 0.8, 0.5)).normalized()
		var xf := Transform3D(Basis(x, n, x.cross(n).normalized()), p - n * 0.2)
		var sub := MeshKit.new()
		# a drift: one tall cap with two or three smaller ones around it
		for k in 2 + rng.randi() % 3:
			var s := rng.randf_range(0.5, 1.0) if k > 0 else rng.randf_range(1.0, 1.7)
			var off := Vector3(rng.randf_range(-0.3, 0.3), 0, rng.randf_range(-0.3, 0.3)) * float(mini(k, 1))
			var lean := Vector3(rng.randf_range(-0.06, 0.06), 0, rng.randf_range(-0.06, 0.06))
			sub.matte().set_emission(0.0)
			sub.tube(off, off + lean * s + Vector3(0, 0.4, 0) * s, 0.022 * s, 0.014 * s, Color("#d8d4c8"), 6)
			sub.surf(0.5).set_emission(0.75)
			sub.lathe(PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.15, 0.0), Vector2(0.13, 0.045), Vector2(0.05, 0.08), Vector2(0.0, 0.085)]),
				Transform3D(Basis.from_scale(Vector3.ONE * s), off + lean * s + Vector3(0, 0.39, 0) * s), cap.lerp(Pal.TEAL, rng.randf() * 0.25), 9, true)
		kit.merge(sub, xf)
		placed += 1
	var mi := kit.instance(MeshKit.material(), false)
	add_child(mi)


## The Deep Vault: a hexagonal dais ringed by six square pillars with warm lamps, clearly made
## by someone. The idol stands in the middle.
func _cavity_vault(c: Dictionary) -> void:
	var center: Vector3 = c["center"]
	var radius: float = c["radius"]
	var up: Vector3 = c["dir"]
	var x := up.cross(Vector3(0.3, 0.2, 0.9)).normalized()
	var floor_p: Vector3 = center - up * (radius - 1.4)
	var node := Node3D.new()
	add_child(node)
	node.global_transform = Transform3D(Basis(x, up, x.cross(up).normalized()), floor_p)
	var kit := MeshKit.new().matte()
	var stone := Pal.ROCK_WARM.darkened(0.2)
	kit.lathe(PackedVector2Array([Vector2(3.3, -0.5), Vector2(3.3, 0.02), Vector2(3.2, 0.1), Vector2(0.0, 0.1)]), Transform3D.IDENTITY, stone.darkened(0.12), 6, false, true)
	kit.lathe(PackedVector2Array([Vector2(1.1, 0.1), Vector2(1.1, 0.26), Vector2(1.0, 0.32), Vector2(0.0, 0.32)]), Transform3D.IDENTITY, stone, 6, false, true)
	for i in 6:
		var a := TAU * float(i) / 6.0
		var p := Vector3(cos(a), 0, sin(a)) * 2.7
		var b := Basis.from_euler(Vector3(0, -a, 0))
		kit.matte()
		kit.hbox(Transform3D(b, p + Vector3(0, 1.5, 0)), Vector3(0.42, 3.0, 0.42), stone, 0.04)
		kit.hbox(Transform3D(b, p + Vector3(0, 0.2, 0)), Vector3(0.58, 0.3, 0.58), stone.darkened(0.08), 0.04)
		kit.surf(0.4, 0.7)
		kit.hbox(Transform3D(b, p + Vector3(0, 3.04, 0)), Vector3(0.52, 0.1, 0.52), Pal.BRASS, 0.02)
		kit.surf(0.4).set_emission(1.8)
		kit.hbox(Transform3D(b, p + Vector3(0, 2.7, 0) - Vector3(cos(a), 0, sin(a)) * 0.215), Vector3(0.06, 0.4, 0.02), Pal.LAMP_WARM, 0.004)
		kit.set_emission(0.0)
	node.add_child(kit.instance(MeshKit.material(), false))


## The Old Workings: an abandoned dig from before your time. Timber sets brace the walls, a
## short run of narrow rail leads to a tipped ore tub, and one storm lantern still hangs from a
## beam. Wood and rusted iron only - nothing here is ours, so no amber.
func _cavity_workings(c: Dictionary, rng: RandomNumberGenerator) -> void:
	var center: Vector3 = c["center"]
	var radius: float = c["radius"]
	var up: Vector3 = c["dir"]
	var x := up.cross(Vector3(0.3, 0.2, 0.9)).normalized()
	var z := x.cross(up).normalized()
	var floor_hit: Variant = _wall(center, -up, radius * 1.6)
	var floor_p: Vector3 = floor_hit if floor_hit != null else center - up * (radius - 1.0)
	var node := Node3D.new()
	add_child(node)
	node.global_transform = Transform3D(Basis(x, up, z), floor_p)
	var kit := MeshKit.new()
	# timber sets: two posts and a cap, each set as far out as the walls allow
	for k in 3:
		var a := TAU * float(k) / 3.0 + rng.randf_range(-0.3, 0.3)
		var d := Vector3(cos(a), 0, sin(a))
		var wall: Variant = _wall(center, (x * d.x + z * d.z).normalized(), radius * 1.8)
		var reach := 3.0
		if wall != null:
			reach = clampf(((wall as Vector3) - center).length() - 0.5, 1.8, 6.0)
		var side := Vector3(-d.z, 0, d.x)
		var base := d * reach
		var b := Basis.from_euler(Vector3(0, -a, 0))
		kit.matte()
		for s: float in [-1.0, 1.0]:
			kit.hbox(Transform3D(b * Basis.from_euler(Vector3(0, 0, s * 0.05)), base + side * s * 0.9 + Vector3(0, 1.3, 0)), Vector3(0.2, 2.6, 0.2), Pal.WOOD_DARK, 0.02)
		kit.hbox(Transform3D(b, base + Vector3(0, 2.66, 0)), Vector3(0.22, 0.22, 2.3), Pal.WOOD, 0.02)
		kit.cast()
		for s: float in [-1.0, 1.0]:
			kit.hbox(Transform3D(b, base + Vector3(0, 2.66, 0) + side * s * 0.95), Vector3(0.26, 0.26, 0.06), Pal.RUST_DARK, 0.005)
	# narrow rails on sleepers
	var rail_dir := Vector3(1, 0, 0.2).normalized()
	var rail_side := Vector3(-rail_dir.z, 0, rail_dir.x)
	var rail_b := Basis(rail_side, Vector3.UP, -rail_dir)
	for i in 7:
		var t := -3.0 + float(i)
		kit.matte()
		kit.hbox(Transform3D(rail_b, rail_dir * t + Vector3(0, 0.04, 0)), Vector3(1.0, 0.08, 0.16), Pal.WOOD_DARK.darkened(0.1), 0.01)
	kit.cast()
	for s: float in [-0.3, 0.3]:
		kit.hbox(Transform3D(rail_b, rail_side * s + Vector3(0, 0.11, 0)), Vector3(0.05, 0.06, 6.4), Pal.RUST, 0.004)
	# tipped ore tub at the end of the line
	var tub := Transform3D(rail_b * Basis.from_euler(Vector3(0, 0, 1.25)), rail_dir * 3.9 + Vector3(0, 0.45, 0) + rail_side * 0.3)
	kit.cast()
	kit.hbox(tub, Vector3(0.8, 0.55, 1.1), Pal.RUST, 0.03)
	kit.hbox(tub.translated_local(Vector3(0, 0.3, 0)), Vector3(0.86, 0.06, 1.16), Pal.RUST_DARK, 0.01)
	for s: float in [-1.0, 1.0]:
		kit.tube(tub * Vector3(0.42, -0.25, s * 0.35), tub * Vector3(0.52, -0.25, s * 0.35), 0.13, 0.13, Pal.STEEL_DARK.darkened(0.3), 10)
	# spilled ore under the tub
	for i in 4:
		kit.rock(Transform3D(Basis.IDENTITY, rail_dir * (3.3 + rng.randf() * 0.8) + rail_side * rng.randf_range(0.4, 1.2) + Vector3(0, 0.05, 0)), rng.randf_range(0.1, 0.2), Pal.RUST.lerp(Pal.ROCK_DARK, 0.5), rng.randi(), 0.25)
	# a storm lantern hanging under a cap beam
	var lamp_at := Vector3(2.4, 2.25, 0.0)
	kit.bare()
	kit.tube(lamp_at + Vector3(0, 0.3, 0), lamp_at + Vector3(0, 0.12, 0), 0.008, 0.008, Pal.STEEL_DARK, 4)
	kit.cast()
	kit.lathe(PackedVector2Array([Vector2(0.07, -0.12), Vector2(0.08, -0.1), Vector2(0.08, 0.1), Vector2(0.05, 0.13), Vector2(0.0, 0.14)]), Transform3D(Basis.IDENTITY, lamp_at), Pal.RUST_DARK, 6, false, true)
	kit.surf(0.3).set_emission(1.4)
	kit.lathe(PackedVector2Array([Vector2(0.06, -0.09), Vector2(0.065, 0.08), Vector2(0.0, 0.09)]), Transform3D(Basis.IDENTITY, lamp_at), Pal.LAMP_WARM, 8)
	kit.set_emission(0.0)
	node.add_child(kit.instance(MeshKit.material(), true))
	var lamp := OmniLight3D.new()
	lamp.light_color = Pal.LAMP_WARM
	lamp.light_energy = 0.8
	lamp.omni_range = 7.0
	lamp.omni_attenuation = 1.4
	lamp.position = lamp_at
	node.add_child(lamp)


# ------------------------------------------------------------------ heart

func _build_heart() -> void:
	var core: Dictionary = planet.config.get("core", {})
	_core_id = str(core.get("discovery", ""))
	if _core_id == "":
		return
	var c1 := Color(str(core.get("color", "#f3cf7a")))
	var c2 := Color(str(core.get("color2", "#e8a23c")))
	var style := str(core.get("style", "seed"))
	heart = Node3D.new()
	heart.name = "Heart"
	add_child(heart)
	var kit := MeshKit.new()
	if style == "crystal":
		# a burst of long prisms around a bright nucleus
		kit.gloss().set_emission(3.0)
		kit.rock(Transform3D.IDENTITY, 0.5, c1, 77, 0.12, false)
		var rng := RandomNumberGenerator.new()
		rng.seed = 911
		for i in 14:
			var d := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized()
			var long := rng.randf_range(0.9, 1.7)
			kit.set_emission(rng.randf_range(1.0, 1.8))
			kit.crystal(d * 0.25, d * long, rng.randf_range(0.12, 0.2), c1.lerp(c2, rng.randf()), 6, 0.6)
	else:
		# a glowing seed inside a ribbed husk, like a lantern
		kit.surf(0.35).set_emission(3.2)
		kit.lathe(PackedVector2Array([Vector2(0.0, -1.0), Vector2(0.45, -0.78), Vector2(0.74, -0.25), Vector2(0.72, 0.3), Vector2(0.42, 0.9), Vector2(0.14, 1.25), Vector2(0.0, 1.32)]), Transform3D.IDENTITY, c1, 18, true)
		kit.surf(0.5, 0.55).set_emission(0.0)
		for i in 7:
			var a := TAU * float(i) / 7.0
			var out := Vector3(cos(a), 0, sin(a))
			kit.pipe(PackedVector3Array([Vector3(0, -1.12, 0), out * 0.56 + Vector3(0, -0.86, 0), out * 0.9 + Vector3(0, -0.26, 0), out * 0.88 + Vector3(0, 0.34, 0), out * 0.54 + Vector3(0, 1.0, 0), Vector3(0, 1.46, 0)]), 0.04, Color("#5a4636"), 6)
		kit.set_emission(0.3)
		kit.leaf(Vector3(0, 1.44, 0), Vector3(0.4, 2.05, 0.08), 0.34, Color("#8fae6a"), Vector3.UP)
		kit.leaf(Vector3(0, 1.44, 0), Vector3(-0.3, 1.86, -0.1), 0.26, Color("#7d9a5e"), Vector3.UP)
	kit.set_emission(0.0)
	_heart_mat = MeshKit.new_material(1.0)
	heart.add_child(kit.instance(_heart_mat, false))
	# two slow rings, like an armillary: they speed up when the heart is touched
	for i in 2:
		var ring := Node3D.new()
		ring.name = "Ring%d" % i
		ring.rotation = Vector3(0.5 + 0.9 * float(i), 0.0, 0.4 * float(i))
		heart.add_child(ring)
		var rk := MeshKit.new().surf(0.4, 0.7)
		rk.lathe(PackedVector2Array([Vector2(1.95 + 0.35 * float(i), -0.025), Vector2(1.98 + 0.35 * float(i), 0.0), Vector2(1.95 + 0.35 * float(i), 0.025), Vector2(1.9 + 0.35 * float(i), 0.0), Vector2(1.95 + 0.35 * float(i), -0.025)]), Transform3D.IDENTITY, Pal.BRASS, 48)
		rk.surf(0.3).set_emission(1.4)
		for k in 3:
			var a2 := TAU * float(k) / 3.0
			rk.sphere(Vector3(cos(a2), 0, sin(a2)) * (1.95 + 0.35 * float(i)), 0.05, c2, Vector3.ONE, 8, 5)
		ring.add_child(rk.instance(MeshKit.material(), false))
		_heart_rings.append(ring)
	heart_light = OmniLight3D.new()
	heart_light.light_color = c1
	heart_light.light_energy = 2.6
	heart_light.omni_range = geo.core_radius * 3.2
	heart_light.omni_attenuation = 1.2
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
	_heart_awake = 1.0 if GameState.has_discovery(_core_id) else 0.0


func touch_heart() -> void:
	if _core_id == "" or GameState.has_discovery(_core_id):
		Audio.play("heart", -6.0)
		_heart_spin = maxf(_heart_spin, 2.0)
		return
	Audio.play("heart", 2.0)
	for i in 3:
		world.fx.shock_ring(Vector3.ZERO, [Vector3.UP, Vector3.RIGHT, Vector3.FORWARD][i], geo.core_radius * (1.2 + 0.4 * i), Pal.LAMP_WARM, 1.0 + 0.25 * i)
	world.player.add_trauma(0.5)
	_heart_spin = 9.0
	var tw := create_tween()
	tw.tween_property(world, "bloom", 1.0, 3.5)
	world.discover(_core_id)


# ------------------------------------------------------------------ runtime

func _process(delta: float) -> void:
	_time += delta
	for a in artifacts:
		var model := (a["node"] as Node3D).get_node_or_null("Model") as Node3D
		if model != null:
			model.rotation.y = _time * 0.5
			model.position.y = 0.2 + sin(_time * 1.3) * 0.03
	if heart != null:
		var found := GameState.has_discovery(_core_id)
		_heart_awake = move_toward(_heart_awake, 1.0 if found else 0.0, delta * 0.4)
		_heart_spin = lerpf(_heart_spin, 0.0, clampf(delta * 0.6, 0.0, 1.0))
		var rate := lerpf(1.2, 2.2, _heart_awake)
		var beat := 0.5 + 0.5 * sin(_time * rate)
		beat = beat * beat
		heart.scale = Vector3.ONE * (1.0 + beat * 0.035)
		heart.rotation.y = _time * 0.12
		_heart_mat.set_shader_parameter("emission_scale", lerpf(0.75, 1.5, _heart_awake) + beat * 0.5)
		heart_light.light_energy = lerpf(2.2, 3.6, _heart_awake) + beat * 0.9
		for i in _heart_rings.size():
			var dir := 1.0 if i % 2 == 0 else -1.0
			_heart_rings[i].rotate_object_local(Vector3.UP, delta * dir * (0.25 + 0.2 * float(i) + _heart_spin))
	_check -= delta
	if _check <= 0.0 and world != null and world.player != null:
		_check = 0.3
		if not _undecorated.is_empty():
			_decorate_ready()
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
