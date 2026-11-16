class_name MenuBackdrop
extends Node3D
## 3D scene behind the main menu: a tiny toy planet with a rocket, trees and one very big hole,
## turning slowly under a candy-coloured sky.

var _planet: Node3D
var _moon: Node3D
var _sky: ShaderMaterial
var _t := 0.0


func _ready() -> void:
	var env := Environment.new()
	_sky = ShaderMaterial.new()
	_sky.shader = preload("res://shaders/sky.gdshader")
	_sky.set_shader_parameter("up_dir", Vector3(0.1, 1.0, 0.2).normalized())
	_sky.set_shader_parameter("sun_dir", Vector3(-0.5, 0.45, 0.6).normalized())
	_sky.set_shader_parameter("planet_a_dir", Vector3(0.9, 0.3, -0.5))
	_sky.set_shader_parameter("planet_b_dir", Vector3(-0.8, 0.5, -0.4))
	var sky := Sky.new()
	sky.sky_material = _sky
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#b9b4ff")
	env.ambient_light_energy = 0.34
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED   # sky reflections wash out the palette
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.glow_enabled = true
	env.glow_intensity = 0.45
	env.glow_hdr_threshold = 1.1
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_energy = 0.8
	sun.light_color = Color("#fff2c9")
	sun.shadow_enabled = true
	sun.look_at_from_position(Vector3(-5, 5, 7), Vector3.ZERO)
	add_child(sun)
	var cam := Camera3D.new()
	cam.fov = 42.0
	cam.position = Vector3(-3.6, 0.9, 11.5)
	cam.look_at_from_position(cam.position, Vector3(-3.6, 0.4, 0.0))
	add_child(cam)
	cam.make_current()

	_planet = Node3D.new()
	_planet.position = Vector3(1.6, -0.3, 0)
	add_child(_planet)
	var kit := MeshKit.new()
	var r := 3.0
	kit.sphere(Vector3.ZERO, r, Color("#7fdc5a"), Vector3.ONE, 40, 24)
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var hill_cols := [Color("#3fcf8e"), Color("#c9ea5c"), Color("#6fd65a")]
	for i in 26:
		var d := _rand_dir(rng)
		kit.sphere(d * (r - 0.55), rng.randf_range(0.7, 1.3), hill_cols[i % 3], Vector3.ONE, 14, 8)
	# the big hole: a dark soil bowl with strata rings and a glowing gem at the bottom
	var hole_dir := Vector3(-0.35, 0.55, 0.76).normalized()
	var hb := _basis(hole_dir)
	kit.blob(Transform3D(hb.scaled(Vector3(1.15, 0.5, 1.15)), hole_dir * (r - 0.05)), Color("#8a5638"), 18, 8)
	kit.blob(Transform3D(hb.scaled(Vector3(0.85, 0.5, 0.85)), hole_dir * (r - 0.0)), Color("#c2643c"), 16, 8)
	kit.blob(Transform3D(hb.scaled(Vector3(0.56, 0.5, 0.56)), hole_dir * (r + 0.04)), Color("#7d8aa6"), 14, 8)
	kit.blob(Transform3D(hb.scaled(Vector3(0.3, 0.5, 0.3)), hole_dir * (r + 0.07)), Color("#3a2b52"), 12, 6)
	kit.set_emission(2.0)
	kit.crystal(hole_dir * (r + 0.2), hole_dir * (r + 0.75), 0.14, Color("#b266ff"))
	kit.set_emission(0.0)
	# trees, mushrooms, rocks
	var tree_cols := [Color("#ff8fb8"), Color("#ffb347"), Color("#6fe3c4"), Color("#ffe36b")]
	for i in 34:
		var d2 := _rand_dir(rng)
		if d2.dot(hole_dir) > 0.82:
			continue
		var b := _basis(d2)
		var base := d2 * (r + 0.25)
		var kind := i % 3
		if kind == 0:
			kit.tube(base, base + d2 * 0.45, 0.07, 0.05, Color("#8a5a3a"), 6)
			kit.sphere(base + d2 * 0.72, 0.36, tree_cols[i % 4], Vector3.ONE, 10, 6)
			kit.sphere(base + d2 * 1.02, 0.22, (tree_cols[i % 4] as Color).lightened(0.15), Vector3.ONE, 8, 5)
		elif kind == 1:
			kit.tube(base, base + d2 * 0.16, 0.05, 0.04, Color("#fff3df"), 6)
			kit.blob(Transform3D(b.scaled(Vector3(0.17, 0.11, 0.17)), base + d2 * 0.18), Color("#ff5d73"), 8, 5)
		else:
			kit.rbox(Transform3D(b, base - d2 * 0.05), Vector3(0.34, 0.26, 0.3), Color("#9aa3bd"), 0.5)
	# rocket
	var rd := Vector3(0.5, 0.75, 0.42).normalized()
	var rb := _basis(rd)
	var p0 := rd * (r + 0.35)
	kit.tube(p0, p0 + rd * 0.95, 0.24, 0.22, Color("#f6f0ff"), 12)
	kit.cone(p0 + rd * 0.95, p0 + rd * 1.45, 0.22, Color("#ff5d6c"), 12)
	for i in 3:
		var a := TAU * float(i) / 3.0
		var out := (rb.x * cos(a) + rb.z * sin(a))
		kit.rbox(Transform3D(Basis(out, rd, out.cross(rd)), p0 + out * 0.3 + rd * 0.15), Vector3(0.26, 0.42, 0.06), Color("#ff5d6c"), 0.5)
	kit.set_emission(1.2)
	kit.sphere(p0 + rd * 0.62 + rb.z * 0.2, 0.09, Color("#7fe6ff"), Vector3.ONE, 8, 5)
	kit.set_emission(0.0)
	_planet.add_child(kit.instance())
	# a little moon with its own crater
	_moon = Node3D.new()
	add_child(_moon)
	var mk := MeshKit.new()
	mk.sphere(Vector3.ZERO, 0.7, Color("#d9c8ff"), Vector3.ONE, 20, 12)
	mk.sphere(Vector3(0.2, 0.3, 0.5), 0.28, Color("#a995dd"), Vector3(1, 1, 0.5), 10, 6)
	mk.sphere(Vector3(-0.4, -0.1, 0.4), 0.2, Color("#a995dd"), Vector3(1, 1, 0.5), 10, 6)
	mk.set_emission(1.5)
	mk.crystal(Vector3(0, 0.6, 0), Vector3(0.1, 1.15, 0), 0.12, Color("#7dfff0"))
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
	_planet.rotation = Vector3(0.18 * sin(_t * 0.2), _t * 0.12, 0.08)
	_moon.position = _planet.position + Vector3(cos(_t * 0.3) * 5.2, 1.6 + sin(_t * 0.4) * 0.5, sin(_t * 0.3) * 5.2)
	_moon.rotation.y = _t * 0.5
