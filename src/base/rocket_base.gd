class_name RocketBase
extends Node3D
## The home base at the landing site, built as a compact survey outpost: the lander (planet
## travel), the Depot (walk onto its pad to sell everything), a Workshop (tool shop) and an
## Outfitter (gear shop) with physical displays of the next thing you can buy, and a helper-bot
## dock. A few extra installations appear as the player progresses, so the base grows with them.
##
## Visual language (docs/ART_DIRECTION.md, "Outpost architecture"): round enamelled drums on
## stepped stone plinths, bronze rib rings and crowns, glazed cream dials and sign plates,
## exposed copper lines, jade only on things you use, ion blue only for screens and lights.

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
	_build_depot(Vector2(6.3, 1.8))
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
	var stand := _spot(Vector2(2.8, 12.6))
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


## A round, stepped stone plinth (two cut courses) sunk a little into the ground.
static func _plinth(kit: MeshKit, radius: float, top := 0.08, depth := 0.6, color := Pal.CONCRETE) -> void:
	kit.matte()
	var prof := PackedVector2Array([Vector2(radius, -depth), Vector2(radius, top * 0.45), Vector2(radius - 0.06, top * 0.5),
		Vector2(radius - 0.16, top * 0.55), Vector2(radius - 0.16, top - 0.03), Vector2(radius - 0.2, top), Vector2(0.0, top)])
	kit.lathe(prof, Transform3D.IDENTITY, color, 24, false, true)


## The shared body of every station: an enamelled drum on a bronze foot ring, held by raised
## bronze ribs (no painted stripes), with a glazed cream label band and a low domed cap.
## Returns the drum's top height.
static func _drum(kit: MeshKit, center: Vector3, radius: float, height: float, sides := 20) -> float:
	var y0 := center.y
	kit.cast()
	kit.lathe(PackedVector2Array([Vector2(radius + 0.12, y0), Vector2(radius + 0.12, y0 + 0.16), Vector2(radius + 0.04, y0 + 0.22), Vector2(radius, y0 + 0.22)]),
		Transform3D(Basis.IDENTITY, Vector3(center.x, 0, center.z)), Pal.BRONZE, sides, false, true)
	kit.paint()
	kit.lathe(PackedVector2Array([Vector2(radius, y0 + 0.2), Vector2(radius, y0 + height)]),
		Transform3D(Basis.IDENTITY, Vector3(center.x, 0, center.z)), Pal.ENAMEL, sides, false, true)
	# ribs
	for f: float in [0.34, 0.86]:
		var ry := y0 + height * f
		kit.cast()
		kit.lathe(PackedVector2Array([Vector2(radius, ry - 0.05), Vector2(radius + 0.045, ry - 0.03), Vector2(radius + 0.045, ry + 0.03), Vector2(radius, ry + 0.05)]),
			Transform3D(Basis.IDENTITY, Vector3(center.x, 0, center.z)), Pal.BRONZE, sides, false, true)
	# glazed label band between the ribs
	kit.gloss()
	kit.lathe(PackedVector2Array([Vector2(radius + 0.012, y0 + height * 0.62), Vector2(radius + 0.012, y0 + height * 0.76)]),
		Transform3D(Basis.IDENTITY, Vector3(center.x, 0, center.z)), Pal.CREAM, sides, false, true)
	# domed cap with a bronze crown ring
	kit.paint()
	var top := y0 + height
	kit.lathe(PackedVector2Array([Vector2(radius + 0.03, top), Vector2(radius + 0.03, top + 0.06), Vector2(radius * 0.86, top + 0.2), Vector2(radius * 0.5, top + 0.3), Vector2(0.0, top + 0.33)]),
		Transform3D(Basis.IDENTITY, Vector3(center.x, 0, center.z)), Pal.ENAMEL_SHADE, sides, true)
	kit.cast()
	kit.disc(Transform3D(Basis.IDENTITY, Vector3(center.x, top + 0.3, center.z)), 0.16, 0.0, 0.08, Pal.BRONZE, 12)
	return top + 0.33


## A round perforated grille (instrument-style vent): a bronze bezel with a grid of dark holes.
static func _grille(kit: MeshKit, xform: Transform3D, radius: float) -> void:
	kit.cast()
	kit.disc(xform, radius, radius * 0.86, 0.025, Pal.BRONZE, 18)
	kit.rubber()
	var n := 3
	var step := radius * 0.5
	for ix in range(-n, n + 1):
		for iz in range(-n, n + 1):
			var p := Vector2(ix, iz) * step * 0.55
			if p.length() < radius * 0.74:
				kit.disc(xform * Transform3D(Basis.IDENTITY, Vector3(p.x, 0.0, p.y)), radius * 0.09, 0.0, 0.012, Pal.DEEP, 6)


## A pressure dial: bronze bezel, cream face, one needle. Faces local +Y.
static func _dial(kit: MeshKit, xform: Transform3D, radius: float, needle := 0.6) -> void:
	kit.cast()
	kit.disc(xform, radius, 0.0, 0.03, Pal.BRONZE, 16)
	kit.gloss()
	kit.disc(xform * Transform3D(Basis.IDENTITY, Vector3(0, 0.03, 0)), radius * 0.82, 0.0, 0.006, Pal.CREAM, 16)
	kit.paint()
	kit.hbox(xform * Transform3D(Basis.from_euler(Vector3(0, needle, 0)), Vector3(0, 0.038, 0) + Basis.from_euler(Vector3(0, needle, 0)) * Vector3(radius * 0.3, 0, 0)), Vector3(radius * 0.62, 0.004, radius * 0.07), Pal.DEEP, 0.001)


# ------------------------------------------------------------------ pieces

