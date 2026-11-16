class_name RocketBase
extends Node3D
## The home base at the landing site, built as a compact survey outpost: the lander (planet
## travel), the Depot (walk onto its pad to sell everything), a Workshop (tool shop) and an
## Outfitter (gear shop) with physical displays of the next thing you can buy, and a helper-bot
## dock. A few extra installations appear as the player progresses, so the base grows with them.
##
## Visual language (docs/ART_DIRECTION.md, "Industrial architecture"): off-white painted
## modules on dark plinths, graphite vents and frames, one amber belt line, teal only for
## screens and status lights, hexagonal concrete pads underfoot.

signal interact_requested(what: String)     ## "tools", "gear", "rocket"
signal sale_completed(total: int)

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
var _progress: Node3D
var _tool_shop: Node3D
var _gear_shop: Node3D
var _dock: Node3D
var _progress_key := ""
var _pad_glow: ShaderMaterial


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
	_build_depot(Vector2(5.4, 1.6))
	_tool_shop = _build_workshop(Vector2(-4.8, 3.5))
	_gear_shop = _build_outfitter(Vector2(-5.4, -2.7))
	_dock = _build_dock(Vector2(3.5, -4.8))
	_build_sign(Vector2(1.3, 6.3))
	for lp: Vector2 in [Vector2(6.6, -2.0), Vector2(-1.4, -6.4), Vector2(-7.0, 0.5), Vector2(2.9, 4.2)]:
		_build_lamp(lp)
	_progress = Node3D.new()
	_progress.name = "Progress"
	add_child(_progress)
	GameState.tools_changed.connect(_refresh_displays)
	GameState.gear_changed.connect(func(_id: String) -> void: _refresh_displays())
	GameState.discovery_made.connect(func(_id: String) -> void: _refresh_progress())
	_refresh_displays()


## Where a newly arrived player stands, and what they look at: a few steps in front of the
## outpost with the lander, Workshop and Depot all in view. Returns [position, look direction].
func arrival() -> Array:
	var stand := _spot(Vector2(2.6, 11.5))
	var centre := origin + geo.landing_dir * 1.6
	return [stand.origin + stand.basis.y * 0.15, centre - stand.origin]


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


## Flat printed lettering on a panel (no outline, no glow). `emissive` is for screens.
func _label(parent: Node3D, text: String, pos: Vector3, size: float, color: Color, emissive := false) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = UiTheme.font_bold()
	l.font_size = 96
	l.pixel_size = 0.0036 * size
	l.modulate = color
	l.outline_size = 0
	l.position = pos
	l.double_sided = false
	l.shaded = not emissive
	l.alpha_cut = Label3D.ALPHA_CUT_OPAQUE_PREPASS
	parent.add_child(l)
	return l


## A hexagonal concrete pad with a chamfered edge, sunk a little into the ground.
static func _hex_pad(kit: MeshKit, radius: float, top := 0.08, depth := 0.6, color := Pal.CONCRETE) -> void:
	kit.matte()
	var prof := PackedVector2Array([Vector2(radius, -depth), Vector2(radius, top - 0.05), Vector2(radius - 0.05, top), Vector2(0.0, top)])
	kit.lathe(prof, Transform3D(Basis.from_euler(Vector3(0, PI / 6.0, 0)), Vector3.ZERO), color, 6, false, true)


## The shared body of every station: painted module on a dark plinth with one amber belt line.
static func _module(kit: MeshKit, center: Vector3, size: Vector3, belt_y := 0.42) -> void:
	kit.rubber()
	kit.block(Vector3(center.x, 0.09, center.z), Vector3(size.x + 0.12, 0.26, size.z + 0.12), Pal.GRAPHITE, 0.03)
	kit.paint()
	kit.block(center + Vector3(0, 0.12, 0), size - Vector3(0, 0.2, 0), Pal.HULL, 0.07)
	# roof cap
	kit.block(Vector3(center.x, center.y + size.y * 0.5 + 0.04, center.z), Vector3(size.x - 0.2, 0.1, size.z - 0.2), Pal.HULL_SHADE, 0.03)
	# belt line (four thin strips hugging the walls)
	var y := belt_y
	kit.block(Vector3(center.x, y, center.z - size.z * 0.5 - 0.004), Vector3(size.x - 0.1, 0.07, 0.012), Pal.AMBER, 0.003)
	kit.block(Vector3(center.x, y, center.z + size.z * 0.5 + 0.004), Vector3(size.x - 0.1, 0.07, 0.012), Pal.AMBER, 0.003)
	kit.block(Vector3(center.x - size.x * 0.5 - 0.004, y, center.z), Vector3(0.012, 0.07, size.z - 0.1), Pal.AMBER, 0.003)
	kit.block(Vector3(center.x + size.x * 0.5 + 0.004, y, center.z), Vector3(0.012, 0.07, size.z - 0.1), Pal.AMBER, 0.003)


# ------------------------------------------------------------------ pieces

