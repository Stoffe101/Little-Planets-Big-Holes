class_name RocketBase
extends Node3D
## The home base at the landing site: the rocket (planet travel), the Sell-o-Matic (walk onto
## the pad to sell everything), a Tool Shop and a Gear Shop kiosk with physical displays of the
## next thing you can buy, a helper-bot dock and some cosy lighting.

signal interact_requested(what: String)     ## "tools", "gear", "rocket"
signal sale_completed(total: int)

const C_WHITE := Color("#f6f0ff")
const C_RED := Color("#ff5d6c")
const C_YELLOW := Color("#ffd23f")
const C_ORANGE := Color("#ff9438")
const C_TEAL := Color("#39d6c4")
const C_BLUE := Color("#4f8dff")
const C_PURPLE := Color("#8f6bff")
const C_PINK := Color("#ff7fb0")
const C_INK := Color("#2a2540")
const C_STEEL := Color("#aab4d0")
const C_WOOD := Color("#b07a45")

var world: World
var planet: Planet
var geo: Geology
var origin := Vector3.ZERO
var frame := Basis.IDENTITY
var hopper_node: Node3D
var sell_display: Label3D
var sell_pad_center := Vector3.ZERO
var dock_position := Vector3.ZERO
var _tool_display: Node3D
var _gear_display: Node3D
var _display_spin := 0.0
var _player_on_pad := false
var _sell_cooldown := 0.0
var _hopper_bounce := 0.0
var _rocket: Node3D


func setup(w: World) -> void:
	world = w
	planet = w.planet
	geo = planet.geology
	var up := geo.landing_dir
	origin = up * geo.surface_radius(up)
	var x := up.cross(Vector3(0.0, 0.2, 1.0)).normalized()
	frame = Basis(x, up, x.cross(up).normalized())
	_build_pad()
	_build_rocket(Vector2(0, 0))
	_build_sell_station(Vector2(5.2, 1.6))
	_build_kiosk(Vector2(-4.6, 3.4), "tools", "TOOLS", C_ORANGE, C_YELLOW)
	_build_kiosk(Vector2(-5.2, -2.6), "gear", "GEAR", C_TEAL, C_PINK)
	_build_dock(Vector2(3.4, -4.6))
	_build_sign(Vector2(1.2, 5.9))
	for lp: Vector2 in [Vector2(6.3, -2.2), Vector2(-1.5, -6.2), Vector2(-6.4, 0.6), Vector2(2.6, 3.6)]:
		_build_lamp(lp)
	GameState.tools_changed.connect(_refresh_displays)
	GameState.gear_changed.connect(func(_id: String) -> void: _refresh_displays())
	_refresh_displays()


# ------------------------------------------------------------------ placement

## World transform for a spot on the pad given local metres (x, z) from the rocket.
func _spot(local: Vector2, yaw := 0.0, on_ground := true) -> Transform3D:
	var dir := (geo.landing_dir + (frame.x * local.x + frame.z * local.y) / geo.radius).normalized()
	var p := planet.ground_point(dir) if on_ground else dir * geo.surface_radius(dir)
	var x := (frame.x - dir * frame.x.dot(dir)).normalized().rotated(dir, yaw)
	return Transform3D(Basis(x, dir, x.cross(dir).normalized()), p)


func _yaw_to_center(local: Vector2) -> float:
	# face the rocket (local -Z of the object points at the pad centre)
	return atan2(-local.x, -local.y) + PI


func _static(parent: Node3D, shape: Shape3D, pos: Vector3, layer := 4) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = layer
	body.collision_mask = 0
	var col := CollisionShape3D.new()
	col.shape = shape
	body.add_child(col)
	body.position = pos
	parent.add_child(body)
	return body


func _interactable(parent: Node3D, radius: float, height: float, pos: Vector3, prompt: String, what: String) -> void:
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	var body := _static(parent, shape, pos, 8)
	body.set_meta("prompt", prompt)
	body.set_meta("action", func() -> void: interact_requested.emit(what))


