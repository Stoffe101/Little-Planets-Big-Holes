class_name ToolPreview
extends SubViewportContainer
## A small studio that renders one model on a slow turntable (shop previews, journal).
## Owns its own 3D world, so it works on top of the paused or dimmed game.

var _viewport: SubViewport
var _turntable: Node3D
var _camera: Camera3D
var _model: Node3D
var _material: ShaderMaterial
var _spin := 0.35
var _boost := 0.0
var _flash := 0.0
var _base_distance := 1.7


func _init() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	add_child(_viewport)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0, 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#c9d3df")
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_white = 6.0
	var we := WorldEnvironment.new()
	we.environment = env
	_viewport.add_child(we)
	var key := DirectionalLight3D.new()
	key.light_energy = 1.6
	key.light_color = Color("#fff3e0")
	key.rotation = Vector3(deg_to_rad(-42.0), deg_to_rad(38.0), 0.0)
	_viewport.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.light_energy = 0.55
	rim.light_color = Color("#bcd6ff")
	rim.rotation = Vector3(deg_to_rad(-12.0), deg_to_rad(-150.0), 0.0)
	_viewport.add_child(rim)
	_camera = Camera3D.new()
	_camera.fov = 30.0
	_camera.near = 0.05
	_viewport.add_child(_camera)
	_turntable = Node3D.new()
	_viewport.add_child(_turntable)
	_place_camera(1.0)


func _place_camera(size: float) -> void:
	_camera.position = Vector3(0.0, 0.42 * size, _base_distance * size)
	_camera.look_at_from_position(_camera.position, Vector3.ZERO)


## Shows a tool tier with the given mod levels.
## `reset_view` turns the model side-on again (use it when the subject changes, not when
## only its attachments do).
func show_tool(family_id: String, tier: int, mods: Dictionary, reset_view := true) -> void:
	var m := ToolModels.build(family_id, tier, mods, false)
	_material = m["material"]
	_set_model(m["root"], Vector3(deg_to_rad(10.0), 0.0, deg_to_rad(-8.0)))
	if reset_view:
		_turntable.rotation = Vector3(0.0, deg_to_rad(112.0), 0.0)


## Shows any prebuilt node (gear models).
func show_node(node: Node3D) -> void:
	_material = null
	_set_model(node, Vector3.ZERO)


func _set_model(node: Node3D, tilt: Vector3) -> void:
	if _model != null:
		_model.queue_free()
	_model = node
	_turntable.add_child(node)
	node.rotation = tilt
	# centre the model on the turntable and frame it by its real size
	var box := _bounds(node, Transform3D(Basis.from_euler(tilt), Vector3.ZERO))
	node.position = -box.get_center()
	var extent := maxf(box.size.length(), 0.2)
	_place_camera(clampf(extent / 0.98, 0.42, 1.6))


static func _bounds(node: Node3D, xf: Transform3D) -> AABB:
	var out := AABB()
	var first := true
	var stack: Array = [[node, xf]]
	while not stack.is_empty():
		var item: Array = stack.pop_back()
		var n: Node3D = item[0]
		var t: Transform3D = item[1]
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var b := t * (n as MeshInstance3D).mesh.get_aabb()
			out = b if first else out.merge(b)
			first = false
		for c in n.get_children():
			if c is Node3D:
				stack.append([c, t * (c as Node3D).transform])
	return out


## A quick spin and highlight, played when something is bought.
func celebrate() -> void:
	_boost = 1.0
	_flash = 1.0


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_boost = lerpf(_boost, 0.0, clampf(delta * 2.2, 0.0, 1.0))
	_flash = maxf(0.0, _flash - delta * 2.0)
	_turntable.rotate_y(delta * (_spin + _boost * 9.0))
	if _material != null:
		_material.set_shader_parameter("flash", _flash * _flash)