func _build_pad() -> void:
	var node := Node3D.new()
	node.name = "Pad"
	add_child(node)
	node.global_transform = _spot(Vector2.ZERO, 0.0, false)
	var kit := MeshKit.new()
	_hex_pad(kit, 4.0, 0.1, 0.7)
	# expansion joints and the landing ring
	kit.matte()
	for i in 3:
		var b := Basis.from_euler(Vector3(0, PI / 3.0 * float(i), 0))
		kit.block(Vector3(0, 0.101, 0), Vector3(6.6, 0.006, 0.035), Pal.CONCRETE_DARK, 0.001, b)
	kit.paint()
	kit.disc(Transform3D(Basis.IDENTITY, Vector3(0, 0.1, 0)), 2.55, 2.4, 0.006, Pal.AMBER, 40)
	for i in 6:
		var a := PI / 3.0 * float(i) + PI / 6.0
		var b2 := Basis.from_euler(Vector3(0, -a, 0))
		kit.block(Vector3(cos(a), 0, sin(a)) * 3.05 + Vector3(0, 0.103, 0), Vector3(0.5, 0.006, 0.12), Pal.AMBER, 0.001, b2)
	# marker lights at the corners
	kit.surf(0.3)
	for i in 6:
		var a2 := PI / 3.0 * float(i)
		var p := Vector3(cos(a2), 0, sin(a2)) * 3.6
		kit.set_emission(0.0)
		kit.tube(p + Vector3(0, 0.08, 0), p + Vector3(0, 0.15, 0), 0.07, 0.06, Pal.GRAPHITE, 8)
		kit.set_emission(1.6)
		kit.tube(p + Vector3(0, 0.15, 0), p + Vector3(0, 0.17, 0), 0.045, 0.04, Pal.TEAL, 8)
	kit.set_emission(0.0)
	node.add_child(kit.instance())
	var shape := CylinderShape3D.new()
	shape.radius = 3.6
	shape.height = 0.7
	_static(node, shape, Vector3(0, -0.25, 0))


func _build_rocket(local: Vector2) -> void:
	_rocket = Node3D.new()
	_rocket.name = "Rocket"
	add_child(_rocket)
	var t := _spot(local, 0.6, false)
	t.origin += t.basis.y * 0.1
	_rocket.global_transform = t
	var kit := MeshKit.new()
	# engine section and bell
	kit.cast()
	kit.lathe(PackedVector2Array([Vector2(0.0, 0.42), Vector2(0.82, 0.38), Vector2(0.7, 0.62), Vector2(0.5, 1.0), Vector2(0.56, 1.1)]), Transform3D.IDENTITY, Pal.GRAPHITE, 20, true)
	kit.paint()
	kit.lathe(PackedVector2Array([Vector2(0.56, 1.05), Vector2(1.02, 1.25), Vector2(1.2, 1.75)]), Transform3D.IDENTITY, Pal.GRAPHITE, 24, true)
	# hull
	kit.lathe(PackedVector2Array([Vector2(1.2, 1.75), Vector2(1.3, 2.4), Vector2(1.3, 5.1), Vector2(1.2, 5.8), Vector2(0.98, 6.5), Vector2(0.66, 7.1)]), Transform3D.IDENTITY, Pal.HULL, 28, true)
	kit.lathe(PackedVector2Array([Vector2(0.66, 7.1), Vector2(0.36, 7.5), Vector2(0.12, 7.68), Vector2(0.0, 7.7)]), Transform3D.IDENTITY, Pal.GRAPHITE, 20, true)
	# belt lines and panel seams
	kit.lathe(PackedVector2Array([Vector2(1.308, 4.72), Vector2(1.308, 4.9)]), Transform3D.IDENTITY, Pal.AMBER, 28)
	kit.lathe(PackedVector2Array([Vector2(1.306, 2.42), Vector2(1.306, 2.5)]), Transform3D.IDENTITY, Pal.GRAPHITE, 28)
	kit.lathe(PackedVector2Array([Vector2(1.304, 3.58), Vector2(1.304, 3.6)]), Transform3D.IDENTITY, Pal.HULL_SHADE.darkened(0.25), 28)
	kit.lathe(PackedVector2Array([Vector2(1.304, 5.1), Vector2(1.304, 5.12)]), Transform3D.IDENTITY, Pal.HULL_SHADE.darkened(0.25), 28)
	# antenna
	kit.bare()
	kit.tube(Vector3(0, 7.65, 0), Vector3(0, 8.5, 0), 0.025, 0.012, Pal.STEEL, 6)
	kit.set_emission(1.8)
	kit.sphere(Vector3(0, 8.53, 0), 0.05, Pal.TEAL, Vector3.ONE, 8, 5)
	kit.set_emission(0.0)
	# three landing legs: fairing, strut, foot
	for i in 3:
		var a := TAU * float(i) / 3.0 + 0.5
		var out := Vector3(cos(a), 0, sin(a))
		var b := Basis(out, Vector3.UP, out.cross(Vector3.UP).normalized())
		kit.paint()
		kit.hbox(Transform3D(b * Basis.from_euler(Vector3(0, 0, -0.2)), out * 1.42 + Vector3(0, 2.25, 0)), Vector3(0.42, 1.5, 0.36), Pal.HULL_SHADE, 0.06)
		kit.bare()
		kit.tube(out * 1.5 + Vector3(0, 1.75, 0), out * 2.5 + Vector3(0, 0.24, 0), 0.085, 0.07, Pal.STEEL, 8)
		kit.tube(out * 1.05 + Vector3(0, 1.3, 0), out * 2.42 + Vector3(0, 0.3, 0), 0.05, 0.05, Pal.STEEL_DARK, 6)
		kit.rubber()
		kit.disc(Transform3D(Basis.IDENTITY, out * 2.52 + Vector3(0, 0.02, 0)), 0.34, 0.0, 0.14, Pal.GRAPHITE, 14)
	# porthole and hatch (facing local +Z)
	kit.cast()
	kit.torus(Transform3D(Basis.from_euler(Vector3(PI * 0.5, 0, 0)), Vector3(0, 4.1, 1.27)), 0.36, 0.06, Pal.GRAPHITE, 20, 6)
	kit.gloss()
	kit.set_emission(0.35)
	kit.sphere(Vector3(0, 4.1, 1.2), 0.34, Pal.GLASS, Vector3(1, 1, 0.3), 14, 7)
	kit.set_emission(0.0)
	kit.paint()
	kit.block(Vector3(0, 2.85, 1.27), Vector3(0.92, 1.42, 0.12), Pal.GRAPHITE, 0.04)
	kit.block(Vector3(0, 2.85, 1.31), Vector3(0.78, 1.28, 0.08), Pal.HULL_SHADE, 0.03)
	kit.block(Vector3(0.26, 2.85, 1.36), Vector3(0.06, 0.26, 0.04), Pal.AMBER, 0.012)
	# ramp with side rails
	var ramp := Basis.from_euler(Vector3(0.42, 0, 0))
	kit.cast()
	kit.hbox(Transform3D(ramp, Vector3(0, 1.16, 2.25)), Vector3(0.9, 0.07, 2.5), Pal.STEEL_DARK, 0.015)
	for sx: float in [-1.0, 1.0]:
		kit.hbox(Transform3D(ramp, Vector3(0.47 * sx, 1.2, 2.25)), Vector3(0.05, 0.14, 2.5), Pal.GRAPHITE, 0.012)
	# vents either side of the hatch
	for sx2: float in [-1.0, 1.0]:
		var va := sx2 * 0.62
		var vb := Basis.from_euler(Vector3(0, va, 0))
		kit.louvre(Transform3D(vb, vb * Vector3(0, 3.0, 1.3)), Vector3(0.36, 0.5, 0.05), 5, Pal.CHARCOAL, Pal.GRAPHITE)
	_rocket.add_child(kit.instance())
	_label(_rocket, "LPB-01", Vector3(0.0, 5.36, 1.3), 0.4, Pal.GRAPHITE).rotation.x = -0.1
	var shape := CapsuleShape3D.new()
	shape.radius = 1.35
	shape.height = 7.4
	_static(_rocket, shape, Vector3(0, 3.7, 0))
	_interactable(_rocket, 2.7, 5.0, Vector3(0, 2.5, 0), "Lander - choose a destination", "rocket")


