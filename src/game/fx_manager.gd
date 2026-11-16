class_name FxManager
extends Node3D
## Pooled, cheap visual effects: colour-matched debris, dust puffs, sparks, gem sparkles,
## explosions and floating world-space text. Everything is GPU particles with short lifetimes;
## nothing here is physically simulated.

const DEBRIS_POOL := 10
const DUST_POOL := 8
const SPARK_POOL := 6

var planet: Planet
var _debris: Array[GPUParticles3D] = []
var _dust: Array[GPUParticles3D] = []
var _sparks: Array[GPUParticles3D] = []
var _next_debris := 0
var _next_dust := 0
var _next_spark := 0
var _soft_tex: GradientTexture2D
var _star_tex: GradientTexture2D
var _ring_mesh: ArrayMesh
var enabled := true
var active_text := 0


func setup(p: Planet) -> void:
	planet = p


func _ready() -> void:
	enabled = DisplayServer.get_name() != "headless"
	_soft_tex = _radial_texture(0.55)
	_star_tex = _radial_texture(0.12)
	if not enabled:
		return
	for i in DEBRIS_POOL:
		_debris.append(_make_debris())
	for i in DUST_POOL:
		_dust.append(_make_dust())
	for i in SPARK_POOL:
		_sparks.append(_make_sparks())


static func _radial_texture(core: float) -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(core, Color(1, 1, 1, 0.75))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 64
	t.height = 64
	return t


func _make_debris() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.amount = 18
	p.lifetime = 0.9
	p.explosiveness = 0.95
	p.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.4
	pm.direction = Vector3.UP
	pm.spread = 55.0
	pm.initial_velocity_min = 2.5
	pm.initial_velocity_max = 6.5
	pm.angular_velocity_min = -360.0
	pm.angular_velocity_max = 360.0
	pm.scale_min = 0.5
	pm.scale_max = 1.3
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1)); curve.add_point(Vector2(0.7, 0.9)); curve.add_point(Vector2(1, 0))
	var ct := CurveTexture.new(); ct.curve = curve
	pm.scale_curve = ct
	pm.gravity = Vector3(0, -16, 0)
	p.process_material = pm
	var kit := MeshKit.new().matte()
	kit.rock(Transform3D(Basis.from_scale(Vector3(1.0, 0.8, 0.9)), Vector3.ZERO), 0.085, Color.WHITE, 17, 0.28, false)
	p.draw_pass_1 = kit.commit()
	p.material_override = MeshKit.material()
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	return p


func _billboard_material(tex: Texture2D, additive: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = tex
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.disable_receive_shadows = true
	return m


func _make_dust() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.amount = 7
	p.lifetime = 1.3
	p.explosiveness = 0.92
	p.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.5
	pm.direction = Vector3.UP
	pm.spread = 80.0
	pm.initial_velocity_min = 0.6
	pm.initial_velocity_max = 2.2
	pm.damping_min = 1.5
	pm.damping_max = 2.5
	pm.gravity = Vector3(0, 0.6, 0)
	pm.scale_min = 0.9
	pm.scale_max = 1.8
	var sc := Curve.new()
	sc.add_point(Vector2(0, 0.35)); sc.add_point(Vector2(0.3, 0.85)); sc.add_point(Vector2(1, 1.25))
	var sct := CurveTexture.new(); sct.curve = sc
	pm.scale_curve = sct
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 0.3)); grad.set_color(1, Color(1, 1, 1, 0.0))
	var gt := GradientTexture1D.new(); gt.gradient = grad
	pm.color_ramp = gt
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(1.0, 1.0)
	q.material = _billboard_material(_soft_tex, false)
	p.draw_pass_1 = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	return p


func _make_sparks() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.amount = 10
	p.lifetime = 0.35
	p.explosiveness = 1.0
	p.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3.UP
	pm.spread = 70.0
	pm.initial_velocity_min = 3.0
	pm.initial_velocity_max = 8.0
	pm.gravity = Vector3(0, -9, 0)
	pm.scale_min = 0.04
	pm.scale_max = 0.11
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 1)); grad.set_color(1, Color(1, 1, 1, 0))
	var gt := GradientTexture1D.new(); gt.gradient = grad
	pm.color_ramp = gt
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(1.0, 1.0)
	q.material = _billboard_material(_star_tex, true)
	p.draw_pass_1 = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	return p


func _orient(p: GPUParticles3D, pos: Vector3, normal: Vector3) -> void:
	var n := normal.normalized() if normal.length() > 0.01 else Vector3.UP
	var x := n.cross(Vector3.FORWARD if absf(n.dot(Vector3.FORWARD)) < 0.95 else Vector3.RIGHT).normalized()
	p.global_transform = Transform3D(Basis(x, n, x.cross(n).normalized()), pos)
	var pm := p.process_material as ParticleProcessMaterial
	var g := planet.gravity_at(pos) if planet else Vector3(0, -16, 0)
	# process-material gravity is in world space when local_coords is off
	if p in _dust:
		pm.gravity = -g.normalized() * 0.6 if g.length() > 0.1 else Vector3.ZERO
	else:
		pm.gravity = g
	pm.direction = Vector3.UP


