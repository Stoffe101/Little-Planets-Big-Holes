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
	kit.emission = maxf(float(def.get("emission", 0.4)), 0.35)
	var main_col := Color(str(colors[rng.randi() % colors.size()])) if not colors.is_empty() else (def["color_c"] as Color)
	var n := 3 + rng.randi() % 4
	for i in n:
		var lean := Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)) * (0.15 + 0.5 * float(i > 0))
		var h := size * (1.0 if i == 0 else rng.randf_range(0.35, 0.75))
		var base := Vector3(lean.x, -0.15, lean.z) * size * 0.45
		var tip := base + (Vector3.UP + lean * 0.55).normalized() * h
		var c := main_col if i % 2 == 0 else main_col.lerp(def["color2_c"], 0.5)
		kit.crystal(base, tip, size * (0.2 if i == 0 else rng.randf_range(0.1, 0.16)), c, 5 + rng.randi() % 2)
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
		light.light_energy = 1.1
		light.omni_range = 3.5 + size * 2.0
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
	world.fx.sparks(top, up, def["color2_c"], 16)
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