func _build_pad() -> void:
	var node := Node3D.new()
	node.name = "Pad"
	add_child(node)
	node.global_transform = _spot(Vector2.ZERO, 0.0, false)
	var kit := MeshKit.new()
	_plinth(kit, 4.0, 0.12, 0.7)
	# radial joints and the jade landing ring
	kit.matte()
	for i in 8:
		var b := Basis.from_euler(Vector3(0, PI / 8.0 * float(i), 0))
		kit.block(b * Vector3(2.2, 0.121, 0), Vector3(3.0, 0.006, 0.03), Pal.CONCRETE_DARK, 0.001, b)
	kit.paint()
	kit.disc(Transform3D(Basis.IDENTITY, Vector3(0, 0.12, 0)), 2.75, 2.62, 0.006, Pal.JADE, 48)
	# marker posts: short bronze bollards with ion caps around the rim
	kit.surf(0.3)
	for i in 8:
		var a2 := TAU * float(i) / 8.0 + PI / 8.0
		var p := Vector3(cos(a2), 0, sin(a2)) * 3.62
		kit.set_emission(0.0)
		kit.turned(p + Vector3(0, 0.1, 0), p + Vector3(0, 0.34, 0), PackedVector2Array([Vector2(0.07, 0.0), Vector2(0.07, 0.18), Vector2(0.05, 0.24)]), Pal.BRONZE, 10, false, true)
		kit.set_emission(1.6)
		kit.sphere(p + Vector3(0, 0.35, 0), 0.04, Pal.ION, Vector3(1, 0.7, 1), 8, 4)
	kit.set_emission(0.0)
	node.add_child(kit.instance())
	var shape := CylinderShape3D.new()
	shape.radius = 3.6
	shape.height = 0.7
	_static(node, shape, Vector3(0, -0.23, 0))