func _label(parent: Node3D, text: String, pos: Vector3, size: float, color: Color, billboard := false) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = UiTheme.font_bold()
	l.font_size = 96
	l.pixel_size = 0.004 * size
	l.modulate = color
	l.outline_size = 22
	l.outline_modulate = C_INK
	l.position = pos
	l.double_sided = false
	if billboard:
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	parent.add_child(l)
	return l


# ------------------------------------------------------------------ pieces

func _build_pad() -> void:
	var node := Node3D.new()
	node.name = "Pad"
	add_child(node)
	node.global_transform = _spot(Vector2.ZERO, 0.0, false)
	var kit := MeshKit.new()
	kit.tube(Vector3(0, -0.5, 0), Vector3(0, 0.06, 0), 3.3, 3.2, Color("#565074"), 28)
	kit.tube(Vector3(0, 0.06, 0), Vector3(0, 0.1, 0), 3.0, 2.95, Color("#6e6792"), 28)
	for i in 12:
		var a := TAU * float(i) / 12.0
		kit.rbox(Transform3D(Basis.from_euler(Vector3(0, -a, 0)), Vector3(cos(a) * 3.05, 0.09, sin(a) * 3.05)), Vector3(0.5, 0.06, 0.22), C_YELLOW if i % 2 == 0 else C_INK, 0.5)
	kit.set_emission(1.3)
	for i in 6:
		var a2 := TAU * float(i) / 6.0 + 0.26
		kit.sphere(Vector3(cos(a2) * 2.6, 0.12, sin(a2) * 2.6), 0.09, Color("#8ffcff"), Vector3(1, 0.5, 1), 8, 4)
	kit.set_emission(0.0)
	node.add_child(kit.instance())
	var shape := CylinderShape3D.new()
	shape.radius = 3.25
	shape.height = 0.6
	_static(node, shape, Vector3(0, -0.2, 0))


func _build_rocket(local: Vector2) -> void:
	_rocket = Node3D.new()
	_rocket.name = "Rocket"
	add_child(_rocket)
	var t := _spot(local, 0.6, false)
	t.origin += t.basis.y * 0.1
	_rocket.global_transform = t
	var kit := MeshKit.new()
	# engine + body + nose
	kit.tube(Vector3(0, 0.25, 0), Vector3(0, 0.95, 0), 0.95, 0.62, Color("#57526f"), 16)
	kit.tube(Vector3(0, 0.9, 0), Vector3(0, 1.7, 0), 0.9, 1.28, C_WHITE, 18)
	kit.tube(Vector3(0, 1.7, 0), Vector3(0, 4.9, 0), 1.28, 1.2, C_WHITE, 18)
	kit.tube(Vector3(0, 4.9, 0), Vector3(0, 6.3, 0), 1.2, 0.7, C_RED, 18)
	kit.sphere(Vector3(0, 6.3, 0), 0.7, C_RED, Vector3(1, 1.25, 1), 16, 8)
	kit.tube(Vector3(0, 7.0, 0), Vector3(0, 7.9, 0), 0.07, 0.03, C_STEEL, 6)
	kit.set_emission(2.0)
	kit.sphere(Vector3(0, 7.95, 0), 0.12, C_YELLOW, Vector3.ONE, 8, 5)
	kit.set_emission(0.0)
	# stripes
	kit.torus(Transform3D(Basis.IDENTITY, Vector3(0, 4.85, 0)), 1.2, 0.09, C_YELLOW, 22, 6)
	kit.torus(Transform3D(Basis.IDENTITY, Vector3(0, 1.75, 0)), 1.28, 0.09, C_RED, 22, 6)
	# fins + feet
	for i in 3:
		var a := TAU * float(i) / 3.0 + 0.5
		var out := Vector3(cos(a), 0, sin(a))
		var b := Basis(out, Vector3.UP, out.cross(Vector3.UP).normalized())
		kit.rbox(Transform3D(b, out * 1.5 + Vector3(0, 1.35, 0)), Vector3(1.3, 2.3, 0.22), C_RED, 0.45)
		kit.rbox(Transform3D(b, out * 2.0 + Vector3(0, 0.35, 0)), Vector3(0.55, 0.7, 0.3), C_RED.darkened(0.15), 0.5)
		kit.sphere(out * 2.05 + Vector3(0, 0.05, 0), 0.3, Color("#57526f"), Vector3(1, 0.45, 1), 10, 5)
	# porthole + door (facing local +Z)
	kit.torus(Transform3D(Basis.from_euler(Vector3(PI * 0.5, 0, 0)), Vector3(0, 3.9, 1.2)), 0.45, 0.1, C_YELLOW, 18, 6)
	kit.set_emission(0.9)
	kit.sphere(Vector3(0, 3.9, 1.12), 0.42, Color("#7fe6ff"), Vector3(1, 1, 0.35), 14, 7)
	kit.set_emission(0.0)
	kit.rbox(Transform3D(Basis.IDENTITY, Vector3(0, 2.3, 1.2)), Vector3(0.8, 1.3, 0.2), Color("#d9d2ee"), 0.4)
	kit.sphere(Vector3(0.25, 2.3, 1.32), 0.06, C_YELLOW, Vector3.ONE, 6, 4)
	# ramp
	kit.rbox(Transform3D(Basis.from_euler(Vector3(0.42, 0, 0)), Vector3(0, 1.05, 2.1)), Vector3(0.9, 0.12, 2.3), C_STEEL, 0.35)
	_rocket.add_child(kit.instance())
	var shape := CapsuleShape3D.new()
	shape.radius = 1.35
	shape.height = 7.0
	_static(_rocket, shape, Vector3(0, 3.5, 0))
	_interactable(_rocket, 2.6, 5.0, Vector3(0, 2.5, 0), "Rocket - choose a planet", "rocket")
	var light := OmniLight3D.new()
	light.light_color = Color("#7fe6ff")
	light.light_energy = 0.35
	light.omni_range = 7.0
	light.position = Vector3(0, 3.9, 2.0)
	_rocket.add_child(light)