## Colour-matched debris + dust for a normal dig. `amount` scales with the bite size.
func dig_burst(pos: Vector3, normal: Vector3, color: Color, amount := 1.0, dusty := true) -> void:
	if not enabled:
		return
	var d := _debris[_next_debris]
	_next_debris = (_next_debris + 1) % DEBRIS_POOL
	_orient(d, pos, normal)
	var pm := d.process_material as ParticleProcessMaterial
	pm.color = color
	pm.emission_sphere_radius = 0.3 * amount
	pm.initial_velocity_min = 2.0 + amount
	pm.initial_velocity_max = 5.0 + amount * 2.0
	pm.scale_min = 0.5 * sqrt(amount)
	pm.scale_max = 1.3 * sqrt(amount)
	d.amount = clampi(int(10.0 + amount * 8.0), 8, 48)
	d.restart()
	if dusty:
		var du := _dust[_next_dust]
		_next_dust = (_next_dust + 1) % DUST_POOL
		_orient(du, pos, normal)
		var dm := du.process_material as ParticleProcessMaterial
		dm.color = Color(color.r * 0.7 + 0.25, color.g * 0.7 + 0.25, color.b * 0.7 + 0.24, 1.0)
		dm.emission_sphere_radius = 0.45 * amount
		dm.scale_min = 0.8 * amount
		dm.scale_max = 1.6 * amount
		du.restart()


## Bright sparks: tool bounced off something too hard, or gem glints.
func sparks(pos: Vector3, normal: Vector3, color := Color(1.0, 0.86, 0.6), count := 8) -> void:
	if not enabled:
		return
	var s := _sparks[_next_spark]
	_next_spark = (_next_spark + 1) % SPARK_POOL
	_orient(s, pos, normal)
	(s.process_material as ParticleProcessMaterial).color = color
	s.amount = count
	s.restart()


func explosion(pos: Vector3, radius: float, color: Color) -> void:
	if not enabled:
		return
	var up := planet.up_at(pos) if planet else Vector3.UP
	for i in 3:
		dig_burst(pos + up * 0.3, up, color.lightened(0.06 * i), radius * 0.9, true)
	sparks(pos, up, Color(1.0, 0.85, 0.6), 14)
	# flash
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.82, 0.6)
	light.light_energy = 3.5
	light.omni_range = radius * 4.0
	add_child(light)
	light.global_position = pos + up * 0.5
	var tw := create_tween()
	tw.tween_property(light, "light_energy", 0.0, 0.35)
	tw.tween_callback(light.queue_free)
	# shockwave ring
	shock_ring(pos, up, radius * 1.5, Color(0.95, 0.92, 0.85), 0.4)


func shock_ring(pos: Vector3, normal: Vector3, radius: float, color: Color, duration := 0.45) -> void:
	if not enabled:
		return
	if _ring_mesh == null:
		var kit := MeshKit.new()
		kit.emission = 1.2
		kit.torus(Transform3D.IDENTITY, 1.0, 0.018, Color.WHITE, 36, 5)
		_ring_mesh = kit.commit()
	var mi := MeshInstance3D.new()
	mi.mesh = _ring_mesh
	var mat := MeshKit.new_material(1.0, 0.0)
	mat.set_shader_parameter("tint", color)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var n := normal.normalized()
	var x := n.cross(Vector3.FORWARD if absf(n.dot(Vector3.FORWARD)) < 0.95 else Vector3.RIGHT).normalized()
	mi.global_transform = Transform3D(Basis(x, n, x.cross(n).normalized()).scaled(Vector3.ONE * 0.2), pos + n * 0.15)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * radius, duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(mat, "shader_parameter/emission_scale", 0.0, duration)
	tw.chain().tween_callback(mi.queue_free)


## Rising, fading world-space label ("+120", "TOO HARD", ...).
func floating_text(pos: Vector3, text: String, color: Color, size := 1.0, rise := 1.2, duration := 1.1) -> void:
	if not enabled or active_text > 24:
		return
	var l := Label3D.new()
	l.text = text
	l.font = UiTheme.font_bold()
	l.font_size = 64
	l.pixel_size = 0.006 * size
	l.modulate = color
	l.outline_size = 10
	l.outline_modulate = Color(0.06, 0.07, 0.09, 0.85)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.fixed_size = false
	l.render_priority = 5
	add_child(l)
	l.global_position = pos
	active_text += 1
	var up := planet.up_at(pos) if planet else Vector3.UP
	var tw := create_tween().set_parallel(true)
	tw.tween_property(l, "global_position", pos + up * rise, duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(l, "modulate:a", 0.0, duration * 0.45).set_delay(duration * 0.55)
	tw.tween_property(l, "outline_modulate:a", 0.0, duration * 0.45).set_delay(duration * 0.55)
	tw.chain().tween_callback(func() -> void:
		active_text -= 1
		l.queue_free())