## The lander, "Seedpod": a squat kiln-fired pod on four splayed legs. A glazed upper dome,
## bronze girth rings, copper fuel lines, a porthole and an arched hatch; a survey mast with a
## gimbal ring on top. Deliberately low and round - nothing like a tall white rocket.
func _build_rocket(local: Vector2) -> void:
	_rocket = Node3D.new()
	_rocket.name = "Rocket"
	add_child(_rocket)
	var t := _spot(local, 0.6, false)
	t.origin += t.basis.y * 0.12
	_rocket.global_transform = t
	var kit := MeshKit.new()
	var s := 28
	# thruster skirt and nozzles under the body
	kit.cast()
	kit.lathe(PackedVector2Array([Vector2(0.0, 0.95), Vector2(1.05, 0.95), Vector2(1.35, 1.25), Vector2(1.5, 1.4)]), Transform3D.IDENTITY, Pal.BRONZE, s, false, true)
	for i in 6:
		var a := TAU * float(i) / 6.0
		var p := Vector3(cos(a), 0, sin(a)) * 0.72
		kit.lathe(PackedVector2Array([Vector2(0.0, 0.62), Vector2(0.2, 0.62), Vector2(0.14, 0.82), Vector2(0.1, 0.98)]), Transform3D(Basis.IDENTITY, p), Pal.STEEL_DARK, 12, true)
		kit.rubber()
		kit.disc(Transform3D(Basis.IDENTITY, p + Vector3(0, 0.62, 0)), 0.16, 0.0, 0.01, Pal.DEEP, 12)
		kit.cast()
	# lower body: enamel shade, then the main enamel belly
	kit.paint()
	kit.lathe(PackedVector2Array([Vector2(1.5, 1.38), Vector2(1.85, 1.7), Vector2(2.0, 2.1)]), Transform3D.IDENTITY, Pal.ENAMEL_SHADE, s, true)
	kit.lathe(PackedVector2Array([Vector2(2.0, 2.1), Vector2(2.08, 2.6), Vector2(2.05, 3.3), Vector2(1.95, 3.7)]), Transform3D.IDENTITY, Pal.ENAMEL, s, true)
	# glazed ceramic dome
	kit.gloss()
	kit.lathe(PackedVector2Array([Vector2(1.95, 3.7), Vector2(1.75, 4.25), Vector2(1.35, 4.75), Vector2(0.75, 5.1), Vector2(0.0, 5.22)]), Transform3D.IDENTITY, Pal.CREAM, s, true)
	# bronze girth rings
	for ry: float in [2.1, 3.7]:
		kit.cast()
		kit.torus(Transform3D(Basis.IDENTITY, Vector3(0, ry, 0)), 2.02 if ry < 3.0 else 1.97, 0.06, Pal.BRONZE, 40, 8)
	# copper fuel lines wrapping the belly
	kit.bare()
	for k in 2:
		var a0 := float(k) * PI + 0.9
		var pts := PackedVector3Array()
		for j in 9:
			var a := a0 + 0.22 * float(j)
			pts.append(Vector3(cos(a) * 2.1, 2.45 + 0.09 * float(j), sin(a) * 2.1))
		kit.pipe(pts, 0.045, Pal.COPPER, 7)
	# survey mast and gimbal ring on the dome
	kit.cast()
	kit.turned(Vector3(0, 5.18, 0), Vector3(0, 5.5, 0), PackedVector2Array([Vector2(0.28, 0.0), Vector2(0.28, 0.12), Vector2(0.16, 0.32)]), Pal.BRONZE, 16)
	kit.bare()
	kit.tube(Vector3(0, 5.48, 0), Vector3(0, 6.6, 0), 0.05, 0.035, Pal.STEEL, 8)
	kit.cast()
	kit.torus(Transform3D(Basis.from_euler(Vector3(PI * 0.5, 0.0, 0.0)), Vector3(0, 6.2, 0)), 0.36, 0.028, Pal.BRONZE, 24, 6)
	kit.torus(Transform3D(Basis.from_euler(Vector3(0.0, 0.0, PI * 0.5)), Vector3(0, 6.2, 0)), 0.3, 0.024, Pal.COPPER, 24, 6)
	kit.set_emission(1.8)
	kit.sphere(Vector3(0, 6.66, 0), 0.07, Pal.ION, Vector3.ONE, 10, 6)
	kit.set_emission(0.0)
	# four splayed legs: bronze strut, copper damper, round foot
	for i in 4:
		var a := TAU * float(i) / 4.0 + PI / 4.0
		var out := Vector3(cos(a), 0, sin(a))
		kit.cast()
		kit.tube(out * 1.75 + Vector3(0, 2.3, 0), out * 3.05 + Vector3(0, 0.22, 0), 0.1, 0.08, Pal.BRONZE, 10)
		kit.bare()
		kit.tube(out * 1.45 + Vector3(0, 1.45, 0), out * 2.6 + Vector3(0, 0.62, 0), 0.06, 0.06, Pal.COPPER, 8)
		kit.tube(out * 2.2 + Vector3(0, 1.04, 0), out * 2.8 + Vector3(0, 0.45, 0), 0.035, 0.035, Pal.STEEL, 6)
		kit.rubber()
		kit.turned(out * 3.1 + Vector3(0, 0.0, 0), out * 3.1 + Vector3(0, 0.16, 0), PackedVector2Array([Vector2(0.42, 0.0), Vector2(0.38, 0.1), Vector2(0.14, 0.16)]), Pal.BRONZE, 16, false, true)
	# porthole (local +Z) and an arched hatch below it
	kit.cast()
	kit.torus(Transform3D(Basis.from_euler(Vector3(PI * 0.5, 0, 0)), Vector3(0, 4.15, 1.72)), 0.3, 0.06, Pal.BRONZE, 20, 6)
	kit.gloss()
	kit.set_emission(0.35)
	kit.sphere(Vector3(0, 4.15, 1.66), 0.28, Pal.GLASS, Vector3(1, 1, 0.35), 14, 7)
	kit.set_emission(0.0)
	var arch := PackedVector2Array()
	for j in 9:
		var aa := PI * float(j) / 8.0
		arch.append(Vector2(cos(aa) * 0.48, 0.95 + sin(aa) * 0.42))
	arch.append(Vector2(-0.48, 0.0))
	arch.append(Vector2(0.48, 0.0))
	kit.cast()
	kit.prism(arch, -0.05, 0.05, Transform3D(Basis.IDENTITY, Vector3(0, 2.15, 2.03)), Pal.BRONZE)
	kit.paint()
	var inner := PackedVector2Array()
	for p2 in arch:
		inner.append(p2 * Vector2(0.84, 0.92) + Vector2(0, 0.04))
	kit.prism(inner, 0.04, 0.09, Transform3D(Basis.IDENTITY, Vector3(0, 2.15, 2.03)), Pal.ENAMEL_SHADE)
	kit.paint()
	kit.block(Vector3(0.26, 2.8, 2.13), Vector3(0.05, 0.3, 0.05), Pal.JADE, 0.015)
	# ramp with side rails
	var ramp := Basis.from_euler(Vector3(0.36, 0, 0))
	kit.cast()
	kit.hbox(Transform3D(ramp, Vector3(0, 1.45, 2.95)), Vector3(0.9, 0.07, 2.3), Pal.STEEL_DARK, 0.015)
	for sx: float in [-1.0, 1.0]:
		kit.hbox(Transform3D(ramp, Vector3(0.47 * sx, 1.49, 2.95)), Vector3(0.05, 0.14, 2.3), Pal.BRONZE, 0.012)
	# instrument cluster beside the hatch: two dials and a round grille
	_dial(kit, Transform3D(Basis.from_euler(Vector3(PI * 0.5, 0.0, 0.0)).rotated(Vector3.UP, 0.42), Vector3(0.0, 2.9, 0.0) + Vector3(sin(0.42), 0, cos(0.42)) * 2.07), 0.17, 0.4)
	_dial(kit, Transform3D(Basis.from_euler(Vector3(PI * 0.5, 0.0, 0.0)).rotated(Vector3.UP, 0.58), Vector3(0.0, 2.55, 0.0) + Vector3(sin(0.58), 0, cos(0.58)) * 2.07), 0.12, -0.8)
	_grille(kit, Transform3D(Basis.from_euler(Vector3(PI * 0.5, 0.0, 0.0)).rotated(Vector3.UP, -0.5), Vector3(0.0, 2.75, 0.0) + Vector3(sin(-0.5), 0, cos(-0.5)) * 2.08), 0.26)
	_rocket.add_child(kit.instance())
	var tag := _label(_rocket, "LPB-01", Vector3(0.0, 3.92, 1.9), 0.42, Pal.BRONZE)
	tag.rotation.x = -0.45
	var shape := CapsuleShape3D.new()
	shape.radius = 2.0
	shape.height = 4.6
	_static(_rocket, shape, Vector3(0, 3.1, 0))
	_interactable(_rocket, 3.0, 5.0, Vector3(0, 2.5, 0), "Lander - choose a destination", "rocket")


