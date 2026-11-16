class_name MenuBackdrop
extends Node3D
## 3D scene behind the main menu: a small planet with one very deep, cleanly cut hole that
## shows its strata, the lander standing beside it, turning slowly in open space.

var _planet: Node3D
var _moon: Node3D
var _sky: ShaderMaterial
var _t := 0.0


func _ready() -> void:
	var cfg := GameData.planet("pipseed")
	var pal: Dictionary = cfg.get("palette", {})
	var env := Environment.new()
	_sky = ShaderMaterial.new()
	_sky.shader = preload("res://shaders/sky.gdshader")
	# seen from orbit: nearly all space, a faint glow low in the frame
	_sky.set_shader_parameter("up_dir", Vector3(0.1, 1.0, 0.2).normalized())
	_sky.set_shader_parameter("sun_dir", Vector3(-0.5, 0.45, 0.6).normalized())
	_sky.set_shader_parameter("top_color", Color("#05080f"))
	_sky.set_shader_parameter("mid_color", Color("#0a1322"))
	_sky.set_shader_parameter("horizon_color", Color("#16273d"))
	_sky.set_shader_parameter("ground_color", Color("#0a1018"))
	_sky.set_shader_parameter("atmosphere", 0.0)
	_sky.set_shader_parameter("star_amount", 1.0)
	_sky.set_shader_parameter("nebula_amount", 0.6)
	_sky.set_shader_parameter("planet_a_size", 0.0001)
	_sky.set_shader_parameter("moon_size", 0.0001)
	_sky.set_shader_parameter("horizon_dip", 0.9)
	var sky := Sky.new()
	sky.sky_material = _sky
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#8fa6c4")
	env.ambient_light_energy = 0.35
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_intensity = 0.25
	env.glow_hdr_threshold = 1.6
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.9
	sun.light_color = Color(str(pal.get("sun", "#fff1d6")))
	sun.shadow_enabled = true
	sun.look_at_from_position(Vector3(-6, 5, 6), Vector3.ZERO)
	add_child(sun)
	var cam := Camera3D.new()
	cam.fov = 40.0
	cam.position = Vector3(-3.4, 0.6, 12.0)
	cam.look_at_from_position(cam.position, Vector3(-3.4, 0.2, 0.0))
	add_child(cam)
	cam.make_current()

	_planet = Node3D.new()
	_planet.position = Vector3(2.0, -0.2, 0)
	add_child(_planet)
	var grass: Array = pal.get("grass", ["#7d9a5e", "#6b8f66", "#a3a868"])
	var kit := MeshKit.new().matte()
	var r := 3.0
	# The planet is one lathe whose profile dips into a stepped pit at the pole, so the hole is
	# real geometry with every stratum in its own colour.
	var rim_a := deg_to_rad(152.0)
	var body := PackedVector2Array()
	for i in 25:
		var a := rim_a * float(i) / 24.0
		body.append(Vector2(r * sin(a), -r * cos(a)))
	kit.lathe(body, Transform3D.IDENTITY, Color(str(grass[0])), 56, true)
	var rim := Vector2(r * sin(rim_a), -r * cos(rim_a))
	var strata := ["topsoil", "clay", "stone", "hardrock"]
	var p := rim
	for i in strata.size():
		var col: Color = GameData.material(strata[i])["color_c"]
		var wall := Vector2(p.x - 0.06, p.y - 0.42)
		var ledge := Vector2(wall.x - 0.26, wall.y)
		kit.lathe(PackedVector2Array([p, wall]), Transform3D.IDENTITY, col, 56)
		kit.lathe(PackedVector2Array([wall, ledge]), Transform3D.IDENTITY, col.darkened(0.12), 56)
		p = ledge
	kit.lathe(PackedVector2Array([p, Vector2(p.x - 0.05, p.y - 0.5), Vector2(0.0, p.y - 0.5)]), Transform3D.IDENTITY, GameData.material("corestone")["color_c"], 56)
	# something glints at the bottom
	kit.gloss().set_emission(0.8)
	var floor_y := p.y - 0.5
	for k in 3:
		var a2 := TAU * float(k) / 3.0
		kit.crystal(Vector3(cos(a2) * 0.12, floor_y, sin(a2) * 0.12), Vector3(cos(a2) * 0.3, floor_y + 0.4 + 0.12 * k, sin(a2) * 0.3), 0.08, GameData.material("amethyst")["color2_c"], 6)
	kit.matte().set_emission(0.0)
	# low hills, boulders and a few trees
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var top := Vector3.UP
	for i in 22:
		var d := _rand_dir(rng)
		if d.dot(top) > 0.72:
			continue
		kit.blob(Transform3D(_basis(d) * Basis.from_scale(Vector3(1.0, 0.22, 1.0) * rng.randf_range(0.7, 1.2)), d * (r - 0.1)), Color(str(grass[i % 3])).lerp(Color(str(grass[0])), 0.6), 20, 10)
	for i in 30:
		var d2 := _rand_dir(rng)
		if d2.dot(top) > 0.78:
			continue
		var b := _basis(d2)
		var base := d2 * (r + 0.02)
		if i % 3 == 0:
			kit.tube(base, base + d2 * 0.42, 0.03, 0.02, Pal.BARK, 5)
			kit.rock(Transform3D(b * Basis.from_scale(Vector3(1.0, 0.32, 1.0)), base + d2 * 0.45), 0.24, Color("#5c876c"), 500 + i, 0.14, false)
			kit.rock(Transform3D(b * Basis.from_scale(Vector3(1.0, 0.32, 1.0)), base + d2 * 0.58 + b.x * 0.06), 0.15, Color("#6f8f58"), 600 + i, 0.14, false)
		else:
			kit.rock(Transform3D(b, base), rng.randf_range(0.08, 0.2), Pal.ROCK if i % 2 == 0 else Pal.ROCK_WARM, 700 + i, 0.24)
	# the lander beside the pit
	var rd := (top + Vector3(0.62, 0.0, 0.3)).normalized()
	var rb := _basis(rd)
	var p0 := rd * (r + 0.02)
	kit.paint()
	kit.lathe(PackedVector2Array([Vector2(0.14, 0.12), Vector2(0.2, 0.3), Vector2(0.2, 0.86), Vector2(0.15, 1.08), Vector2(0.08, 1.2)]), Transform3D(rb, p0), Pal.HULL, 16, true)
	kit.lathe(PackedVector2Array([Vector2(0.08, 1.2), Vector2(0.0, 1.3)]), Transform3D(rb, p0), Pal.GRAPHITE, 12)
	kit.lathe(PackedVector2Array([Vector2(0.202, 0.74), Vector2(0.202, 0.78)]), Transform3D(rb, p0), Pal.AMBER, 16)
	kit.cast()
	kit.lathe(PackedVector2Array([Vector2(0.12, 0.02), Vector2(0.08, 0.14)]), Transform3D(rb, p0), Pal.GRAPHITE, 12)
	kit.bare()
	for i in 3:
		var a3 := TAU * float(i) / 3.0
		var out := (rb.x * cos(a3) + rb.z * sin(a3))
		kit.tube(p0 + out * 0.2 + rd * 0.36, p0 + out * 0.42, 0.016, 0.012, Pal.STEEL, 5)
	_planet.add_child(kit.instance())
	# tilt the pit towards the camera
	_planet.rotation = Vector3(deg_to_rad(52.0), 0.0, deg_to_rad(-16.0))

	# the neighbouring moon
	_moon = Node3D.new()
	add_child(_moon)
	var gpal: Dictionary = GameData.planet("glimmerock").get("palette", {})
	var gs: Array = gpal.get("from_space", ["#aab3c8", "#6f7f9a"])
	var mk := MeshKit.new().matte()
	mk.rock(Transform3D.IDENTITY, 0.6, Color(str(gs[0])), 9, 0.05, false)
	mk.gloss().set_emission(0.5)
	mk.crystal(Vector3(0, 0.5, 0), Vector3(0.08, 0.95, 0), 0.08, Color("#4fc6bd"), 6)
	_moon.add_child(mk.instance())


func _rand_dir(rng: RandomNumberGenerator) -> Vector3:
	var z := rng.randf_range(-1.0, 1.0)
	var a := rng.randf() * TAU
	var s := sqrt(1.0 - z * z)
	return Vector3(s * cos(a), z, s * sin(a))


func _basis(up: Vector3) -> Basis:
	var x := up.cross(Vector3(0.3, 0.2, 0.9)).normalized()
	return Basis(x, up, x.cross(up).normalized())


func _process(delta: float) -> void:
	_t += delta
	# turn about the pit's own axis so the hole stays in view
	_planet.rotate_object_local(Vector3.UP, delta * 0.07)
	_moon.position = _planet.position + Vector3(cos(_t * 0.12) * 5.6, 1.9 + sin(_t * 0.2) * 0.3, sin(_t * 0.12) * 5.6 - 2.0)
	_moon.rotation.y = _t * 0.2