func _build_depot(local: Vector2) -> void:
	var node := Node3D.new()
	node.name = "SellStation"
	add_child(node)
	node.global_transform = _spot(local, _yaw_to_center(local))
	var kit := MeshKit.new()
	_hex_pad(kit, 2.1, 0.03, 0.5)
	_module(kit, Vector3(0, 0.82, 0.1), Vector3(2.3, 1.6, 1.6), 0.5)
	# status screen recess on the front
	kit.rubber()
	kit.block(Vector3(0, 1.05, -0.71), Vector3(1.56, 0.74, 0.06), Pal.CHARCOAL, 0.02)
	# output tray
	kit.cast()
	kit.hbox(Transform3D(Basis.from_euler(Vector3(-0.45, 0, 0)), Vector3(0.82, 0.5, -0.86)), Vector3(0.4, 0.05, 0.42), Pal.STEEL_DARK, 0.012)
	# side vents and exhaust stack
	kit.louvre(Transform3D(Basis.from_euler(Vector3(0, PI * 0.5, 0)), Vector3(1.155, 1.1, 0.1)), Vector3(0.9, 0.5, 0.05), 6, Pal.CHARCOAL, Pal.GRAPHITE)
	kit.louvre(Transform3D(Basis.from_euler(Vector3(0, -PI * 0.5, 0)), Vector3(-1.155, 1.1, 0.1)), Vector3(0.9, 0.5, 0.05), 6, Pal.CHARCOAL, Pal.GRAPHITE)
	kit.bare()
	kit.tube(Vector3(-0.82, 1.6, 0.62), Vector3(-0.82, 2.55, 0.62), 0.11, 0.11, Pal.STEEL, 12)
	kit.cast()
	kit.tube(Vector3(-0.82, 2.5, 0.62), Vector3(-0.82, 2.66, 0.62), 0.14, 0.14, Pal.GRAPHITE, 12)
	# sign mast
	kit.bare()
	kit.tube(Vector3(0.9, 1.6, 0.62), Vector3(0.9, 2.75, 0.62), 0.045, 0.045, Pal.STEEL_DARK, 8)
	kit.paint()
	kit.block(Vector3(0.9, 3.05, 0.62), Vector3(0.95, 0.56, 0.08), Pal.GRAPHITE, 0.03)
	node.add_child(kit.instance())
	# hopper (dips when fed)
	hopper_node = Node3D.new()
	hopper_node.name = "Hopper"
	hopper_node.position = Vector3(0, 1.7, 0.1)
	node.add_child(hopper_node)
	var hk := MeshKit.new().cast()
	hk.lathe(PackedVector2Array([Vector2(0.4, 0.0), Vector2(0.46, 0.12), Vector2(0.95, 0.72), Vector2(0.95, 0.84)]), Transform3D.IDENTITY, Pal.GRAPHITE, 8, false, true)
	hk.lathe(PackedVector2Array([Vector2(0.88, 0.84), Vector2(0.88, 0.7), Vector2(0.4, 0.1), Vector2(0.0, 0.1)]), Transform3D.IDENTITY, Pal.CHARCOAL, 8, false, true)
	hk.paint()
	hk.lathe(PackedVector2Array([Vector2(0.97, 0.76), Vector2(0.97, 0.86), Vector2(0.88, 0.86)]), Transform3D.IDENTITY, Pal.AMBER, 8, false, true)
	hopper_node.add_child(hk.instance())
	_label(node, "SELL", Vector3(0.9, 3.05, 0.575), 0.95, Pal.AMBER).rotation.y = PI
	_label(node, "SELL", Vector3(0.9, 3.05, 0.665), 0.95, Pal.AMBER)
	_label(node, "DEPOT", Vector3(-0.42, 1.24, -0.745), 0.62, Color(0.75, 0.8, 0.82), true).rotation.y = PI
	sell_display = _label(node, "Step on the pad", Vector3(0, 0.93, -0.745), 0.56, Pal.TEAL, true)
	sell_display.rotation.y = PI
	var box := BoxShape3D.new()
	box.size = Vector3(2.3, 2.4, 1.6)
	_static(node, box, Vector3(0, 1.2, 0.1))

	# the sell pad in front of the machine (towards the rocket)
	var pad := Node3D.new()
	pad.name = "SellPad"
	node.add_child(pad)
	pad.position = Vector3(0, 0.0, -2.4)
	var pk := MeshKit.new()
	_hex_pad(pk, 1.55, 0.07, 0.4, Pal.CONCRETE_DARK)
	pk.paint()
	for i in 3:
		# chevrons pointing at the machine
		var z := -0.55 + 0.42 * float(i)
		for sx: float in [-1.0, 1.0]:
			pk.hbox(Transform3D(Basis.from_euler(Vector3(0, sx * 0.6, 0)), Vector3(0.2 * sx, 0.072, z)), Vector3(0.46, 0.006, 0.09), Pal.AMBER, 0.001)
	pad.add_child(pk.instance())
	var glow := MeshKit.new().surf(0.4)
	glow.set_emission(1.0)
	glow.lathe(PackedVector2Array([Vector2(1.42, 0.07), Vector2(1.42, 0.085), Vector2(1.32, 0.085), Vector2(1.32, 0.07)]), Transform3D(Basis.from_euler(Vector3(0, PI / 6.0, 0)), Vector3.ZERO), Pal.GREEN, 6, false, true)
	_pad_glow = MeshKit.new_material(1.0)
	pad.add_child(glow.instance(_pad_glow, false))
	var pshape := CylinderShape3D.new()
	pshape.radius = 1.4
	pshape.height = 0.3
	_static(pad, pshape, Vector3(0, -0.07, 0))
	sell_pad_center = pad.global_position