## The Depot: a squat drum crowned by a funnel hopper and a copper chimney, with a round
## porthole read-out on the front and a round cream sign on a mast.
func _build_depot(local: Vector2) -> void:
	var node := Node3D.new()
	node.name = "SellStation"
	add_child(node)
	node.global_transform = _spot(local, _yaw_to_center(local))
	var kit := MeshKit.new()
	_plinth(kit, 1.9, 0.05, 0.5)
	_drum(kit, Vector3(0, 0.05, 0.1), 1.05, 1.45)
	# porthole read-out on the front (faces -Z, towards the sell pad)
	kit.cast()
	kit.torus(Transform3D(Basis.from_euler(Vector3(PI * 0.5, 0, 0)), Vector3(0, 0.98, -0.97)), 0.42, 0.06, Pal.BRONZE, 24, 6)
	kit.rubber()
	kit.disc(Transform3D(Basis.from_euler(Vector3(-PI * 0.5, 0, 0)), Vector3(0, 0.98, -0.95)), 0.4, 0.0, 0.02, Pal.DEEP, 24)
	# output chute
	kit.cast()
	kit.hbox(Transform3D(Basis.from_euler(Vector3(-0.45, 0, 0)), Vector3(0.75, 0.42, -0.98)), Vector3(0.36, 0.05, 0.4), Pal.STEEL_DARK, 0.012)
	# copper chimney with a domed rain cap
	kit.bare()
	kit.tube(Vector3(-0.7, 1.7, 0.62), Vector3(-0.7, 2.7, 0.62), 0.1, 0.1, Pal.COPPER, 12)
	kit.cast()
	kit.turned(Vector3(-0.7, 2.7, 0.62), Vector3(-0.7, 2.95, 0.62), PackedVector2Array([Vector2(0.2, 0.0), Vector2(0.2, 0.05), Vector2(0.12, 0.2), Vector2(0.0, 0.25)]), Pal.BRONZE, 14, true)
	# sign mast with a round cream sign
	kit.bare()
	kit.tube(Vector3(0.95, 1.6, 0.62), Vector3(0.95, 2.75, 0.62), 0.045, 0.045, Pal.STEEL_DARK, 8)
	kit.cast()
	kit.turned(Vector3(0.95, 3.05, 0.58), Vector3(0.95, 3.05, 0.66), PackedVector2Array([Vector2(0.52, 0.0), Vector2(0.52, 0.08)]), Pal.BRONZE, 24)
	kit.gloss()
	kit.turned(Vector3(0.95, 3.05, 0.575), Vector3(0.95, 3.05, 0.665), PackedVector2Array([Vector2(0.46, 0.0), Vector2(0.46, 0.09)]), Pal.CREAM, 24)
	node.add_child(kit.instance())
	# hopper (dips when fed)
	hopper_node = Node3D.new()
	hopper_node.name = "Hopper"
	hopper_node.position = Vector3(0, 1.7, 0.1)
	node.add_child(hopper_node)
	var hk := MeshKit.new().cast()
	hk.lathe(PackedVector2Array([Vector2(0.4, 0.0), Vector2(0.46, 0.12), Vector2(0.95, 0.72), Vector2(0.95, 0.84)]), Transform3D.IDENTITY, Pal.BRONZE, 20, true)
	hk.lathe(PackedVector2Array([Vector2(0.88, 0.84), Vector2(0.88, 0.7), Vector2(0.4, 0.1), Vector2(0.0, 0.1)]), Transform3D.IDENTITY, Pal.DEEP, 20, true)
	hk.paint()
	hk.torus(Transform3D(Basis.IDENTITY, Vector3(0, 0.85, 0)), 0.93, 0.035, Pal.JADE, 32, 6)
	hopper_node.add_child(hk.instance())
	_label(node, "SELL", Vector3(0.95, 3.05, 0.57), 0.9, Pal.BRONZE).rotation.y = PI
	_label(node, "SELL", Vector3(0.95, 3.05, 0.67), 0.9, Pal.BRONZE)
	_label(node, "DEPOT", Vector3(0, 1.17, -0.96), 0.5, Pal.CREAM, true).rotation.y = PI
	sell_display = _label(node, "Step on the pad", Vector3(0, 0.92, -0.96), 0.44, Pal.ION, true)
	sell_display.rotation.y = PI
	var cyl := CylinderShape3D.new()
	cyl.radius = 1.12
	cyl.height = 2.4
	_static(node, cyl, Vector3(0, 1.2, 0.1))

	# the sell pad in front of the machine (towards the lander)
	var pad := Node3D.new()
	pad.name = "SellPad"
	node.add_child(pad)
	pad.position = Vector3(0, 0.0, -2.4)
	var pk := MeshKit.new()
	_plinth(pk, 1.55, 0.08, 0.4, Pal.CONCRETE_DARK)
	pk.paint()
	for i in 3:
		# arcs pointing at the machine
		var r := 0.45 + 0.32 * float(i)
		var arc := PackedVector2Array()
		for j in 7:
			var aa := -0.6 + 1.2 * float(j) / 6.0
			arc.append(Vector2(sin(aa) * r, -cos(aa) * r))
		for j in 7:
			var aa2 := 0.6 - 1.2 * float(j) / 6.0
			arc.append(Vector2(sin(aa2) * (r - 0.08), -cos(aa2) * (r - 0.08)))
		pk.prism(arc, -0.003, 0.003, Transform3D(Basis.from_euler(Vector3(-PI * 0.5, 0, 0)), Vector3(0, 0.083, -0.75)), Pal.JADE)
	pad.add_child(pk.instance())
	var glow := MeshKit.new().surf(0.4)
	glow.set_emission(1.0)
	glow.lathe(PackedVector2Array([Vector2(1.36, 0.08), Vector2(1.36, 0.095), Vector2(1.27, 0.095), Vector2(1.27, 0.08)]), Transform3D.IDENTITY, Pal.GREEN, 32)
	_pad_glow = MeshKit.new_material(1.0)
	pad.add_child(glow.instance(_pad_glow, false))
	var pshape := CylinderShape3D.new()
	pshape.radius = 1.4
	pshape.height = 0.3
	_static(pad, pshape, Vector3(0, -0.07, 0))
	sell_pad_center = pad.global_position