func _build_sell_station(local: Vector2) -> void:
	var node := Node3D.new()
	node.name = "SellStation"
	add_child(node)
	node.global_transform = _spot(local, _yaw_to_center(local))
	var kit := MeshKit.new()
	# machine body
	kit.rbox(Transform3D(Basis.IDENTITY, Vector3(0, 0.75, 0)), Vector3(2.1, 1.5, 1.7), C_TEAL, 0.35)
	kit.rbox(Transform3D(Basis.IDENTITY, Vector3(0, 0.2, 0)), Vector3(2.3, 0.4, 1.9), C_INK, 0.4)
	kit.rbox(Transform3D(Basis.IDENTITY, Vector3(0, 1.0, -0.86)), Vector3(1.5, 0.75, 0.12), C_INK, 0.4)
	# chute where credits come out
	kit.rbox(Transform3D(Basis.from_euler(Vector3(-0.5, 0, 0)), Vector3(0.7, 0.55, -0.95)), Vector3(0.45, 0.1, 0.5), C_YELLOW, 0.4)
	# smokestack with ring
	kit.tube(Vector3(-0.75, 1.5, 0.45), Vector3(-0.75, 2.5, 0.45), 0.18, 0.15, C_STEEL, 10)
	kit.torus(Transform3D(Basis.IDENTITY, Vector3(-0.75, 2.5, 0.45)), 0.17, 0.05, C_RED, 12, 6)
	# big coin sign
	kit.tube(Vector3(0.85, 1.5, 0.5), Vector3(0.85, 2.7, 0.5), 0.07, 0.07, C_STEEL, 8)
	kit.set_emission(0.5)
	kit.tube(Vector3(0.85, 3.1, 0.42), Vector3(0.85, 3.1, 0.58), 0.48, 0.48, C_YELLOW, 20)
	kit.set_emission(0.0)
	kit.torus(Transform3D(Basis.from_euler(Vector3(PI * 0.5, 0, 0)), Vector3(0.85, 3.1, 0.5)), 0.48, 0.06, C_ORANGE, 20, 6)
	node.add_child(kit.instance())
	# hopper (bounces when fed)
	hopper_node = Node3D.new()
	hopper_node.name = "Hopper"
	hopper_node.position = Vector3(0, 1.5, 0)
	node.add_child(hopper_node)
	var hk := MeshKit.new()
	hk.tube(Vector3(0, 0, 0), Vector3(0, 0.95, 0), 0.5, 1.15, C_ORANGE, 16, false)
	hk.torus(Transform3D(Basis.IDENTITY, Vector3(0, 0.95, 0)), 1.15, 0.1, C_YELLOW, 20, 6)
	hk.tube(Vector3(0, -0.02, 0), Vector3(0, 0.05, 0), 0.52, 0.5, C_INK, 16)
	hopper_node.add_child(hk.instance())
	_label(node, "$", Vector3(0.85, 3.1, 0.6), 2.0, C_INK)
	_label(node, "$", Vector3(0.85, 3.1, 0.4), 2.0, C_INK).rotation.y = PI
	_label(node, "SELL-O-MATIC", Vector3(0, 1.22, -0.93), 0.85, C_YELLOW).rotation.y = PI
	sell_display = _label(node, "Step on the pad!", Vector3(0, 0.84, -0.93), 0.6, Color("#8ffcff"))
	sell_display.rotation.y = PI
	var box := BoxShape3D.new()
	box.size = Vector3(2.1, 2.4, 1.7)
	_static(node, box, Vector3(0, 1.2, 0))

	# the sell pad in front of the machine (towards the rocket)
	var pad := Node3D.new()
	pad.name = "SellPad"
	node.add_child(pad)
	pad.position = Vector3(0, 0.0, -2.3)
	var pk := MeshKit.new()
	pk.tube(Vector3(0, -0.2, 0), Vector3(0, 0.07, 0), 1.45, 1.4, C_INK, 22)
	pk.set_emission(1.0)
	pk.tube(Vector3(0, 0.07, 0), Vector3(0, 0.1, 0), 1.2, 1.18, Color("#7be36b"), 22)
	pk.set_emission(0.0)
	pk.torus(Transform3D(Basis.IDENTITY, Vector3(0, 0.08, 0)), 1.33, 0.07, C_YELLOW, 24, 6)
	pad.add_child(pk.instance())
	var pshape := CylinderShape3D.new()
	pshape.radius = 1.45
	pshape.height = 0.3
	_static(pad, pshape, Vector3(0, -0.07, 0))
	sell_pad_center = pad.global_position