## The tool shop: a service-window module with a steel counter, a flat canopy and a lit
## turntable that shows the next tool you can buy.
func _build_workshop(local: Vector2) -> Node3D:
	var node := Node3D.new()
	node.name = "Kiosk_tools"
	add_child(node)
	node.global_transform = _spot(local, _yaw_to_center(local))
	var kit := MeshKit.new()
	_hex_pad(kit, 2.6, 0.03, 0.5)
	_module(kit, Vector3(0, 1.3, 0.45), Vector3(3.0, 2.6, 1.5), 0.5)
	# service window: dark recess with a pegboard back
	kit.rubber()
	kit.block(Vector3(0, 1.72, -0.31), Vector3(2.3, 1.12, 0.06), Pal.CHARCOAL, 0.02)
	kit.paint()
	kit.block(Vector3(0, 1.72, -0.285), Vector3(2.16, 0.98, 0.03), Pal.GRAPHITE, 0.01)
	# tools hanging on the pegboard (flat silhouettes: spade, pick, wrench)
	kit.bare()
	kit.block(Vector3(-0.8, 1.78, -0.31), Vector3(0.05, 0.62, 0.03), Pal.STEEL_DARK, 0.008)
	kit.block(Vector3(-0.8, 1.42, -0.31), Vector3(0.2, 0.22, 0.03), Pal.STEEL, 0.02)
	kit.block(Vector3(0.82, 1.76, -0.31), Vector3(0.05, 0.6, 0.03), Pal.WOOD, 0.008)
	kit.hbox(Transform3D(Basis.from_euler(Vector3(0, 0, 0.25)), Vector3(0.82, 2.04, -0.31)), Vector3(0.46, 0.07, 0.03), Pal.STEEL, 0.012)
	kit.block(Vector3(0.48, 1.7, -0.31), Vector3(0.05, 0.46, 0.03), Pal.STEEL, 0.008)
	kit.torus(Transform3D(Basis.from_euler(Vector3(PI * 0.5, 0, 0)), Vector3(0.48, 1.98, -0.31)), 0.07, 0.022, Pal.STEEL, 10, 5)
	# counter: steel top on brackets
	kit.bare()
	kit.block(Vector3(0, 1.1, -0.62), Vector3(2.5, 0.07, 0.72), Pal.STEEL, 0.015)
	kit.paint()
	kit.block(Vector3(0, 0.62, -0.42), Vector3(2.4, 0.9, 0.3), Pal.HULL_SHADE, 0.04)
	for sx: float in [-1.0, 1.0]:
		kit.prism(PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.5, 0.0), Vector2(0.0, -0.4)]), -0.03, 0.03,
			Transform3D(Basis.from_euler(Vector3(0, PI * 0.5, 0)), Vector3(1.05 * sx, 1.06, -0.52)), Pal.GRAPHITE)
	# canopy: a flat plate with an amber leading edge on two struts
	var cb := Basis.from_euler(Vector3(0.08, 0, 0))
	kit.paint()
	kit.hbox(Transform3D(cb, Vector3(0, 2.72, -0.72)), Vector3(3.1, 0.07, 1.5), Pal.HULL, 0.02)
	kit.hbox(Transform3D(cb, Vector3(0, 2.66, -1.46)), Vector3(3.1, 0.1, 0.06), Pal.AMBER, 0.012)
	kit.bare()
	for sx2: float in [-1.0, 1.0]:
		kit.tube(Vector3(1.4 * sx2, 2.2, -0.3), Vector3(1.4 * sx2, 2.63, -1.3), 0.025, 0.025, Pal.STEEL_DARK, 6)
	# sign board on the roof
	kit.paint()
	kit.block(Vector3(0, 3.02, 0.2), Vector3(1.9, 0.5, 0.1), Pal.GRAPHITE, 0.03)
	kit.bare()
	for sx3: float in [-1.0, 1.0]:
		kit.tube(Vector3(0.7 * sx3, 2.62, 0.2), Vector3(0.7 * sx3, 2.8, 0.2), 0.03, 0.03, Pal.STEEL_DARK, 6)
	# side details: vent, glazing strip
	kit.louvre(Transform3D(Basis.from_euler(Vector3(0, PI * 0.5, 0)), Vector3(1.505, 1.9, 0.45)), Vector3(0.8, 0.44, 0.05), 5, Pal.CHARCOAL, Pal.GRAPHITE)
	kit.gloss()
	kit.block(Vector3(-1.505, 1.5, 0.45), Vector3(0.03, 1.5, 0.3), Pal.GLASS, 0.008)
	# turntable on the counter
	kit.cast()
	kit.disc(Transform3D(Basis.IDENTITY, Vector3(0, 1.135, -0.66)), 0.36, 0.0, 0.05, Pal.GRAPHITE, 20)
	kit.surf(0.3).set_emission(1.3)
	kit.disc(Transform3D(Basis.IDENTITY, Vector3(0, 1.185, -0.66)), 0.3, 0.27, 0.006, Pal.TEAL, 24)
	kit.set_emission(0.0)
	node.add_child(kit.instance())
	_label(node, "TOOLS", Vector3(0, 3.02, 0.145), 1.15, Pal.HULL).rotation.y = PI
	_label(node, "TOOLS", Vector3(0, 3.02, 0.255), 1.15, Pal.HULL)
	var box := BoxShape3D.new()
	box.size = Vector3(3.0, 2.7, 1.5)
	_static(node, box, Vector3(0, 1.35, 0.45))
	var cbox := BoxShape3D.new()
	cbox.size = Vector3(2.5, 1.1, 0.7)
	_static(node, cbox, Vector3(0, 0.55, -0.6))
	_interactable(node, 2.0, 2.6, Vector3(0, 1.3, -0.7), "Workshop - buy and upgrade tools", "tools")
	_tool_display = Node3D.new()
	_tool_display.name = "Display"
	_tool_display.position = Vector3(0, 1.75, -0.66)
	node.add_child(_tool_display)
	var spot := SpotLight3D.new()
	spot.light_color = Pal.LAMP_WARM
	spot.light_energy = 2.2
	spot.spot_range = 3.2
	spot.spot_angle = 38.0
	spot.shadow_enabled = false
	spot.position = Vector3(0, 2.6, -0.9)
	spot.rotation = Vector3(-PI * 0.5 + 0.2, 0, 0)
	node.add_child(spot)
	return node