## The Workshop (tools): a tall drum with a curved service counter wrapped around its front,
## a pegboard of hanging tools inside the opening, a half-disc canopy and a lit turntable that
## shows the next tool you can buy.
func _build_workshop(local: Vector2) -> Node3D:
	var node := Node3D.new()
	node.name = "Kiosk_tools"
	add_child(node)
	node.global_transform = _spot(local, _yaw_to_center(local))
	var kit := MeshKit.new()
	_plinth(kit, 2.5, 0.05, 0.5)
	var top := _drum(kit, Vector3(0, 0.05, 0.55), 1.3, 2.45)
	# the opening: a dark recess with a bronze surround, pegboard inside
	kit.cast()
	kit.hbox(Transform3D(Basis.IDENTITY, Vector3(0, 1.75, -0.66)), Vector3(1.8, 1.16, 0.1), Pal.BRONZE, 0.03)
	kit.rubber()
	kit.hbox(Transform3D(Basis.IDENTITY, Vector3(0, 1.75, -0.7)), Vector3(1.62, 1.0, 0.06), Pal.DEEP, 0.02)
	kit.bare()
	kit.block(Vector3(-0.55, 1.8, -0.74), Vector3(0.05, 0.6, 0.03), Pal.STEEL_DARK, 0.008)
	kit.block(Vector3(-0.55, 1.45, -0.74), Vector3(0.2, 0.22, 0.03), Pal.STEEL, 0.02)
	kit.block(Vector3(0.6, 1.78, -0.74), Vector3(0.05, 0.6, 0.03), Pal.WOOD, 0.008)
	kit.hbox(Transform3D(Basis.from_euler(Vector3(0, 0, 0.25)), Vector3(0.6, 2.05, -0.74)), Vector3(0.44, 0.07, 0.03), Pal.STEEL, 0.012)
	kit.torus(Transform3D(Basis.from_euler(Vector3(PI * 0.5, 0, 0)), Vector3(0.0, 2.02, -0.74)), 0.07, 0.022, Pal.COPPER, 10, 5)
	# curved counter: a half-ring slab on a enamel front skirt
	var outer := PackedVector2Array()
	for j in 13:
		var aa := PI * float(j) / 12.0
		outer.append(Vector2(cos(aa) * 1.45, sin(aa) * 0.85))
	for j in 13:
		var aa2 := PI - PI * float(j) / 12.0
		outer.append(Vector2(cos(aa2) * 1.05, sin(aa2) * 0.45))
	kit.bare()
	kit.prism(outer, 1.06, 1.12, Transform3D(Basis.from_euler(Vector3(-PI * 0.5, 0, 0)), Vector3(0, 0, -0.62)), Pal.STEEL)
	kit.paint()
	var skirt := PackedVector2Array()
	for j in 13:
		var aa3 := PI * float(j) / 12.0
		skirt.append(Vector2(cos(aa3) * 1.38, sin(aa3) * 0.78))
	for j in 13:
		var aa4 := PI - PI * float(j) / 12.0
		skirt.append(Vector2(cos(aa4) * 1.18, sin(aa4) * 0.58))
	kit.prism(skirt, 0.05, 1.06, Transform3D(Basis.from_euler(Vector3(-PI * 0.5, 0, 0)), Vector3(0, 0, -0.62)), Pal.ENAMEL_SHADE)
	# half-disc canopy on two bronze arms
	var canopy := PackedVector2Array()
	for j in 13:
		var aa5 := PI * float(j) / 12.0
		canopy.append(Vector2(cos(aa5) * 1.7, sin(aa5) * 1.15))
	kit.paint()
	kit.prism(canopy, 2.66, 2.72, Transform3D(Basis.from_euler(Vector3(-PI * 0.5, 0, 0)), Vector3(0, 0, -0.4)), Pal.ENAMEL)
	kit.cast()
	for sx2: float in [-1.0, 1.0]:
		kit.tube(Vector3(1.05 * sx2, 2.1, -0.4), Vector3(1.25 * sx2, 2.66, -1.0), 0.03, 0.03, Pal.BRONZE, 6)
	# round sign on the roof
	kit.cast()
	kit.tube(Vector3(0, top - 0.05, 0.55), Vector3(0, top + 0.35, 0.55), 0.04, 0.04, Pal.BRONZE, 6)
	kit.turned(Vector3(0, top + 0.72, 0.5), Vector3(0, top + 0.72, 0.6), PackedVector2Array([Vector2(0.5, 0.0), Vector2(0.5, 0.1)]), Pal.BRONZE, 24)
	kit.gloss()
	kit.turned(Vector3(0, top + 0.72, 0.495), Vector3(0, top + 0.72, 0.605), PackedVector2Array([Vector2(0.44, 0.0), Vector2(0.44, 0.11)]), Pal.CREAM, 24)
	# side grilles and a copper conduit
	_grille(kit, Transform3D(Basis.from_euler(Vector3(0, 0, -PI * 0.5)), Vector3(1.31, 1.6, 0.55)), 0.28)
	kit.bare()
	kit.pipe(PackedVector3Array([Vector3(-1.32, 0.3, 0.9), Vector3(-1.42, 0.6, 0.9), Vector3(-1.42, 2.2, 0.9), Vector3(-1.2, 2.45, 0.9)]), 0.04, Pal.COPPER, 7)
	# turntable on the counter
	kit.cast()
	kit.disc(Transform3D(Basis.IDENTITY, Vector3(0, 1.12, -1.12)), 0.32, 0.0, 0.05, Pal.BRONZE, 20)
	kit.surf(0.3).set_emission(1.3)
	kit.disc(Transform3D(Basis.IDENTITY, Vector3(0, 1.17, -1.12)), 0.27, 0.24, 0.006, Pal.ION, 24)
	kit.set_emission(0.0)
	node.add_child(kit.instance())
	_label(node, "TOOLS", Vector3(0, top + 0.72, 0.49), 0.85, Pal.BRONZE).rotation.y = PI
	_label(node, "TOOLS", Vector3(0, top + 0.72, 0.61), 0.85, Pal.BRONZE)
	var cyl := CylinderShape3D.new()
	cyl.radius = 1.35
	cyl.height = 2.7
	_static(node, cyl, Vector3(0, 1.35, 0.55))
	var cbox := BoxShape3D.new()
	cbox.size = Vector3(2.6, 1.1, 0.6)
	_static(node, cbox, Vector3(0, 0.55, -1.05))
	_interactable(node, 2.0, 2.6, Vector3(0, 1.3, -1.1), "Workshop - buy and upgrade tools", "tools")
	_tool_display = Node3D.new()
	_tool_display.name = "Display"
	_tool_display.position = Vector3(0, 1.75, -1.12)
	node.add_child(_tool_display)
	var spot := SpotLight3D.new()
	spot.light_color = Pal.LAMP_WARM
	spot.light_energy = 2.2
	spot.spot_range = 3.2
	spot.spot_angle = 38.0
	spot.shadow_enabled = false
	spot.position = Vector3(0, 2.6, -1.25)
	spot.rotation = Vector3(-PI * 0.5 + 0.2, 0, 0)
	node.add_child(spot)
	return node