func _build_kiosk(local: Vector2, what: String, title: String, main: Color, accent: Color) -> void:
	var node := Node3D.new()
	node.name = "Kiosk_" + what
	add_child(node)
	node.global_transform = _spot(local, _yaw_to_center(local))
	var kit := MeshKit.new()
	# counter
	kit.rbox(Transform3D(Basis.IDENTITY, Vector3(0, 0.55, 0)), Vector3(2.4, 1.1, 0.9), main, 0.35)
	kit.rbox(Transform3D(Basis.IDENTITY, Vector3(0, 1.13, -0.05)), Vector3(2.6, 0.14, 1.1), C_WHITE, 0.4)
	kit.rbox(Transform3D(Basis.IDENTITY, Vector3(0, 0.12, 0)), Vector3(2.5, 0.24, 1.0), C_INK, 0.4)
	# posts
	for sx: float in [-1.0, 1.0]:
		kit.tube(Vector3(1.15 * sx, 1.1, 0.3), Vector3(1.15 * sx, 2.75, 0.3), 0.07, 0.07, C_WOOD, 8)
	# striped awning
	for i in 6:
		var x := -1.25 + 0.5 * float(i)
		kit.rbox(Transform3D(Basis.from_euler(Vector3(0.32, 0, 0)), Vector3(x, 2.8, -0.15)), Vector3(0.52, 0.12, 1.6), accent if i % 2 == 0 else C_WHITE, 0.4)
		kit.sphere(Vector3(x, 2.5, -0.92), 0.26, accent if i % 2 == 0 else C_WHITE, Vector3(1, 0.6, 0.4), 8, 4)
	# sign board
	kit.rbox(Transform3D(Basis.IDENTITY, Vector3(0, 3.35, 0.25)), Vector3(1.9, 0.6, 0.14), C_INK, 0.4)
	# display pedestal on the counter
	kit.tube(Vector3(0, 1.2, -0.05), Vector3(0, 1.32, -0.05), 0.42, 0.36, accent, 14)
	kit.set_emission(1.0)
	kit.torus(Transform3D(Basis.IDENTITY, Vector3(0, 1.33, -0.05)), 0.36, 0.03, Color("#8ffcff"), 16, 5)
	kit.set_emission(0.0)
	node.add_child(kit.instance())
	_label(node, title, Vector3(0, 3.35, 0.17), 1.5, accent).rotation.y = PI
	_label(node, title, Vector3(0, 3.35, 0.33), 1.5, accent)
	var box := BoxShape3D.new()
	box.size = Vector3(2.4, 1.3, 0.9)
	_static(node, box, Vector3(0, 0.65, 0))
	_interactable(node, 1.9, 2.6, Vector3(0, 1.2, -0.4), "Open %s Shop" % title.capitalize(), what)
	var holder := Node3D.new()
	holder.name = "Display"
	holder.position = Vector3(0, 1.95, -0.05)
	node.add_child(holder)
	if what == "tools":
		_tool_display = holder
	else:
		_gear_display = holder
	var light := OmniLight3D.new()
	light.light_color = accent.lightened(0.4)
	light.light_energy = 0.3
	light.omni_range = 5.0
	light.position = Vector3(0, 2.3, -0.9)
	node.add_child(light)