## The gear shop: a locker wall with a glass display case for the backpack.
func _build_outfitter(local: Vector2) -> Node3D:
	var node := Node3D.new()
	node.name = "Kiosk_gear"
	add_child(node)
	node.global_transform = _spot(local, _yaw_to_center(local))
	var kit := MeshKit.new()
	_hex_pad(kit, 2.4, 0.03, 0.5)
	_module(kit, Vector3(0, 1.25, 0.4), Vector3(3.0, 2.5, 1.3), 0.34)
	# lockers left and right of the display case
	for sx: float in [-1.0, 1.0]:
		for k in 2:
			var x := sx * (0.78 + 0.5 * float(k))
			kit.paint()
			kit.block(Vector3(x, 1.38, -0.262), Vector3(0.46, 1.7, 0.05), Pal.GRAPHITE, 0.015)
			kit.block(Vector3(x, 1.38, -0.285), Vector3(0.38, 1.6, 0.04), Pal.HULL_SHADE, 0.012)
			kit.louvre(Transform3D(Basis.from_euler(Vector3(0, PI, 0)), Vector3(x, 1.92, -0.31)), Vector3(0.24, 0.16, 0.025), 4, Pal.CHARCOAL, Pal.GRAPHITE)
			kit.bare()
			kit.block(Vector3(x + 0.12 * sx, 1.3, -0.315), Vector3(0.03, 0.16, 0.03), Pal.STEEL, 0.008)
			kit.surf(0.3).set_emission(1.4)
			kit.block(Vector3(x, 2.1, -0.31), Vector3(0.05, 0.025, 0.02), Pal.TEAL, 0.004)
			kit.set_emission(0.0)
	# display case: plinth, frame and glass
	kit.paint()
	kit.block(Vector3(0, 0.55, -0.5), Vector3(0.96, 0.96, 0.7), Pal.HULL_SHADE, 0.04)
	kit.block(Vector3(0, 1.05, -0.5), Vector3(1.02, 0.06, 0.76), Pal.GRAPHITE, 0.015)
	kit.block(Vector3(0, 2.26, -0.5), Vector3(1.02, 0.08, 0.76), Pal.GRAPHITE, 0.015)
	kit.bare()
	for sx2: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			kit.block(Vector3(0.48 * sx2, 1.65, -0.5 + 0.35 * sz), Vector3(0.035, 1.16, 0.035), Pal.STEEL_DARK, 0.008)
	# sign board
	kit.paint()
	kit.block(Vector3(0, 2.92, 0.2), Vector3(1.7, 0.5, 0.1), Pal.GRAPHITE, 0.03)
	kit.bare()
	for sx3: float in [-1.0, 1.0]:
		kit.tube(Vector3(0.6 * sx3, 2.52, 0.2), Vector3(0.6 * sx3, 2.7, 0.2), 0.03, 0.03, Pal.STEEL_DARK, 6)
	kit.louvre(Transform3D(Basis.from_euler(Vector3(0, -PI * 0.5, 0)), Vector3(-1.505, 1.9, 0.4)), Vector3(0.7, 0.44, 0.05), 5, Pal.CHARCOAL, Pal.GRAPHITE)
	node.add_child(kit.instance())
	_label(node, "GEAR", Vector3(0, 2.92, 0.145), 1.15, Pal.HULL).rotation.y = PI
	_label(node, "GEAR", Vector3(0, 2.92, 0.255), 1.15, Pal.HULL)
	var box := BoxShape3D.new()
	box.size = Vector3(3.0, 2.6, 1.3)
	_static(node, box, Vector3(0, 1.3, 0.4))
	var cbox := BoxShape3D.new()
	cbox.size = Vector3(1.0, 2.3, 0.75)
	_static(node, cbox, Vector3(0, 1.15, -0.5))
	_interactable(node, 2.0, 2.6, Vector3(0, 1.3, -0.6), "Outfitter - upgrade your gear", "gear")
	_gear_display = Node3D.new()
	_gear_display.name = "Display"
	_gear_display.position = Vector3(0, 1.62, -0.5)
	node.add_child(_gear_display)
	var spot := SpotLight3D.new()
	spot.light_color = Pal.LAMP_COOL
	spot.light_energy = 1.6
	spot.spot_range = 2.4
	spot.spot_angle = 40.0
	spot.shadow_enabled = false
	spot.position = Vector3(0, 2.2, -0.5)
	spot.rotation = Vector3(-PI * 0.5, 0, 0)
	node.add_child(spot)
	return node