## The Outfitter (gear): a drum flanked by two tall canister lockers, with a glass bell jar on a
## plinth out front that shows the backpack.
func _build_outfitter(local: Vector2) -> Node3D:
	var node := Node3D.new()
	node.name = "Kiosk_gear"
	add_child(node)
	node.global_transform = _spot(local, _yaw_to_center(local))
	var kit := MeshKit.new()
	_plinth(kit, 2.4, 0.05, 0.5)
	var top := _drum(kit, Vector3(0, 0.05, 0.55), 1.15, 2.2)
	# canister lockers either side: tall cylinders with hinged fronts and a status pip
	for sx: float in [-1.0, 1.0]:
		var c := Vector3(1.45 * sx, 0.05, 0.2)
		kit.cast()
		kit.turned(c, c + Vector3(0, 0.18, 0), PackedVector2Array([Vector2(0.42, 0.0), Vector2(0.42, 0.18)]), Pal.BRONZE, 18)
		kit.paint()
		kit.turned(c + Vector3(0, 0.18, 0), c + Vector3(0, 2.0, 0), PackedVector2Array([Vector2(0.38, 0.0), Vector2(0.38, 1.82), Vector2(0.3, 1.9), Vector2(0.0, 1.95)]), Pal.ENAMEL_SHADE, 18, true)
		kit.cast()
		for ry: float in [0.7, 1.5]:
			kit.torus(Transform3D(Basis.IDENTITY, c + Vector3(0, ry, 0)), 0.39, 0.025, Pal.BRONZE, 20, 5)
		kit.bare()
		kit.block(c + Vector3(-0.12 * sx, 1.1, -0.39), Vector3(0.03, 0.2, 0.03), Pal.STEEL, 0.008)
		kit.surf(0.3).set_emission(1.4)
		kit.sphere(c + Vector3(0, 1.85, -0.36), 0.03, Pal.ION, Vector3.ONE, 6, 4)
		kit.set_emission(0.0)
	# bell jar display: plinth, bronze base ring, glass dome
	kit.paint()
	kit.turned(Vector3(0, 0.05, -0.75), Vector3(0, 1.0, -0.75), PackedVector2Array([Vector2(0.5, 0.0), Vector2(0.5, 0.85), Vector2(0.56, 0.9), Vector2(0.56, 0.95)]), Pal.ENAMEL, 18)
	kit.cast()
	kit.disc(Transform3D(Basis.IDENTITY, Vector3(0, 1.0, -0.75)), 0.58, 0.0, 0.06, Pal.BRONZE, 24)
	kit.gloss()
	kit.turned(Vector3(0, 1.06, -0.75), Vector3(0, 2.25, -0.75), PackedVector2Array([Vector2(0.5, 0.0), Vector2(0.5, 0.8), Vector2(0.42, 1.04), Vector2(0.22, 1.16), Vector2(0.0, 1.19)]), Pal.GLASS.lightened(0.25), 24, true)
	kit.cast()
	kit.disc(Transform3D(Basis.IDENTITY, Vector3(0, 2.24, -0.75)), 0.1, 0.0, 0.06, Pal.BRONZE, 10)
	# round sign on the roof
	kit.cast()
	kit.tube(Vector3(0, top - 0.05, 0.55), Vector3(0, top + 0.3, 0.55), 0.04, 0.04, Pal.BRONZE, 6)
	kit.turned(Vector3(0, top + 0.66, 0.5), Vector3(0, top + 0.66, 0.6), PackedVector2Array([Vector2(0.48, 0.0), Vector2(0.48, 0.1)]), Pal.BRONZE, 24)
	kit.gloss()
	kit.turned(Vector3(0, top + 0.66, 0.495), Vector3(0, top + 0.66, 0.605), PackedVector2Array([Vector2(0.42, 0.0), Vector2(0.42, 0.11)]), Pal.CREAM, 24)
	_grille(kit, Transform3D(Basis.from_euler(Vector3(0, 0, PI * 0.5)), Vector3(-1.16, 1.5, 0.75)), 0.24)
	node.add_child(kit.instance())
	_label(node, "GEAR", Vector3(0, top + 0.66, 0.49), 0.85, Pal.BRONZE).rotation.y = PI
	_label(node, "GEAR", Vector3(0, top + 0.66, 0.61), 0.85, Pal.BRONZE)
	var cyl := CylinderShape3D.new()
	cyl.radius = 1.2
	cyl.height = 2.5
	_static(node, cyl, Vector3(0, 1.25, 0.55))
	for sx3: float in [-1.0, 1.0]:
		var lc := CylinderShape3D.new()
		lc.radius = 0.42
		lc.height = 2.0
		_static(node, lc, Vector3(1.45 * sx3, 1.05, 0.2))
	var jar := CylinderShape3D.new()
	jar.radius = 0.58
	jar.height = 2.25
	_static(node, jar, Vector3(0, 1.12, -0.75))
	_interactable(node, 2.0, 2.6, Vector3(0, 1.3, -0.9), "Outfitter - upgrade your gear", "gear")
	_gear_display = Node3D.new()
	_gear_display.name = "Display"
	_gear_display.position = Vector3(0, 1.55, -0.75)
	node.add_child(_gear_display)
	var spot := SpotLight3D.new()
	spot.light_color = Pal.LAMP_COOL
	spot.light_energy = 1.6
	spot.spot_range = 2.4
	spot.spot_angle = 40.0
	spot.shadow_enabled = false
	spot.position = Vector3(0, 2.15, -0.75)
	spot.rotation = Vector3(-PI * 0.5, 0, 0)
	node.add_child(spot)
	return node