func _build_dock(local: Vector2) -> void:
	var node := Node3D.new()
	node.name = "BotDock"
	add_child(node)
	node.global_transform = _spot(local, _yaw_to_center(local))
	var kit := MeshKit.new()
	kit.tube(Vector3(0, -0.2, 0), Vector3(0, 0.14, 0), 1.2, 1.1, C_PURPLE, 6)
	kit.tube(Vector3(0, 0.14, 0), Vector3(0, 0.2, 0), 0.85, 0.8, C_INK, 6)
	kit.tube(Vector3(0.95, 0.1, 0.0), Vector3(0.95, 1.9, 0.0), 0.05, 0.04, C_STEEL, 6)
	kit.set_emission(1.6)
	kit.sphere(Vector3(0.95, 1.95, 0), 0.1, C_PINK, Vector3.ONE, 8, 5)
	kit.torus(Transform3D(Basis.IDENTITY, Vector3(0, 0.21, 0)), 0.6, 0.035, Color("#8ffcff"), 18, 5)
	kit.set_emission(0.0)
	node.add_child(kit.instance())
	var shape := CylinderShape3D.new()
	shape.radius = 1.15
	shape.height = 0.4
	_static(node, shape, Vector3(0, -0.05, 0))
	dock_position = node.global_position + node.global_basis.y * 1.6


func _build_sign(local: Vector2) -> void:
	var node := Node3D.new()
	node.name = "Sign"
	add_child(node)
	node.global_transform = _spot(local, _yaw_to_center(local))
	var kit := MeshKit.new()
	kit.tube(Vector3(0, 0, 0), Vector3(0, 1.9, 0), 0.07, 0.06, C_WOOD, 8)
	kit.rbox(Transform3D(Basis.from_euler(Vector3(0, 0, 0.04)), Vector3(0, 1.75, 0)), Vector3(2.1, 0.62, 0.1), C_WOOD.lightened(0.15), 0.4)
	kit.rbox(Transform3D(Basis.from_euler(Vector3(0, 0, -0.05)), Vector3(0.1, 1.15, 0)), Vector3(1.5, 0.36, 0.1), C_WOOD.lightened(0.05), 0.4)
	node.add_child(kit.instance())
	var title := str(planet.config.get("name", "Planet")).to_upper()
	for side: float in [-1.0, 1.0]:
		var l := _label(node, title, Vector3(0, 1.75, 0.06 * side), 1.25, C_WHITE)
		l.rotation = Vector3(0, 0.0 if side > 0 else PI, 0.04 * side)
		var l2 := _label(node, "pop. 1 (you)", Vector3(0.1, 1.15, 0.06 * side), 0.6, C_YELLOW)
		l2.rotation = Vector3(0, 0.0 if side > 0 else PI, -0.05 * side)