func _build_dock(local: Vector2) -> Node3D:
	var node := Node3D.new()
	node.name = "BotDock"
	add_child(node)
	node.global_transform = _spot(local, _yaw_to_center(local))
	var kit := MeshKit.new()
	_hex_pad(kit, 1.3, 0.1, 0.5, Pal.CONCRETE_DARK)
	kit.cast()
	kit.disc(Transform3D(Basis.IDENTITY, Vector3(0, 0.1, 0)), 0.8, 0.0, 0.05, Pal.GRAPHITE, 6, true)
	kit.surf(0.3).set_emission(1.2)
	kit.disc(Transform3D(Basis.IDENTITY, Vector3(0, 0.15, 0)), 0.62, 0.57, 0.006, Pal.TEAL, 24)
	kit.set_emission(0.0)
	# mast with a status light and two charging arms
	kit.bare()
	kit.tube(Vector3(0.98, 0.1, 0.0), Vector3(0.98, 1.9, 0.0), 0.04, 0.035, Pal.STEEL_DARK, 6)
	kit.paint()
	kit.block(Vector3(0.98, 1.98, 0), Vector3(0.14, 0.16, 0.14), Pal.GRAPHITE, 0.02)
	kit.block(Vector3(0.8, 1.0, 0), Vector3(0.36, 0.05, 0.05), Pal.HULL_SHADE, 0.012)
	kit.surf(0.3).set_emission(1.6)
	kit.block(Vector3(0.9, 1.98, 0), Vector3(0.03, 0.08, 0.08), Pal.TEAL, 0.006)
	kit.set_emission(0.0)
	node.add_child(kit.instance())
	var shape := CylinderShape3D.new()
	shape.radius = 1.15
	shape.height = 0.4
	_static(node, shape, Vector3(0, -0.05, 0))
	dock_position = node.global_position + node.global_basis.y * 1.6
	return node


func _build_sign(local: Vector2) -> void:
	var node := Node3D.new()
	node.name = "Sign"
	add_child(node)
	node.global_transform = _spot(local, _yaw_to_center(local))
	var kit := MeshKit.new().bare()
	for sx: float in [-1.0, 1.0]:
		kit.tube(Vector3(0.8 * sx, -0.2, 0), Vector3(0.8 * sx, 1.72, 0), 0.035, 0.035, Pal.STEEL_DARK, 6)
	kit.paint()
	kit.block(Vector3(0, 1.4, 0), Vector3(2.0, 0.7, 0.06), Pal.HULL, 0.02)
	kit.block(Vector3(0, 1.09, 0), Vector3(2.0, 0.06, 0.066), Pal.AMBER, 0.01)
	node.add_child(kit.instance())
	var title := str(planet.config.get("name", "Planet")).to_upper()
	var site := "SURVEY SITE %02d" % (int(planet.config.get("order", 0)) + 1)
	for side: float in [-1.0, 1.0]:
		var l := _label(node, title, Vector3(0, 1.5, 0.034 * side), 0.95, Pal.GRAPHITE)
		l.rotation = Vector3(0, 0.0 if side > 0 else PI, 0)
		var l2 := _label(node, site, Vector3(0, 1.24, 0.034 * side), 0.4, Pal.STEEL_DARK)
		l2.rotation = Vector3(0, 0.0 if side > 0 else PI, 0)


func _build_lamp(local: Vector2) -> void:
	var node := Node3D.new()
	add_child(node)
	node.global_transform = _spot(local, _yaw_to_center(local))
	var kit := MeshKit.new().cast()
	kit.disc(Transform3D(Basis.IDENTITY, Vector3(0, -0.05, 0)), 0.16, 0.0, 0.1, Pal.GRAPHITE, 8)
	kit.tube(Vector3(0, 0, 0), Vector3(0, 2.7, 0), 0.04, 0.03, Pal.GRAPHITE, 8)
	kit.tube(Vector3(0, 2.68, 0), Vector3(0, 2.76, -0.42), 0.022, 0.022, Pal.GRAPHITE, 6)
	kit.paint()
	kit.block(Vector3(0, 2.76, -0.5), Vector3(0.16, 0.05, 0.36), Pal.HULL_SHADE, 0.012)
	kit.surf(0.4).set_emission(2.4)
	kit.block(Vector3(0, 2.732, -0.5), Vector3(0.11, 0.012, 0.3), Pal.LAMP_WARM, 0.002)
	kit.set_emission(0.0)
	node.add_child(kit.instance())
	var light := OmniLight3D.new()
	light.light_color = Pal.LAMP_WARM
	light.light_energy = 0.5
	light.omni_range = 7.0
	light.omni_attenuation = 1.4
	light.shadow_enabled = false
	light.position = Vector3(0, 2.55, -0.5)
	node.add_child(light)