## The bot dock: a round landing dish with an ion ring, and a tripod mast carrying a gimbal
## ring beacon.
func _build_dock(local: Vector2) -> Node3D:
	var node := Node3D.new()
	node.name = "BotDock"
	add_child(node)
	node.global_transform = _spot(local, _yaw_to_center(local))
	var kit := MeshKit.new()
	_plinth(kit, 1.3, 0.1, 0.5, Pal.CONCRETE_DARK)
	kit.cast()
	kit.lathe(PackedVector2Array([Vector2(0.85, 0.1), Vector2(0.85, 0.14), Vector2(0.4, 0.2), Vector2(0.0, 0.2)]), Transform3D.IDENTITY, Pal.BRONZE, 24, false, true)
	kit.surf(0.3).set_emission(1.2)
	kit.disc(Transform3D(Basis.IDENTITY, Vector3(0, 0.2, 0)), 0.62, 0.56, 0.006, Pal.ION, 24)
	kit.set_emission(0.0)
	# tripod mast
	var mast := Vector3(1.0, 0.1, 0.0)
	kit.cast()
	for k in 3:
		var a := TAU * float(k) / 3.0
		kit.tube(mast + Vector3(cos(a), 0, sin(a)) * 0.28, mast + Vector3(0, 1.4, 0), 0.03, 0.025, Pal.BRONZE, 6)
	kit.bare()
	kit.tube(mast + Vector3(0, 1.35, 0), mast + Vector3(0, 2.0, 0), 0.035, 0.03, Pal.STEEL_DARK, 6)
	kit.cast()
	kit.torus(Transform3D(Basis.from_euler(Vector3(PI * 0.5, 0, 0)), mast + Vector3(0, 2.05, 0)), 0.16, 0.02, Pal.COPPER, 18, 5)
	kit.surf(0.3).set_emission(1.6)
	kit.sphere(mast + Vector3(0, 2.05, 0), 0.06, Pal.ION, Vector3.ONE, 8, 5)
	kit.set_emission(0.0)
	node.add_child(kit.instance())
	var shape := CylinderShape3D.new()
	shape.radius = 1.15
	shape.height = 0.4
	_static(node, shape, Vector3(0, -0.05, 0))
	dock_position = node.global_position + node.global_basis.y * 1.6
	return node


## The site marker: a round cream survey plate on a bronze post with tripod feet.
func _build_sign(local: Vector2) -> void:
	var node := Node3D.new()
	node.name = "Sign"
	add_child(node)
	node.global_transform = _spot(local, _yaw_to_center(local))
	var kit := MeshKit.new().cast()
	for k in 3:
		var a := TAU * float(k) / 3.0 + 0.3
		kit.tube(Vector3(cos(a), 0, sin(a)) * 0.45 + Vector3(0, -0.1, 0), Vector3(0, 0.7, 0), 0.03, 0.03, Pal.BRONZE, 6)
	kit.tube(Vector3(0, 0.6, 0), Vector3(0, 1.0, 0), 0.05, 0.05, Pal.BRONZE, 8)
	kit.turned(Vector3(0, 1.62, -0.05), Vector3(0, 1.62, 0.05), PackedVector2Array([Vector2(0.72, 0.0), Vector2(0.72, 0.1)]), Pal.BRONZE, 32)
	kit.gloss()
	kit.turned(Vector3(0, 1.62, -0.056), Vector3(0, 1.62, 0.056), PackedVector2Array([Vector2(0.65, 0.0), Vector2(0.65, 0.112)]), Pal.CREAM, 32)
	kit.paint()
	kit.torus(Transform3D(Basis.from_euler(Vector3(PI * 0.5, 0, 0)), Vector3(0, 1.62, 0.0)), 0.5, 0.012, Pal.JADE, 40, 4)
	node.add_child(kit.instance())
	var title := str(planet.config.get("name", "Planet")).to_upper()
	var site := "SURVEY SITE %02d" % (int(planet.config.get("order", 0)) + 1)
	for side: float in [-1.0, 1.0]:
		var l := _label(node, title, Vector3(0, 1.7, 0.058 * side), 0.7, Pal.BRONZE)
		l.rotation = Vector3(0, 0.0 if side > 0 else PI, 0)
		var l2 := _label(node, site, Vector3(0, 1.46, 0.058 * side), 0.3, Pal.ENAMEL_SHADE)
		l2.rotation = Vector3(0, 0.0 if side > 0 else PI, 0)