func _build_lamp(local: Vector2) -> void:
	var node := Node3D.new()
	add_child(node)
	node.global_transform = _spot(local, 0.0)
	var kit := MeshKit.new()
	kit.tube(Vector3(0, 0, 0), Vector3(0, 2.3, 0), 0.07, 0.05, C_INK, 8)
	kit.sphere(Vector3(0, 0.05, 0), 0.2, C_INK, Vector3(1, 0.5, 1), 8, 4)
	kit.set_emission(1.3)
	kit.sphere(Vector3(0, 2.45, 0), 0.22, Color("#fff0b0"), Vector3.ONE, 10, 6)
	kit.set_emission(0.0)
	kit.torus(Transform3D(Basis.IDENTITY, Vector3(0, 2.3, 0)), 0.14, 0.04, C_YELLOW, 10, 5)
	node.add_child(kit.instance())
	var light := OmniLight3D.new()
	light.light_color = Color("#ffe3a0")
	light.light_energy = 0.3
	light.omni_range = 6.5
	light.omni_attenuation = 1.3
	light.position = Vector3(0, 2.5, 0)
	node.add_child(light)


# ------------------------------------------------------------------ displays

func _refresh_displays() -> void:
	if _tool_display != null:
		for c in _tool_display.get_children():
			c.queue_free()
		# show the most exciting thing you can't yet afford... or the best thing you own
		var show_family := ""
		var show_tier := 0
		for fam in GameData.tool_families:
			var next := GameState.next_tier_def(fam["id"])
			if not next.is_empty():
				show_family = fam["id"]
				show_tier = GameState.tier_of(fam["id"]) + 1
				break
		if show_family == "":
			show_family = "shovel"
			show_tier = GameState.tier_of("shovel")
		var m := ToolModels.build(show_family, show_tier, {}, false)
		var root: Node3D = m["root"]
		root.scale = Vector3.ONE * 1.7
		root.rotation = Vector3(-0.5, 0, 0)
		root.position = Vector3(0, 0, 0.35)
		_tool_display.add_child(root)
	if _gear_display != null:
		for c in _gear_display.get_children():
			c.queue_free()
		_gear_display.add_child(_gear_model())


## A chunky backpack that grows with the backpack level (the gear shop's mascot item).
func _gear_model() -> Node3D:
	var lvl := GameState.gear_level("backpack")
	var s := 0.75 + 0.07 * float(lvl)
	var kit := MeshKit.new()
	kit.rbox(Transform3D(Basis.IDENTITY, Vector3(0, 0, 0)), Vector3(0.7, 0.8, 0.45) * s, C_PINK, 0.45)
	kit.rbox(Transform3D(Basis.IDENTITY, Vector3(0, -0.12 * s, 0.24 * s)), Vector3(0.5, 0.36, 0.14) * s, C_YELLOW, 0.5)
	kit.rbox(Transform3D(Basis.IDENTITY, Vector3(0, 0.3 * s, 0.0)), Vector3(0.74, 0.26, 0.5) * s, C_PURPLE, 0.5)
	kit.torus(Transform3D(Basis.from_euler(Vector3(0, 0, PI * 0.5)), Vector3(0, 0.46 * s, 0)), 0.12 * s, 0.03 * s, C_INK, 10, 5)
	for sx: float in [-1.0, 1.0]:
		kit.tube(Vector3(0.22 * sx * s, 0.3 * s, -0.24 * s), Vector3(0.22 * sx * s, -0.3 * s, -0.24 * s), 0.05 * s, 0.05 * s, C_INK, 6)
	return kit.instance()