# ------------------------------------------------------------------ displays

func _refresh_displays() -> void:
	if _tool_display != null:
		for c in _tool_display.get_children():
			c.queue_free()
		# show the next thing you can work towards... or the best thing you own
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
		root.scale = Vector3.ONE * 1.25
		root.rotation = Vector3(-0.45, 0, 0)
		root.position = Vector3(0, 0, 0.3)
		_tool_display.add_child(root)
	if _gear_display != null:
		for c in _gear_display.get_children():
			c.queue_free()
		_gear_display.add_child(gear_model(GameState.gear_level("backpack")))
	_refresh_progress()


## A field pack that gains pouches and a frame as the backpack is upgraded (the gear shop's
## showcase item).
static func gear_model(level: int) -> Node3D:
	var s := 0.62 + 0.04 * float(level)
	var kit := MeshKit.new().matte()
	kit.block(Vector3(0, 0, 0), Vector3(0.56, 0.72, 0.34) * s, Pal.HULL_SHADE, 0.07 * s)
	kit.block(Vector3(0, 0.3 * s, 0.0), Vector3(0.6, 0.2, 0.38) * s, Pal.GRAPHITE, 0.05 * s)
	kit.block(Vector3(0, -0.12 * s, 0.19 * s), Vector3(0.4, 0.3, 0.1) * s, Pal.GRAPHITE, 0.03 * s)
	kit.paint()
	kit.block(Vector3(0, 0.12 * s, 0.172 * s), Vector3(0.5, 0.05, 0.02) * s, Pal.AMBER, 0.006)
	kit.rubber()
	for sx: float in [-1.0, 1.0]:
		kit.tube(Vector3(0.18 * sx * s, 0.3 * s, -0.18 * s), Vector3(0.18 * sx * s, -0.3 * s, -0.18 * s), 0.035 * s, 0.035 * s, Pal.RUBBER, 6)
	if level >= 2:
		for sx2: float in [-1.0, 1.0]:
			kit.matte()
			kit.block(Vector3(0.33 * sx2 * s, -0.1 * s, 0.0), Vector3(0.12, 0.34, 0.24) * s, Pal.HULL_SHADE.darkened(0.08), 0.03 * s)
	if level >= 4:
		kit.bare()
		for sx3: float in [-1.0, 1.0]:
			kit.tube(Vector3(0.3 * sx3 * s, -0.42 * s, -0.12 * s), Vector3(0.3 * sx3 * s, 0.5 * s, -0.12 * s), 0.018 * s, 0.018 * s, Pal.STEEL, 6)
		kit.tube(Vector3(-0.3 * s, 0.5 * s, -0.12 * s), Vector3(0.3 * s, 0.5 * s, -0.12 * s), 0.018 * s, 0.018 * s, Pal.STEEL, 6)
	if level >= 6:
		kit.surf(0.3).set_emission(1.5)
		kit.block(Vector3(0, 0.3 * s, 0.195 * s), Vector3(0.2, 0.05, 0.01) * s, Pal.TEAL, 0.004)
		kit.set_emission(0.0)
	return kit.instance()