## A path lantern: a bronze crook post with a small domed lantern hanging from it.
func _build_lamp(local: Vector2) -> void:
	var node := Node3D.new()
	add_child(node)
	node.global_transform = _spot(local, _yaw_to_center(local))
	var kit := MeshKit.new().cast()
	kit.disc(Transform3D(Basis.IDENTITY, Vector3(0, -0.05, 0)), 0.16, 0.0, 0.1, Pal.BRONZE, 10)
	kit.tube(Vector3(0, 0, 0), Vector3(0, 2.4, 0), 0.04, 0.03, Pal.BRONZE, 8)
	var crook := PackedVector3Array()
	for j in 7:
		var a := PI * float(j) / 6.0
		crook.append(Vector3(0, 2.4 + sin(a) * 0.22, -0.22 + cos(a) * 0.22))
	kit.pipe(crook, 0.025, Pal.BRONZE, 6)
	kit.tube(Vector3(0, 2.4, -0.44), Vector3(0, 2.25, -0.44), 0.01, 0.01, Pal.STEEL_DARK, 4)
	kit.turned(Vector3(0, 2.0, -0.44), Vector3(0, 2.26, -0.44), PackedVector2Array([Vector2(0.11, 0.0), Vector2(0.13, 0.14), Vector2(0.08, 0.24), Vector2(0.0, 0.26)]), Pal.ENAMEL, 12, true)
	kit.surf(0.4).set_emission(2.4)
	kit.turned(Vector3(0, 1.94, -0.44), Vector3(0, 2.02, -0.44), PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.09, 0.02), Vector2(0.1, 0.08)]), Pal.LAMP_WARM, 12, true)
	kit.set_emission(0.0)
	node.add_child(kit.instance())
	var light := OmniLight3D.new()
	light.light_color = Pal.LAMP_WARM
	light.light_energy = 0.5
	light.omni_range = 7.0
	light.omni_attenuation = 1.4
	light.shadow_enabled = false
	light.position = Vector3(0, 1.85, -0.44)
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
	kit.block(Vector3(0, 0, 0), Vector3(0.56, 0.72, 0.34) * s, Pal.ENAMEL_SHADE, 0.07 * s)
	kit.block(Vector3(0, 0.3 * s, 0.0), Vector3(0.6, 0.2, 0.38) * s, Pal.BRONZE, 0.05 * s)
	kit.block(Vector3(0, -0.12 * s, 0.19 * s), Vector3(0.4, 0.3, 0.1) * s, Pal.BRONZE, 0.03 * s)
	kit.paint()
	kit.block(Vector3(0, 0.12 * s, 0.172 * s), Vector3(0.5, 0.05, 0.02) * s, Pal.JADE, 0.006)
	kit.rubber()
	for sx: float in [-1.0, 1.0]:
		kit.tube(Vector3(0.18 * sx * s, 0.3 * s, -0.18 * s), Vector3(0.18 * sx * s, -0.3 * s, -0.18 * s), 0.035 * s, 0.035 * s, Pal.RUBBER, 6)
	if level >= 2:
		for sx2: float in [-1.0, 1.0]:
			kit.matte()
			kit.block(Vector3(0.33 * sx2 * s, -0.1 * s, 0.0), Vector3(0.12, 0.34, 0.24) * s, Pal.ENAMEL_SHADE.darkened(0.08), 0.03 * s)
	if level >= 4:
		kit.bare()
		for sx3: float in [-1.0, 1.0]:
			kit.tube(Vector3(0.3 * sx3 * s, -0.42 * s, -0.12 * s), Vector3(0.3 * sx3 * s, 0.5 * s, -0.12 * s), 0.018 * s, 0.018 * s, Pal.STEEL, 6)
		kit.tube(Vector3(-0.3 * s, 0.5 * s, -0.12 * s), Vector3(0.3 * s, 0.5 * s, -0.12 * s), 0.018 * s, 0.018 * s, Pal.STEEL, 6)
	if level >= 6:
		kit.surf(0.3).set_emission(1.5)
		kit.block(Vector3(0, 0.3 * s, 0.195 * s), Vector3(0.2, 0.05, 0.01) * s, Pal.ION, 0.004)
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
		node.global_transform = _spot(Vector2(-6.4, -5.0), 0.4)
		var kit := MeshKit.new()
		var slots := [Vector3(0, 0.3, 0), Vector3(0.72, 0.3, 0.1), Vector3(0.3, 0.9, 0.05), Vector3(-0.2, 0.3, 0.75), Vector3(1.42, 0.3, -0.1), Vector3(0.9, 0.9, 0.0)]
		for i in crates:
			# sample canisters: enamel drums with bronze lids, stacked as the pack grows
			var p: Vector3 = slots[i] - Vector3(0, 0.3, 0)
			kit.cast()
			kit.turned(p, p + Vector3(0, 0.08, 0), PackedVector2Array([Vector2(0.3, 0.0), Vector2(0.3, 0.08)]), Pal.BRONZE, 14)
			kit.paint()
			kit.turned(p + Vector3(0, 0.08, 0), p + Vector3(0, 0.5, 0), PackedVector2Array([Vector2(0.27, 0.0), Vector2(0.27, 0.42)]), Pal.ENAMEL_SHADE if i % 2 == 0 else Pal.ENAMEL, 14)
			kit.cast()
			kit.turned(p + Vector3(0, 0.5, 0), p + Vector3(0, 0.6, 0), PackedVector2Array([Vector2(0.29, 0.0), Vector2(0.29, 0.05), Vector2(0.12, 0.1), Vector2(0.0, 0.1)]), Pal.BRONZE, 14)
			if i % 3 == 0:
				kit.gloss()
				kit.turned(p + Vector3(0, 0.26, 0), p + Vector3(0, 0.36, 0), PackedVector2Array([Vector2(0.275, 0.0), Vector2(0.275, 0.1)]), Pal.CREAM, 14)
		node.add_child(kit.instance())
	if powered:
		var node2 := Node3D.new()
		_progress.add_child(node2)
		node2.global_transform = _spot(Vector2(6.9, -4.6), -0.6)
		var kit2 := MeshKit.new()
		_plinth(kit2, 1.5, 0.05, 0.4, Pal.CONCRETE_DARK)
		for i in 2:
			var x := -0.75 + 1.5 * float(i)
			kit2.bare()
			kit2.tube(Vector3(x, 0.05, 0), Vector3(x, 0.95, 0), 0.05, 0.04, Pal.STEEL_DARK, 6)
			var pb := Basis.from_euler(Vector3(-0.7, 0, 0))
			kit2.paint()
			kit2.hbox(Transform3D(pb, Vector3(x, 1.02, 0)), Vector3(1.3, 0.05, 0.95), Pal.ENAMEL, 0.012)
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
			Transform3D(Basis.from_euler(Vector3(0.9, 0.5, 0)), Vector3(1.1, 3.25, 0.75)), Pal.ENAMEL, 18, true)
		kit3.surf(0.3).set_emission(1.6)
		kit3.sphere(Vector3(1.1, 3.25, 0.75) + Basis.from_euler(Vector3(0.9, 0.5, 0)) * Vector3(0, 0.26, 0), 0.03, Pal.ION, Vector3.ONE, 6, 4)
		var mi := kit3.instance()
		_progress.add_child(mi)
		mi.global_transform = _tool_shop.global_transform
	if bots and _dock != null:
		var light := OmniLight3D.new()
		light.light_color = Pal.ION
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
		world.fx.sparks(pos + up * 0.3, up, Pal.JADE, 12)
		world.fx.floating_text(pos + up * 1.2, "+%s" % GameData.format_money(total), UiTheme.YELLOW, 1.4, 1.2, 1.5)
		Audio.play_at("sell", pos, 2.0, 1.0, 0.03))