# ------------------------------------------------------------------ selling

func hopper_position() -> Vector3:
	return hopper_node.global_position + hopper_node.global_basis.y * 0.9


func _process(delta: float) -> void:
	_display_spin += delta
	if _tool_display != null:
		_tool_display.rotation.y = _display_spin * 0.9
		_tool_display.position.y = 1.95 + sin(_display_spin * 1.6) * 0.06
	if _gear_display != null:
		_gear_display.rotation.y = -_display_spin * 0.9
		_gear_display.position.y = 1.85 + sin(_display_spin * 1.6 + 1.0) * 0.06
	_hopper_bounce = lerpf(_hopper_bounce, 0.0, clampf(delta * 9.0, 0.0, 1.0))
	if hopper_node != null:
		hopper_node.scale = Vector3(1.0 + _hopper_bounce * 0.12, 1.0 - _hopper_bounce * 0.16, 1.0 + _hopper_bounce * 0.12)
	_sell_cooldown = maxf(0.0, _sell_cooldown - delta)
	if world == null or world.player == null:
		return
	var p := world.player.global_position
	var on_pad := p.distance_to(sell_pad_center) < 1.7
	if on_pad and _sell_cooldown <= 0.0 and GameState.inventory_count() > 0:
		sell_now()
	_player_on_pad = on_pad


## Sells the player's whole backpack with a shower of chunks into the hopper.
func sell_now() -> int:
	var before := GameState.inventory.duplicate()
	var result := GameState.sell_all()
	var total := int(result["total"])
	if total <= 0:
		return 0
	_sell_cooldown = 0.8
	var from := world.player.global_position + world.player.up * 1.1
	var n := 0
	for mat_id: String in before:
		var mat := GameData.mat_index(mat_id)
		var chunks := clampi(int(ceil(float(before[mat_id]) / 6.0)), 1, 5)
		for i in chunks:
			_fly_chunk(mat, from, 0.05 * float(n))
			n += 1
	feed_hopper(total, 0.35 + 0.05 * float(n))
	sale_completed.emit(total)
	return total


func _fly_chunk(mat: int, from: Vector3, delay: float) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var mi := MeshInstance3D.new()
	mi.mesh = world.pickups._mesh_for(mat)
	mi.material_override = MeshKit.material()
	mi.scale = Vector3.ONE * 0.26
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(mi)
	mi.global_position = from
	var to := hopper_position()
	var up := planet.up_at(to)
	var mid := (from + to) * 0.5 + up * 2.2
	var tw := create_tween()
	tw.tween_interval(delay)
	tw.tween_method(func(t: float) -> void:
		var a := from.lerp(mid, t)
		var b := mid.lerp(to, t)
		mi.global_position = a.lerp(b, t)
		mi.rotation += Vector3(0.2, 0.3, 0.1), 0.0, 1.0, 0.42)
	tw.tween_callback(func() -> void:
		_hopper_bounce = 1.0
		Audio.play_at("hopper", to, -6.0, 1.0, 0.15)
		mi.queue_free())


## Coins-and-numbers feedback at the machine. Also used when helper bots deliver cargo.
func feed_hopper(total: int, delay := 0.0) -> void:
	sell_display.text = "+%s" % GameData.format_money(total)
	if DisplayServer.get_name() == "headless":
		return
	var tw := create_tween()
	tw.tween_interval(delay)
	tw.tween_callback(func() -> void:
		var pos := hopper_position()
		var up := planet.up_at(pos)
		_hopper_bounce = 1.0
		world.fx.sparks(pos + up * 0.4, up, Color("#ffd23f"), 26)
		world.fx.floating_text(pos + up * 1.3, "+%s" % GameData.format_money(total), UiTheme.YELLOW, 1.6, 1.6, 1.5)
		Audio.play_at("sell", pos, 2.0, 1.0, 0.03))
