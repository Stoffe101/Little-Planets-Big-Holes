class_name Formation
extends StaticBody3D
## A harvestable crystal formation. Unlike soil it does not get "dug": tools crack it over a few
## hits and it shatters into gem chunks. Needs a tool whose power >= the crystal's hardness.

signal shattered(formation: Formation)

var material_index := 0
var units := 3
var hits_left := 2
var flag_key := ""           ## GameState flag that marks this formation as already harvested
var mesh_instance: MeshInstance3D
var light: OmniLight3D
var _wobble := 0.0
var _base_scale := Vector3.ONE


func setup(mat: int, total_units: int, size: float, colors: Array, seed_value: int, with_light := false) -> void:
	material_index = mat
	units = total_units
	hits_left = 1 + int(size > 1.2) + int(size > 2.2)
	collision_layer = 4
	collision_mask = 0
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var kit := MeshKit.new()
	var def := GameData.materials[mat]
	var main_col := Color(str(colors[rng.randi() % colors.size()])) if not colors.is_empty() else (def["color_c"] as Color)
	# A mineral deposit, not a toy: a low bed of host rock with a tight cluster of glossy,
	# properly faceted prisms growing out of it. The gloss does the sparkling (sun, headlamp);
	# emission stays very low so a cavern full of them does not wash out.
	kit.matte()
	kit.rock(Transform3D(Basis.from_scale(Vector3(1.25, 0.42, 1.1)), Vector3(0, 0.02, 0)), size * 0.3, Pal.ROCK_DARK, seed_value + 5, 0.22)
	kit.gloss()
	kit.emission = clampf(float(def.get("emission", 0.2)) * 0.5, 0.03, 0.22)
	var n := 4 + rng.randi() % 4
	for i in n:
		var ang := rng.randf() * TAU
		var spread := 0.0 if i == 0 else rng.randf_range(0.25, 0.75)
		var lean := Vector3(cos(ang), 0, sin(ang)) * spread
		var h := size * (1.0 if i == 0 else rng.randf_range(0.3, 0.7))
		var base := Vector3(lean.x, -0.08, lean.z) * size * 0.3
		var tip := base + (Vector3.UP + lean * 0.7).normalized() * h
		var c := main_col.lerp(def["color2_c"], rng.randf_range(0.0, 0.3))
		c = c.darkened(rng.randf_range(0.0, 0.12))
		kit.crystal(base, tip, size * (0.13 if i == 0 else rng.randf_range(0.055, 0.1)), c, 6, rng.randf_range(0.78, 0.9))
	mesh_instance = kit.instance(MeshKit.material(), true)
	add_child(mesh_instance)
	var shape := CapsuleShape3D.new()
	shape.radius = size * 0.34
	shape.height = maxf(size * 1.0, shape.radius * 2.0)
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position = Vector3(0, size * 0.42, 0)
	add_child(col)
	if with_light:
		light = OmniLight3D.new()
		light.light_color = main_col
		light.light_energy = 0.5
		light.omni_range = 4.0 + size * 2.5
		light.omni_attenuation = 1.4
		light.shadow_enabled = false
		light.position = Vector3(0, size * 0.6, 0)
		add_child(light)
	_base_scale = scale


## Returns true if the hit did something (crack or shatter); false if the tool is too weak.
func hit(power: int, world: Node3D, ore_bonus := 0.0) -> bool:
	var def := GameData.materials[material_index]
	if power < int(def["hardness"]):
		return false
	hits_left -= 1
	_wobble = 1.0
	var up := global_basis.y.normalized()
	var top := global_position + up * 0.6
	world.fx.sparks(top, up, def["color2_c"], 6)
	if hits_left > 0:
		Audio.play("dig_crystal", -3.0, 1.15, 0.1)
		return true
	# shatter
	var total := int(round(float(units) * (1.0 + ore_bonus)))
	world.pickups.burst({material_index: total}, top, up, 0.8, 8)
	world.fx.dig_burst(top, up, def["color_c"], 1.4, false)
	world.fx.shock_ring(global_position + up * 0.2, up, 2.2, def["color2_c"], 0.35)
	Audio.play("shatter", -1.0, 1.0, 0.08)
	if flag_key != "":
		GameState.set_flag(flag_key)
	GameState.add_stat("formations")
	shattered.emit(self)
	queue_free()
	return true


func _process(delta: float) -> void:
	if _wobble > 0.0:
		_wobble = maxf(0.0, _wobble - delta * 4.0)
		var s := 1.0 + sin(_wobble * 30.0) * 0.08 * _wobble
		mesh_instance.scale = Vector3(s, 2.0 - s, s)