## Installations that appear as the player progresses, so the outpost visibly grows:
## cargo crates (backpack level), a solar array (first powered tool), a survey dish (scanner),
## a charging pylon light (helper bots) and a pennant once the planet's heart is found.
func _refresh_progress() -> void:
	if _progress == null:
		return
	var crates := clampi(GameState.gear_level("backpack"), 0, 6)
	var powered := GameState.tier_of("shovel") >= 3 or GameState.owns_family("drill") or GameState.owns_family("vacuum")
	var dish := GameState.gear_level("scanner") > 0
	var bots := GameState.gear_level("robot") > 0
	var heart := GameState.has_discovery(str((planet.config.get("core", {}) as Dictionary).get("discovery", "")))
	var key := "%d|%s|%s|%s|%s" % [crates, powered, dish, bots, heart]
	if key == _progress_key:
		return
	_progress_key = key
	for c in _progress.get_children():
		c.queue_free()
	if crates > 0:
		var node := Node3D.new()
		_progress.add_child(node)
		node.global_transform = _spot(Vector2(-7.4, -4.6), 0.4)
		var kit := MeshKit.new()
		var slots := [Vector3(0, 0.3, 0), Vector3(0.72, 0.3, 0.1), Vector3(0.3, 0.9, 0.05), Vector3(-0.2, 0.3, 0.75), Vector3(1.42, 0.3, -0.1), Vector3(0.9, 0.9, 0.0)]
		for i in crates:
			var p: Vector3 = slots[i]
			var b := Basis.from_euler(Vector3(0, 0.25 * float(i % 3) - 0.2, 0))
			kit.paint()
			kit.hbox(Transform3D(b, p), Vector3(0.6, 0.58, 0.6), Pal.HULL_SHADE if i % 2 == 0 else Pal.HULL, 0.03)
			kit.hbox(Transform3D(b, p + Vector3(0, 0.2, 0)), Vector3(0.615, 0.06, 0.615), Pal.AMBER if i % 3 == 0 else Pal.GRAPHITE, 0.01)
			kit.hbox(Transform3D(b, p + Vector3(0, -0.24, 0)), Vector3(0.62, 0.1, 0.62), Pal.GRAPHITE, 0.015)
		node.add_child(kit.instance())
	if powered:
		var node2 := Node3D.new()
		_progress.add_child(node2)
		node2.global_transform = _spot(Vector2(7.8, -4.6), -0.6)
		var kit2 := MeshKit.new()
		_hex_pad(kit2, 1.5, 0.05, 0.4, Pal.CONCRETE_DARK)
		for i in 2:
			var x := -0.75 + 1.5 * float(i)
			kit2.bare()
			kit2.tube(Vector3(x, 0.05, 0), Vector3(x, 0.95, 0), 0.05, 0.04, Pal.STEEL_DARK, 6)
			var pb := Basis.from_euler(Vector3(-0.7, 0, 0))
			kit2.paint()
			kit2.hbox(Transform3D(pb, Vector3(x, 1.02, 0)), Vector3(1.3, 0.05, 0.95), Pal.HULL, 0.012)
			kit2.gloss()
			kit2.hbox(Transform3D(pb, Vector3(x, 1.046, 0.0)), Vector3(1.2, 0.012, 0.86), Pal.GLASS_DARK, 0.003)
			kit2.paint()
			for g in 3:
				kit2.hbox(Transform3D(pb, Vector3(x - 0.3 + 0.3 * float(g), 1.053, 0.0)), Vector3(0.012, 0.004, 0.86), Pal.STEEL_DARK, 0.001)
		kit2.rubber()
		kit2.pipe(PackedVector3Array([Vector3(-0.75, 0.1, 0.0), Vector3(-0.75, 0.08, 0.6), Vector3(0.75, 0.08, 0.6), Vector3(0.75, 0.1, 0.0)]), 0.025, Pal.RUBBER, 6)
		node2.add_child(kit2.instance())
	if dish and _tool_shop != null:
		var kit3 := MeshKit.new().bare()
		kit3.tube(Vector3(1.1, 2.6, 0.75), Vector3(1.1, 3.25, 0.75), 0.03, 0.03, Pal.STEEL_DARK, 6)
		kit3.paint()
		kit3.lathe(PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.22, 0.03), Vector2(0.4, 0.12), Vector2(0.42, 0.12)]),
			Transform3D(Basis.from_euler(Vector3(0.9, 0.5, 0)), Vector3(1.1, 3.25, 0.75)), Pal.HULL, 18, true)
		kit3.surf(0.3).set_emission(1.6)
		kit3.sphere(Vector3(1.1, 3.25, 0.75) + Basis.from_euler(Vector3(0.9, 0.5, 0)) * Vector3(0, 0.26, 0), 0.03, Pal.TEAL, Vector3.ONE, 6, 4)
		var mi := kit3.instance()
		_progress.add_child(mi)
		mi.global_transform = _tool_shop.global_transform
	if bots and _dock != null:
		var light := OmniLight3D.new()
		light.light_color = Pal.TEAL
		light.light_energy = 0.5
		light.omni_range = 4.0
		_progress.add_child(light)
		light.global_position = _dock.global_position + _dock.global_basis.y * 1.2
	if heart and _rocket != null:
		var kit4 := MeshKit.new().matte()
		var core: Dictionary = planet.config.get("core", {})
		kit4.prism(PackedVector2Array([Vector2(0, 0), Vector2(0.7, -0.14), Vector2(0, -0.3)]), -0.006, 0.006,
			Transform3D(Basis.IDENTITY, Vector3(0.02, 8.45, 0)), Color(str(core.get("color", "#f0a22e"))))
		var mi2 := kit4.instance(MeshKit.material(), false)
		_progress.add_child(mi2)
		mi2.global_transform = _rocket.global_transform


# ------------------------------------------------------------------ selling

func hopper_position() -> Vector3:
	return hopper_node.global_position + hopper_node.global_basis.y * 0.8


func _process(delta: float) -> void:
	_display_spin += delta
	if _tool_display != null:
		_tool_display.rotation.y = _display_spin * 0.6
		_tool_display.position.y = 1.75 + sin(_display_spin * 1.2) * 0.03
	if _gear_display != null:
		_gear_display.rotation.y = -_display_spin * 0.5
	_hopper_bounce = lerpf(_hopper_bounce, 0.0, clampf(delta * 9.0, 0.0, 1.0))
	if hopper_node != null:
		hopper_node.position.y = 1.7 - _hopper_bounce * 0.07
		hopper_node.scale = Vector3(1.0 + _hopper_bounce * 0.03, 1.0 - _hopper_bounce * 0.05, 1.0 + _hopper_bounce * 0.03)
	_sell_cooldown = maxf(0.0, _sell_cooldown - delta)
	if world == null or world.player == null:
		return
	var p := world.player.global_position
	var on_pad := p.distance_to(sell_pad_center) < 1.7
	if on_pad and _sell_cooldown <= 0.0 and GameState.inventory_count() > 0:
		sell_now()
	_player_on_pad = on_pad
	if _pad_glow != null:
		# the pad's edge light breathes gently and brightens while you carry something to sell
		var want := 1.6 if GameState.inventory_count() > 0 else 0.7
		_pad_glow.set_shader_parameter("emission_scale", want + sin(_display_spin * 2.4) * 0.25)


## Sells the player's whole backpack with a stream of chunks into the hopper.
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


## Payout feedback at the machine. Also used when helper bots deliver cargo.
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
		world.fx.sparks(pos + up * 0.3, up, Pal.AMBER, 12)
		world.fx.floating_text(pos + up * 1.2, "+%s" % GameData.format_money(total), UiTheme.YELLOW, 1.4, 1.2, 1.5)
		Audio.play_at("sell", pos, 2.0, 1.0, 0.03))
