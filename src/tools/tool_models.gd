class_name ToolModels
extends RefCounted
## Procedural models for every tool tier, built from MeshKit's hard-surface primitives.
##
## Design rules (docs/ART_DIRECTION.md, "Tools"):
##   * One family, one silhouette idea; each tier adds real construction (powered head, rams,
##     turbines), never just a new colour. Paint is off-white with graphite, bare steel does the
##     work, amber marks what the hand touches, teal means stored energy.
##   * Every purchased mod bolts something visible onto the model.
##   * The player looks at the tool from behind, above and slightly from the left, so the
##     interesting detail sits on top and on the -X side.
##
## Convention: the grip is at the origin, the working end points along -Z, +Y is up.
## build() returns {"root": Node3D, "spin": Node3D|null, "piston": Node3D|null,
##                  "muzzle": Node3D, "material": ShaderMaterial, "recoil": Node3D|null}
## spin / piston / recoil are animated by ToolController.

## Maps a prism outline (x = across, y = forward) onto the tool: flat, pointing along -Z.
const FLAT := Basis(Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0))
## Maps a prism outline (x = forward, y = up) onto the tool's side plane (extruded along X).
const SIDE := Basis(Vector3(0, 0, -1), Vector3(0, 1, 0), Vector3(1, 0, 0))


static func build(family_id: String, tier: int, mods: Dictionary = {}, viewmodel := true) -> Dictionary:
	var root := Node3D.new()
	root.name = "Tool_%s_%d" % [family_id, tier]
	var mat: ShaderMaterial = MeshKit.new_viewmodel_material() if viewmodel else MeshKit.new_material()
	var out := {"root": root, "spin": null, "piston": null, "muzzle": null, "material": mat, "recoil": null}
	match family_id:
		"shovel": _shovel(out, tier, mods, mat)
		"drill": _drill(out, tier, mods, mat)
		"vacuum": _vacuum(out, tier, mods, mat)
		"cannon": _cannon(out, tier, mods, mat)
	if out["muzzle"] == null:
		_muzzle(out, Vector3(0, 0, -0.6))
	return out


static func _part(parent: Node3D, kit: MeshKit, mat: Material, part_name: String, pos := Vector3.ZERO) -> MeshInstance3D:
	var mi := kit.instance(mat, false)
	mi.name = part_name
	mi.position = pos
	parent.add_child(mi)
	return mi


static func _node(parent: Node3D, node_name: String, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.name = node_name
	n.position = pos
	parent.add_child(n)
	return n


static func _muzzle(out: Dictionary, pos: Vector3) -> void:
	out["muzzle"] = _node(out["root"], "Muzzle", pos)


# ------------------------------------------------------------------ shared parts

## Rubber pistol grip hanging below `top`, raked back a little, with moulded finger ridges.
static func _pistol_grip(kit: MeshKit, top: Vector3, length := 0.13, s := 1.0) -> void:
	var b := Basis.from_euler(Vector3(0.3, 0, 0))
	kit.rubber()
	kit.hbox(Transform3D(b, top + b * Vector3(0, -length * 0.5, 0)), Vector3(0.036 * s, length, 0.05 * s), Pal.RUBBER, 0.012 * s)
	for i in 3:
		kit.hbox(Transform3D(b, top + b * Vector3(0, -length * (0.25 + 0.25 * float(i)), -0.026 * s)), Vector3(0.038 * s, length * 0.13, 0.012 * s), Pal.CHARCOAL, 0.004)
	kit.paint()
	kit.hbox(Transform3D(b, top + b * Vector3(0, -length - 0.004, 0)), Vector3(0.04 * s, 0.012, 0.054 * s), Pal.GRAPHITE, 0.004)


## Trigger and guard in front of a pistol grip.
static func _trigger(kit: MeshKit, at: Vector3, s := 1.0) -> void:
	kit.paint()
	kit.hbox(Transform3D(Basis.from_euler(Vector3(-0.35, 0, 0)), at + Vector3(0, -0.02 * s, 0)), Vector3(0.012 * s, 0.04 * s, 0.012 * s), Pal.AMBER, 0.004)
	kit.cast()
	kit.pipe(PackedVector3Array([at + Vector3(0, 0, 0.022 * s), at + Vector3(0, -0.05 * s, 0.018 * s), at + Vector3(0, -0.055 * s, -0.03 * s), at + Vector3(0, -0.004, -0.045 * s)]), 0.004 * s, Pal.GRAPHITE, 5)


## Closed D-handle loop in the YZ plane, behind `at` (shovel grips, carry handles).
static func _d_handle(kit: MeshKit, at: Vector3, width := 0.1, depth := 0.08) -> void:
	kit.paint()
	kit.pipe(PackedVector3Array([at, at + Vector3(-width * 0.5, 0, depth * 0.35), at + Vector3(-width * 0.5, 0, depth)]), 0.011, Pal.GRAPHITE, 6)
	kit.pipe(PackedVector3Array([at, at + Vector3(width * 0.5, 0, depth * 0.35), at + Vector3(width * 0.5, 0, depth)]), 0.011, Pal.GRAPHITE, 6)
	kit.rubber()
	kit.tube(at + Vector3(-width * 0.5 - 0.006, 0, depth), at + Vector3(width * 0.5 + 0.006, 0, depth), 0.016, 0.016, Pal.RUBBER, 8)
	kit.paint()
	for sx: float in [-1.0, 1.0]:
		kit.tube(at + Vector3(sx * (width * 0.5 - 0.004), 0, depth), at + Vector3(sx * (width * 0.5 + 0.008), 0, depth), 0.019, 0.019, Pal.AMBER, 8)


## A ring of small bolt heads around the Z axis.
static func _bolts(kit: MeshKit, center: Vector3, radius: float, count: int, size := 0.006) -> void:
	kit.bare()
	for i in count:
		var a := TAU * float(i) / float(count) + 0.3
		var p := center + Vector3(cos(a), sin(a), 0) * radius
		kit.tube(p + Vector3(0, 0, 0.002), p + Vector3(0, 0, -size), size, size, Pal.STEEL, 6)


## Small indicator light (unlit housing + emissive lens).
static func _lamp(kit: MeshKit, pos: Vector3, color: Color, size := 0.008, strength := 1.6) -> void:
	kit.paint().set_emission(0.0)
	kit.block(pos, Vector3(size * 2.4, size * 0.8, size * 2.4), Pal.CHARCOAL, size * 0.3)
	kit.surf(0.25).set_emission(strength)
	kit.block(pos + Vector3(0, size * 0.5, 0), Vector3(size * 1.5, size * 0.6, size * 1.5), color, size * 0.25)
	kit.set_emission(0.0)


# ------------------------------------------------------------------ shovels

static func _spade_outline(half_w: float, length: float, chipped := false) -> PackedVector2Array:
	var w := half_w
	var pts := PackedVector2Array([
		Vector2(-w * 0.72, 0.0), Vector2(-w, length * 0.14), Vector2(-w, length * 0.62),
		Vector2(-w * 0.62, length * 0.9), Vector2(-w * 0.16, length), Vector2(w * 0.16, length)])
	if chipped:
		pts.append_array(PackedVector2Array([Vector2(w * 0.5, length * 0.93), Vector2(w * 0.58, length * 0.82), Vector2(w * 0.78, length * 0.8)]))
	else:
		pts.append(Vector2(w * 0.62, length * 0.9))
	pts.append_array(PackedVector2Array([Vector2(w, length * 0.62), Vector2(w, length * 0.14), Vector2(w * 0.72, 0.0)]))
	return pts


static func _shovel(out: Dictionary, tier: int, mods: Dictionary, mat: Material) -> void:
	var root: Node3D = out["root"]
	var kit := MeshKit.new()
	var wide := 1.0 + 0.14 * float(mods.get("wide_scoop", 0))
	var quick := int(mods.get("quick_hands", 0))
	var teeth := int(mods.get("ore_tooth", 0))
	var trench := int(mods.get("trench_blade", 0)) > 0
	var tilt := Basis.from_euler(Vector3(deg_to_rad(-13.0), 0, 0))
	var tip_z := -0.7
	match tier:
		1:
			# Rusty Scoop: a short hand scoop. Turned wooden handle with a cloth wrap, a pitted
			# rust blade with a chipped edge and one crude weld. Humble, but a real object.
			kit.matte()
			kit.turned(Vector3(0, 0, 0.17), Vector3(0, 0, -0.2), PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.021, 0.004), Vector2(0.024, 0.03),
				Vector2(0.02, 0.1), Vector2(0.022, 0.2), Vector2(0.019, 0.37)]), Pal.WOOD, 10, true)
			kit.turned(Vector3(0, 0, 0.1), Vector3(0, 0, 0.0), PackedVector2Array([Vector2(0.0235, 0.0), Vector2(0.0245, 0.05), Vector2(0.0225, 0.1)]), Pal.TAPE, 10, true)
			kit.tube(Vector3(0, 0, 0.055), Vector3(0, 0, 0.045), 0.0255, 0.0255, Pal.TAPE.darkened(0.2), 10)
			kit.cast()
			kit.turned(Vector3(0, 0, -0.19), Vector3(0, 0, -0.26), PackedVector2Array([Vector2(0.023, 0.0), Vector2(0.025, 0.012), Vector2(0.025, 0.05), Vector2(0.02, 0.07)]), Pal.STEEL_DARK, 10)
			# socket: a bent strap from ferrule down to the blade
			kit.hbox(Transform3D(tilt, Vector3(0, -0.012, -0.3)), Vector3(0.04, 0.014, 0.12), Pal.RUST_DARK, 0.005)
			# blade
			var blade_xf := Transform3D(tilt * FLAT, Vector3(0, -0.026, -0.32))
			kit.surf(0.72, 0.35)
			kit.prism(_spade_outline(0.088 * wide, 0.23, true), -0.005, 0.005, blade_xf, Pal.RUST)
			# rolled side lips make it a scoop rather than a plate
			for sx: float in [-1.0, 1.0]:
				kit.hbox(Transform3D(tilt, Vector3(0.084 * wide * sx, -0.04, -0.41)), Vector3(0.01, 0.022, 0.13), Pal.RUST_DARK, 0.004)
			kit.hbox(Transform3D(tilt, Vector3(0, -0.018, -0.33)), Vector3(0.13 * wide, 0.02, 0.012), Pal.RUST_DARK, 0.004)
			# pitting and a weld bead
			kit.matte()
			kit.prism(PackedVector2Array([Vector2(-0.05, 0.05), Vector2(-0.02, 0.04), Vector2(-0.01, 0.09), Vector2(-0.04, 0.11)]), 0.0052, 0.0062, blade_xf, Pal.RUST_DARK)
			kit.prism(PackedVector2Array([Vector2(0.02, 0.12), Vector2(0.055, 0.11), Vector2(0.06, 0.15), Vector2(0.03, 0.17)]), 0.0052, 0.0062, blade_xf, Pal.RUST_DARK.darkened(0.1))
			kit.cast()
			kit.hbox(Transform3D(tilt, Vector3(0.012, -0.012, -0.355)), Vector3(0.012, 0.01, 0.03), Pal.STEEL_DARK, 0.004)
			_add_blade_mods(kit, tilt, wide, teeth, trench, Vector3(0, -0.075, -0.535), 0.07, 1)
			tip_z = -0.56
		2:
			# Sturdy Spade: tubular steel shaft, D-grip, forged blued blade with a centre rib,
			# rolled treads and a ground cutting edge.
			kit.bare()
			kit.tube(Vector3(0, 0, 0.12), Vector3(0, 0, -0.34), 0.016, 0.016, Pal.STEEL, 10)
			_d_handle(kit, Vector3(0, 0, 0.12), 0.1, 0.09)
			kit.rubber()
			kit.tube(Vector3(0, 0, 0.04), Vector3(0, 0, -0.1), 0.02, 0.02, Pal.RUBBER, 10)
			kit.paint()
			kit.tube(Vector3(0, 0, -0.1), Vector3(0, 0, -0.118), 0.021, 0.021, Pal.STEEL_BLUE, 10)
			kit.cast()
			kit.turned(Vector3(0, 0, -0.32), Vector3(0, 0, -0.44), PackedVector2Array([Vector2(0.018, 0.0), Vector2(0.023, 0.015), Vector2(0.026, 0.08), Vector2(0.02, 0.12)]), Pal.STEEL_DARK, 10)
			_bolts(kit, Vector3(0, 0, -0.36), 0.0, 1, 0.006)
			var bxf := Transform3D(tilt * FLAT, Vector3(0, -0.028, -0.42))
			kit.surf(0.36, 0.8)
			kit.prism(_spade_outline(0.105 * wide, 0.3), -0.005, 0.005, bxf, Pal.STEEL_BLUE)
			# ground edge: a brighter bevel along the tip
			kit.bare()
			kit.prism(PackedVector2Array([Vector2(-0.105 * wide, 0.19), Vector2(-0.065 * wide, 0.27), Vector2(-0.017 * wide, 0.3), Vector2(0.017 * wide, 0.3),
				Vector2(0.065 * wide, 0.27), Vector2(0.105 * wide, 0.19), Vector2(0.09 * wide, 0.185), Vector2(0.055 * wide, 0.25),
				Vector2(0.0, 0.278), Vector2(-0.055 * wide, 0.25), Vector2(-0.09 * wide, 0.185)]), 0.0052, 0.0066, bxf, Pal.STEEL)
			# centre rib and socket strap
			kit.surf(0.4, 0.8)
			kit.hbox(Transform3D(tilt, Vector3(0, -0.04, -0.52)), Vector3(0.026, 0.016, 0.2), Pal.STEEL_BLUE.darkened(0.12), 0.006)
			# rolled treads on the shoulders
			for sx2: float in [-1.0, 1.0]:
				kit.hbox(Transform3D(tilt, Vector3(0.066 * wide * sx2, -0.02, -0.43)), Vector3(0.06 * wide, 0.014, 0.022), Pal.STEEL_BLUE.lightened(0.08), 0.005)
			_add_blade_mods(kit, tilt, wide, teeth, trench, Vector3(0, -0.096, -0.71), 0.085, 2)
			tip_z = -0.74
		3:
			# Thumper 3000: a pneumatic breaker. Motor housing with a rear D-handle and a side
			# grip, twin drive cylinders, and a square blade on a reciprocating carrier.
			_power_shovel_body(kit, 1.0, 3, quick)
			var head := MeshKit.new()
			head.bare()
			for sx3: float in [-1.0, 1.0]:
				head.tube(Vector3(0.052 * sx3, 0.0, 0.14), Vector3(0.052 * sx3, 0.0, -0.05), 0.012, 0.012, Pal.STEEL, 8)
			head.cast()
			head.block(Vector3(0, 0, -0.065), Vector3(0.17, 0.05, 0.05), Pal.GRAPHITE, 0.012)
			_bolts(head, Vector3(0, 0, -0.092), 0.0, 1, 0.007)
			var hxf := Transform3D(tilt * FLAT, Vector3(0, -0.02, -0.07))
			head.paint()
			head.prism(PackedVector2Array([Vector2(-0.11 * wide, 0.0), Vector2(-0.125 * wide, 0.05), Vector2(-0.125 * wide, 0.2), Vector2(-0.09 * wide, 0.26),
				Vector2(0.09 * wide, 0.26), Vector2(0.125 * wide, 0.2), Vector2(0.125 * wide, 0.05), Vector2(0.11 * wide, 0.0)]), -0.007, 0.007, hxf, Pal.AMBER)
			head.bare()
			head.prism(PackedVector2Array([Vector2(-0.125 * wide, 0.18), Vector2(-0.09 * wide, 0.26), Vector2(0.09 * wide, 0.26), Vector2(0.125 * wide, 0.18),
				Vector2(0.11 * wide, 0.18), Vector2(0.08 * wide, 0.235), Vector2(-0.08 * wide, 0.235), Vector2(-0.11 * wide, 0.18)]), 0.0072, 0.009, hxf, Pal.STEEL)
			head.paint()
			for sx4: float in [-1.0, 1.0]:
				head.hbox(Transform3D(tilt, Vector3(0.121 * wide * sx4, -0.026, -0.2)), Vector3(0.012, 0.03, 0.18), Pal.GRAPHITE, 0.004)
			head.hbox(Transform3D(tilt, Vector3(0, -0.028, -0.13)), Vector3(0.2 * wide, 0.02, 0.016), Pal.GRAPHITE, 0.004)
			_add_blade_mods(head, tilt, wide, teeth, trench, Vector3(0, -0.08, -0.325), 0.1, 3)
			var piston := _node(root, "Piston", Vector3(0, 0, -0.3))
			_part(piston, head, mat, "Head")
			out["piston"] = piston
			tip_z = -0.66
		_:
			# Mega Scooper: hydraulic excavator bucket. Larger housing with an accumulator tank,
			# twin chrome rams and a toothed bucket that bites forward.
			_power_shovel_body(kit, 1.22, 4, quick)
			var bucket := MeshKit.new()
			bucket.bare()
			for sx5: float in [-1.0, 1.0]:
				bucket.tube(Vector3(0.075 * sx5, 0.01, 0.17), Vector3(0.075 * sx5, 0.01, -0.06), 0.016, 0.016, Pal.STEEL, 10)
				bucket.cast()
				bucket.tube(Vector3(0.075 * sx5, 0.01, -0.05), Vector3(0.075 * sx5, 0.01, -0.085), 0.024, 0.024, Pal.GRAPHITE, 10)
				bucket.bare()
			var bw := 0.16 * wide
			# side plates
			var side_outline := PackedVector2Array([Vector2(0.0, 0.07), Vector2(0.1, 0.085), Vector2(0.27, 0.02), Vector2(0.3, -0.05), Vector2(0.2, -0.085), Vector2(0.06, -0.07), Vector2(0.0, -0.02)])
			bucket.paint()
			for sx6: float in [-1.0, 1.0]:
				bucket.prism(side_outline, -0.007, 0.007, Transform3D(SIDE, Vector3(bw * sx6, 0.0, -0.08)), Pal.AMBER)
			# curved shell: back, belly and floor
			bucket.hbox(Transform3D(Basis.from_euler(Vector3(0.35, 0, 0)), Vector3(0, 0.03, -0.095)), Vector3(bw * 2.0, 0.11, 0.012), Pal.AMBER_DARK, 0.004)
			bucket.hbox(Transform3D(Basis.from_euler(Vector3(1.25, 0, 0)), Vector3(0, -0.06, -0.14)), Vector3(bw * 2.0, 0.1, 0.012), Pal.STEEL_DARK, 0.004)
			bucket.hbox(Transform3D(Basis.from_euler(Vector3(1.75, 0, 0)), Vector3(0, -0.078, -0.25)), Vector3(bw * 2.0, 0.14, 0.012), Pal.STEEL_DARK, 0.004)
			bucket.block(Vector3(0, 0.082, -0.13), Vector3(bw * 2.0 + 0.02, 0.014, 0.1), Pal.GRAPHITE, 0.004)
			# cutting edge and teeth
			bucket.bare()
			bucket.hbox(Transform3D(Basis.from_euler(Vector3(1.9, 0, 0)), Vector3(0, -0.062, -0.345)), Vector3(bw * 2.0 + 0.016, 0.05, 0.014), Pal.STEEL, 0.004)
			for i in 5:
				var tx := (float(i) - 2.0) * bw * 0.44
				bucket.prism(PackedVector2Array([Vector2(-0.016, 0.0), Vector2(0.0, 0.07), Vector2(0.016, 0.0)]), -0.009, 0.009,
					Transform3D(Basis.from_euler(Vector3(deg_to_rad(-20.0), 0, 0)) * FLAT, Vector3(tx, -0.05, -0.36)), Pal.STEEL)
			_bolts(bucket, Vector3(-bw - 0.008, 0.02, -0.14), 0.0, 1, 0.007)
			_add_blade_mods(bucket, tilt, wide * 1.4, teeth, trench, Vector3(0, -0.075, -0.42), 0.13, 4)
			var ram := _node(root, "Piston", Vector3(0, 0, -0.36))
			_part(ram, bucket, mat, "Bucket")
			out["piston"] = ram
			tip_z = -0.8
	if tier <= 2:
		# Quick Hands on a hand tool: counterweight collars at the butt, one per level.
		for i in quick:
			var z := (0.13 if tier == 1 else 0.07) - float(i) * 0.022
			kit.bare()
			kit.tube(Vector3(0, 0, z), Vector3(0, 0, z - 0.014), 0.028, 0.028, Pal.BRASS, 10)
	_part(root, kit, mat, "Body")
	_muzzle(out, Vector3(0, -0.05, tip_z))


## Housing shared by the two powered shovels (scale `s`). Quick Hands adds pressure
## canisters on the left side, one per level.
static func _power_shovel_body(kit: MeshKit, s: float, tier: int, quick: int) -> void:
	kit.paint()
	kit.block(Vector3(0, 0.0, -0.08 * s), Vector3(0.12, 0.11, 0.3) * s, Pal.HULL, 0.022 * s)
	kit.block(Vector3(0, 0.0, 0.075 * s), Vector3(0.126, 0.116, 0.03) * s, Pal.GRAPHITE, 0.012 * s)
	kit.block(Vector3(0, 0.0, -0.235 * s), Vector3(0.132, 0.12, 0.03) * s, Pal.GRAPHITE, 0.012 * s)
	# belt stripe and top spine
	kit.block(Vector3(0, 0.0, -0.02 * s), Vector3(0.1215, 0.1115, 0.022) * s, Pal.AMBER, 0.006)
	kit.block(Vector3(0, 0.058 * s, -0.1 * s), Vector3(0.05, 0.016, 0.2) * s, Pal.GRAPHITE, 0.006 * s)
	# vent on the visible (left) side and top status light
	kit.louvre(Transform3D(Basis.from_euler(Vector3(0, -PI * 0.5, 0)), Vector3(-0.0605 * s, 0.0, -0.13 * s)), Vector3(0.12, 0.05, 0.012) * s, 5, Pal.CHARCOAL, Pal.GRAPHITE)
	_lamp(kit, Vector3(0, 0.066 * s, 0.03 * s), Pal.TEAL, 0.008 * s)
	# rear D-handle and pistol grip with trigger
	_d_handle(kit, Vector3(0, 0.0, 0.09 * s), 0.1 * s, 0.085 * s)
	_pistol_grip(kit, Vector3(0, -0.055 * s, 0.03 * s), 0.12 * s, s)
	_trigger(kit, Vector3(0, -0.058 * s, -0.012 * s), s)
	# front side grip
	kit.bare()
	kit.tube(Vector3(-0.06 * s, 0.0, -0.19 * s), Vector3(-0.115 * s, 0.01 * s, -0.19 * s), 0.008 * s, 0.008 * s, Pal.STEEL_DARK, 6)
	kit.rubber()
	kit.tube(Vector3(-0.115 * s, 0.0, -0.15 * s), Vector3(-0.115 * s, 0.02 * s, -0.235 * s), 0.015 * s, 0.015 * s, Pal.RUBBER, 8)
	# drive cylinders
	kit.cast()
	for sx: float in [-1.0, 1.0]:
		var x := (0.052 if tier == 3 else 0.075 / s) * sx * s
		kit.tube(Vector3(x, 0.0 if tier == 3 else 0.01 * s, -0.12 * s), Vector3(x, 0.0 if tier == 3 else 0.01 * s, -0.275 * s), 0.021 * s, 0.021 * s, Pal.STEEL_DARK, 10)
	# hose from the housing to the cylinders
	kit.rubber()
	kit.pipe(PackedVector3Array([Vector3(0.03 * s, 0.056 * s, -0.04 * s), Vector3(0.05 * s, 0.085 * s, -0.12 * s), Vector3(0.056 * s, 0.03 * s, -0.22 * s)]), 0.007 * s, Pal.RUBBER, 6)
	if tier >= 4:
		# accumulator tank with a sight gauge and an energy strip
		kit.paint()
		kit.turned(Vector3(-0.012, 0.098 * s, 0.03 * s), Vector3(-0.012, 0.098 * s, -0.19 * s), PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.026 * s, 0.006), Vector2(0.034 * s, 0.03),
			Vector2(0.034 * s, 0.19 * s), Vector2(0.026 * s, 0.215 * s), Vector2(0.0, 0.22 * s)]), Pal.HULL_SHADE, 12, true)
		kit.cast()
		for z: float in [-0.02, -0.14]:
			kit.tube(Vector3(-0.012, 0.098 * s, z * s), Vector3(-0.012, 0.098 * s, (z - 0.014) * s), 0.0365 * s, 0.0365 * s, Pal.GRAPHITE, 12)
		kit.gloss()
		kit.tube(Vector3(-0.052 * s, 0.1 * s, -0.08 * s), Vector3(-0.058 * s, 0.1 * s, -0.08 * s), 0.014 * s, 0.014 * s, Pal.GLASS, 10)
		kit.surf(0.25).set_emission(1.4)
		kit.block(Vector3(0.0, 0.0, -0.065 * s), Vector3(0.1225, 0.02, 0.05) * s, Pal.TEAL, 0.004)
		kit.set_emission(0.0)
	for i in quick:
		var z2 := (0.04 - 0.045 * float(i)) * s
		kit.bare()
		kit.turned(Vector3(-0.078 * s, 0.03 * s, z2), Vector3(-0.078 * s, 0.03 * s, z2 - 0.036 * s), PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.012 * s, 0.003),
			Vector2(0.014 * s, 0.01), Vector2(0.014 * s, 0.028 * s), Vector2(0.008 * s, 0.036 * s)]), Pal.BRASS, 8, true)


## Blade attachments. `front` is the middle of the cutting edge.
static func _add_blade_mods(kit: MeshKit, tilt: Basis, wide: float, teeth: int, trench: bool, front: Vector3, half_w: float, tier: int) -> void:
	# Ore Tooth: hardened pry-teeth bolted along the leading edge.
	if teeth > 0:
		var n := 2 + teeth * 2 if tier < 4 else 0
		kit.bare()
		for i in n:
			var x := lerpf(-half_w, half_w, float(i) / float(maxi(n - 1, 1))) * wide
			kit.prism(PackedVector2Array([Vector2(-0.011, 0.0), Vector2(0.0, 0.05), Vector2(0.011, 0.0)]), -0.006, 0.006,
				Transform3D(tilt * FLAT, front + Vector3(x, 0.004, 0.012)), Pal.STEEL)
		# carbide strip behind the teeth (also the visible change on the toothed bucket)
		kit.surf(0.35, 0.7)
		kit.hbox(Transform3D(tilt, front + Vector3(0, 0.014, 0.045)), Vector3(half_w * 2.0 * wide, 0.01, 0.022), Pal.BRASS, 0.003)
		if teeth > 1:
			kit.hbox(Transform3D(tilt, front + Vector3(0, 0.02, 0.075)), Vector3(half_w * 1.7 * wide, 0.01, 0.016), Pal.BRASS, 0.003)
	# Trench Blade: a long keel that leads the cut.
	if trench:
		kit.surf(0.36, 0.8)
		kit.prism(PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.24, 0.0), Vector2(0.31, -0.03), Vector2(0.24, -0.05), Vector2(0.0, -0.035)]), -0.006, 0.006,
			Transform3D(tilt * SIDE, front + Vector3(0, 0.04, 0.2)), Pal.STEEL_BLUE)
		kit.paint()
		kit.hbox(Transform3D(tilt, front + Vector3(0, 0.047, 0.12)), Vector3(0.016, 0.012, 0.12), Pal.AMBER, 0.004)


# ------------------------------------------------------------------ drills

static func _drill(out: Dictionary, tier: int, mods: Dictionary, mat: Material) -> void:
	var root: Node3D = out["root"]
	var kit := MeshKit.new()
	var bore := 1.0 + 0.13 * float(mods.get("wide_bore", 0))
	var turbo := int(mods.get("turbo", 0))
	var fracture := int(mods.get("fracture_bit", 0))
	var shaft := 0.1 * float(mods.get("long_shaft", 0))
	var s: float = [1.0, 1.12, 1.3][clampi(tier - 1, 0, 2)]
	var r := 0.058 * s                 # motor housing radius
	var nose_z := -0.25 * s            # where the gearbox ends
	# ---- motor housing (round, along Z)
	kit.paint()
	kit.turned(Vector3(0, 0, 0.1 * s), Vector3(0, 0, -0.14 * s), PackedVector2Array([Vector2(0.0, 0.0), Vector2(r * 0.8, 0.0), Vector2(r, 0.012 * s), Vector2(r, 0.24 * s)]), Pal.HULL, 16)
	kit.turned(Vector3(0, 0, 0.1 * s), Vector3(0, 0, 0.06 * s), PackedVector2Array([Vector2(r + 0.002, 0.012 * s), Vector2(r + 0.002, 0.04 * s)]), Pal.GRAPHITE, 16)
	kit.turned(Vector3(0, 0, -0.02 * s), Vector3(0, 0, -0.045 * s), PackedVector2Array([Vector2(r + 0.0015, 0.0), Vector2(r + 0.0015, 0.025 * s)]), Pal.AMBER, 16)
	# cooling fins at the back
	kit.cast()
	for i in 4:
		var z := (0.092 - 0.011 * float(i)) * s
		kit.tube(Vector3(0, 0, z), Vector3(0, 0, z - 0.004 * s), r * (0.86 - 0.06 * float(i)) + 0.012 * s, r * (0.86 - 0.06 * float(i)) + 0.012 * s, Pal.GRAPHITE, 14)
	# ---- gearbox: tapered cast nose
	kit.cast()
	kit.turned(Vector3(0, 0, -0.14 * s), Vector3(0, 0, nose_z), PackedVector2Array([Vector2(r + 0.004, 0.0), Vector2(r + 0.004, 0.03 * s), Vector2(r * 0.72, 0.085 * s), Vector2(r * 0.62, 0.11 * s)]), Pal.GRAPHITE, 16)
	_bolts(kit, Vector3(0, 0, -0.142 * s), r - 0.006, 6, 0.005 * s)
	# long shaft collar (mod)
	if shaft > 0.0:
		kit.bare()
		kit.tube(Vector3(0, 0, nose_z), Vector3(0, 0, nose_z - shaft), r * 0.42, r * 0.42, Pal.STEEL, 12)
		kit.cast()
		kit.tube(Vector3(0, 0, nose_z - shaft * 0.45), Vector3(0, 0, nose_z - shaft * 0.45 - 0.014), r * 0.52, r * 0.52, Pal.AMBER_DARK, 12)
	# ---- grips
	_pistol_grip(kit, Vector3(0, -r * 0.9, 0.04 * s), 0.12 * s, s)
	_trigger(kit, Vector3(0, -r - 0.004, -0.004 * s), s)
	# battery / power pack under the nose
	kit.paint()
	kit.block(Vector3(0, -r - 0.022 * s, -0.09 * s), Vector3(0.06, 0.04, 0.09) * s, Pal.GRAPHITE, 0.01 * s)
	for i in 3:
		_lamp(kit, Vector3(-0.031 * s, -r - 0.018 * s, (-0.065 - 0.022 * float(i)) * s), Pal.TEAL if i < tier else Pal.STEEL_DARK, 0.004 * s, 1.4 if i < tier else 0.0)
	# vent on the visible side
	kit.louvre(Transform3D(Basis.from_euler(Vector3(0, -PI * 0.5, 0)), Vector3(-r - 0.001, 0.008 * s, 0.01 * s)), Vector3(0.07, 0.04, 0.01) * s, 4, Pal.CHARCOAL, Pal.GRAPHITE)
	if tier >= 2:
		# top carry handle and a braced side grip: this one needs two hands
		kit.cast()
		kit.pipe(PackedVector3Array([Vector3(0, r, 0.06 * s), Vector3(0, r + 0.045 * s, 0.04 * s), Vector3(0, r + 0.045 * s, -0.1 * s), Vector3(0, r, -0.13 * s)]), 0.0065 * s, Pal.GRAPHITE, 6)
		kit.rubber()
		kit.tube(Vector3(0, r + 0.045 * s, 0.02 * s), Vector3(0, r + 0.045 * s, -0.08 * s), 0.0105 * s, 0.0105 * s, Pal.RUBBER, 8)
		kit.bare()
		kit.tube(Vector3(-r, 0, -0.17 * s), Vector3(-r - 0.05 * s, -0.01 * s, -0.17 * s), 0.008 * s, 0.008 * s, Pal.STEEL_DARK, 6)
		kit.rubber()
		kit.tube(Vector3(-r - 0.05 * s, -0.055 * s, -0.17 * s), Vector3(-r - 0.05 * s, 0.02 * s, -0.17 * s), 0.014 * s, 0.014 * s, Pal.RUBBER, 8)
	if tier >= 3:
		# Mole Engine: shoulder brace, twin exhaust stacks and an energy core behind the head
		kit.rubber()
		kit.block(Vector3(0, 0.01 * s, 0.17 * s), Vector3(0.11, 0.1, 0.05) * s, Pal.RUBBER, 0.02 * s)
		kit.bare()
		kit.tube(Vector3(0, 0, 0.1 * s), Vector3(0, 0, 0.15 * s), 0.014 * s, 0.014 * s, Pal.STEEL_DARK, 8)
		kit.cast()
		for sx: float in [-1.0, 1.0]:
			kit.pipe(PackedVector3Array([Vector3(r * 0.7 * sx, r * 0.6, -0.1 * s), Vector3(r * 1.1 * sx, r * 1.25, -0.08 * s), Vector3(r * 1.1 * sx, r * 1.3, 0.03 * s)]), 0.011 * s, Pal.STEEL_DARK, 7)
		kit.surf(0.25).set_emission(1.5)
		kit.turned(Vector3(0, 0, -0.118 * s), Vector3(0, 0, -0.132 * s), PackedVector2Array([Vector2(r + 0.003, 0.0), Vector2(r + 0.003, 0.014 * s)]), Pal.TEAL, 16)
		kit.set_emission(0.0)
	# Turbo Motor (mod): intercooler blocks on the left flank, one per level
	for i in turbo:
		var tz := (0.045 - 0.05 * float(i)) * s
		kit.cast()
		kit.block(Vector3(-r - 0.012 * s, r * 0.55, tz), Vector3(0.02, 0.03, 0.04) * s, Pal.STEEL_DARK, 0.004)
		kit.bare()
		for f in 3:
			kit.block(Vector3(-r - 0.024 * s, r * 0.55, tz + (0.012 - 0.012 * float(f)) * s), Vector3(0.008, 0.034, 0.004) * s, Pal.STEEL, 0.001)
		kit.rubber()
		kit.pipe(PackedVector3Array([Vector3(-r - 0.012 * s, r * 0.55 + 0.016 * s, tz), Vector3(-r * 0.5, r + 0.006 * s, tz - 0.01 * s)]), 0.005 * s, Pal.RUBBER, 5)
	_part(root, kit, mat, "Body")

	# ---- spinning bit
	var spin := _node(root, "Spin", Vector3(0, 0, nose_z - shaft))
	var bit := MeshKit.new()
	var tip_len := 0.0
	bit.cast()
	# chuck: knurled (faceted) collar
	bit.turned(Vector3.ZERO, Vector3(0, 0, -0.045 * s), PackedVector2Array([Vector2(r * 0.6, 0.0), Vector2(r * 0.66, 0.008 * s), Vector2(r * 0.66, 0.034 * s), Vector2(r * 0.5, 0.045 * s)]), Pal.STEEL_DARK, 10, false, true)
	match tier:
		1:
			# single twist bit
			tip_len = 0.27 * s
			var rad := 0.034 * s * bore
			bit.bare()
			bit.turned(Vector3(0, 0, -0.04 * s), Vector3(0, 0, -0.04 * s - tip_len), PackedVector2Array([Vector2(rad * 0.62, 0.0), Vector2(rad * 0.62, tip_len * 0.78), Vector2(0.0, tip_len)]), Pal.STEEL_DARK, 10)
			for k in 2:
				bit.spiral(Vector3(0, 0, -0.045 * s), Vector3(0, 0, -0.04 * s - tip_len * 0.97), rad * 0.62, rad * 0.08, 2.6, tip_len * 0.11, rad * 0.5, Pal.STEEL, 44, PI * float(k))
			tip_len += 0.04 * s
		2:
			# planetary head: carrier plate with three diamond-tipped bits
			tip_len = 0.25 * s
			bit.cast()
			bit.turned(Vector3(0, 0, -0.04 * s), Vector3(0, 0, -0.07 * s), PackedVector2Array([Vector2(r * 0.5, 0.0), Vector2(r * 0.98 * bore, 0.008 * s), Vector2(r * 0.98 * bore, 0.024 * s), Vector2(r * 0.6, 0.03 * s)]), Pal.GRAPHITE, 14)
			for b in 3:
				var ang := TAU * float(b) / 3.0
				var off := Vector3(cos(ang), sin(ang), 0) * r * 0.55 * bore
				var rad2 := 0.02 * s * bore
				bit.bare()
				bit.turned(off + Vector3(0, 0, -0.065 * s), off + Vector3(0, 0, -0.065 * s - tip_len * 0.78), PackedVector2Array([Vector2(rad2, 0.0), Vector2(rad2, tip_len * 0.62), Vector2(rad2 * 0.6, tip_len * 0.78)]), Pal.STEEL_DARK, 8)
				bit.spiral(off + Vector3(0, 0, -0.07 * s), off + Vector3(0, 0, -0.065 * s - tip_len * 0.74), rad2, rad2 * 0.7, 2.2, tip_len * 0.08, rad2 * 0.45, Pal.STEEL, 26, ang)
				bit.gloss().set_emission(0.25)
				bit.crystal(off + Vector3(0, 0, -0.065 * s - tip_len * 0.76), off + Vector3(0, 0, -0.065 * s - tip_len), rad2 * 0.75, Color("#bfeee9"), 6, 0.3)
				bit.set_emission(0.0)
			# centre pilot bit
			bit.bare()
			bit.turned(Vector3(0, 0, -0.065 * s), Vector3(0, 0, -0.065 * s - tip_len * 0.5), PackedVector2Array([Vector2(0.012 * s, 0.0), Vector2(0.012 * s, tip_len * 0.36), Vector2(0.0, tip_len * 0.5)]), Pal.STEEL, 8)
			tip_len += 0.065 * s
		_:
			# boring head: a wide stepped cone with rows of cutters and a pilot spike
			tip_len = 0.3 * s
			var hr := r * 1.35 * bore
			bit.cast()
			bit.turned(Vector3(0, 0, -0.04 * s), Vector3(0, 0, -0.04 * s - tip_len), PackedVector2Array([Vector2(r * 0.55, 0.0), Vector2(hr, 0.02 * s), Vector2(hr, 0.05 * s), Vector2(hr * 0.72, 0.1 * s),
				Vector2(hr * 0.72, 0.125 * s), Vector2(hr * 0.42, 0.19 * s), Vector2(hr * 0.42, 0.21 * s), Vector2(0.0, tip_len)]), Pal.GRAPHITE, 16)
			bit.paint()
			bit.turned(Vector3(0, 0, -0.062 * s), Vector3(0, 0, -0.088 * s), PackedVector2Array([Vector2(hr + 0.0015, 0.0), Vector2(hr + 0.0015, 0.026 * s)]), Pal.AMBER, 16)
			bit.bare()
			var rows := [[hr, 0.075 * s, 8], [hr * 0.72, 0.15 * s, 6], [hr * 0.42, 0.235 * s, 4]]
			for row: Array in rows:
				var rr: float = row[0]
				for c in int(row[2]):
					var a := TAU * float(c) / float(int(row[2])) + rr * 30.0
					var p := Vector3(cos(a) * rr, sin(a) * rr, -0.04 * s - float(row[1]))
					var tb := Basis(Vector3(-sin(a), cos(a), 0), Vector3(0, 0, -1), Vector3(cos(a), sin(a), 0))
					bit.prism(PackedVector2Array([Vector2(-0.012 * s, -0.012 * s), Vector2(0.0, 0.026 * s), Vector2(0.012 * s, -0.012 * s)]), -0.006 * s, 0.012 * s, Transform3D(tb, p), Pal.STEEL)
			for k in 2:
				bit.spiral(Vector3(0, 0, -0.045 * s), Vector3(0, 0, -0.04 * s - tip_len * 0.96), hr * 0.98, hr * 0.06, 1.4, 0.016 * s, 0.012 * s, Pal.STEEL_DARK, 40, PI * float(k))
			tip_len += 0.04 * s
	# Fracture Bit (mod): carbide studs on the chuck
	if fracture > 0:
		bit.surf(0.3, 0.6)
		for i in 4 * fracture:
			var a2 := TAU * float(i) / float(4 * fracture)
			var p2 := Vector3(cos(a2), sin(a2), 0) * r * 0.7 + Vector3(0, 0, -0.022 * s)
			var sb := MeshKit._basis_from_y(Vector3(cos(a2), sin(a2), 0))
			bit.lathe(PackedVector2Array([Vector2(0.008 * s, 0.0), Vector2(0.0, 0.016 * s)]), Transform3D(sb, p2), Pal.BRASS, 4, false, true)
	_part(spin, bit, mat, "Bit")
	out["spin"] = spin
	_muzzle(out, Vector3(0, 0, nose_z - shaft - tip_len))


# ------------------------------------------------------------------ vacuum

static func _vacuum(out: Dictionary, tier: int, mods: Dictionary, mat: Material) -> void:
	var root: Node3D = out["root"]
	var kit := MeshKit.new()
	var nozzle_len := 0.2 + 0.06 * float(mods.get("long_nozzle", 0))
	var mouth := 1.0 + 0.16 * float(mods.get("wide_mouth", 0))
	var s := 1.0 if tier == 1 else 1.18
	# ---- motor body
	kit.paint()
	kit.block(Vector3(0, 0.0, 0.0), Vector3(0.12, 0.11, 0.2) * s, Pal.HULL, 0.024 * s)
	kit.block(Vector3(0, 0.0, 0.105 * s), Vector3(0.11, 0.1, 0.025) * s, Pal.GRAPHITE, 0.012 * s)
	kit.block(Vector3(0, 0.0, 0.03 * s), Vector3(0.1215, 0.1115, 0.02) * s, Pal.AMBER, 0.005)
	# rear exhaust grille
	kit.louvre(Transform3D(Basis.IDENTITY, Vector3(0, 0.0, 0.118 * s)), Vector3(0.08, 0.07, 0.012) * s, 5, Pal.CHARCOAL, Pal.GRAPHITE)
	kit.louvre(Transform3D(Basis.from_euler(Vector3(0, -PI * 0.5, 0)), Vector3(-0.0605 * s, 0.0, -0.03 * s)), Vector3(0.09, 0.045, 0.01) * s, 4, Pal.CHARCOAL, Pal.GRAPHITE)
	_pistol_grip(kit, Vector3(0, -0.055 * s, 0.03 * s), 0.12 * s, s)
	_trigger(kit, Vector3(0, -0.058 * s, -0.012 * s), s)
	# ---- collection canister on top: clear cylinder between two caps, dust visible inside
	var cy := 0.095 * s
	kit.cast()
	kit.paint()
	kit.turned(Vector3(0, cy, 0.074 * s), Vector3(0, cy, 0.056 * s), PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.03 * s, 0.002), Vector2(0.04 * s, 0.01 * s), Vector2(0.04 * s, 0.018 * s)]), Pal.HULL_SHADE, 14, true)
	kit.cast()
	kit.tube(Vector3(0, cy, -0.07 * s), Vector3(0, cy, -0.084 * s), 0.04 * s, 0.04 * s, Pal.GRAPHITE, 14)
	kit.gloss()
	if tier == 1:
		kit.tube(Vector3(0, cy, 0.056 * s), Vector3(0, cy, -0.07 * s), 0.035 * s, 0.035 * s, Pal.GLASS, 14, false)
	else:
		# cyclone separator: the canister tapers and wears a spiral
		kit.turned(Vector3(0, cy, 0.056 * s), Vector3(0, cy, -0.07 * s), PackedVector2Array([Vector2(0.037 * s, 0.0), Vector2(0.037 * s, 0.05 * s), Vector2(0.026 * s, 0.126 * s)]), Pal.GLASS, 14)
		kit.paint()
		kit.spiral(Vector3(0, cy, 0.05 * s), Vector3(0, cy, -0.066 * s), 0.0375 * s, 0.027 * s, 1.5, 0.008 * s, 0.003 * s, Pal.HULL, 30)
	kit.matte()
	kit.tube(Vector3(0, cy - 0.012 * s, 0.05 * s), Vector3(0, cy - 0.012 * s, -0.064 * s), 0.022 * s, 0.018 * s, Pal.ROCK_WARM.darkened(0.15), 8)
	kit.bare()
	kit.pipe(PackedVector3Array([Vector3(0, cy + 0.03 * s, -0.08 * s), Vector3(0, cy + 0.04 * s, -0.12 * s), Vector3(0, 0.03 * s, -0.15 * s)]), 0.009 * s, Pal.STEEL_DARK, 6)
	_lamp(kit, Vector3(0.0, cy + 0.04 * s, 0.064 * s), Pal.TEAL, 0.006 * s)
	# ---- corrugated hose coupling
	kit.rubber()
	for i in 5:
		var z := (-0.105 - 0.013 * float(i)) * s
		kit.tube(Vector3(0, 0, z), Vector3(0, 0, z - 0.008 * s), 0.036 * s, 0.036 * s, Pal.CHARCOAL if i % 2 == 0 else Pal.RUBBER, 12)
	kit.tube(Vector3(0, 0, -0.1 * s), Vector3(0, 0, -0.17 * s), 0.031 * s, 0.031 * s, Pal.RUBBER, 12)
	# ---- nozzle: straight throat, then a flared mouth with an amber lip
	var nz := -0.17 * s
	var mr := 0.062 * s * mouth
	kit.paint()
	kit.turned(Vector3(0, 0, nz), Vector3(0, 0, nz - nozzle_len), PackedVector2Array([Vector2(0.034 * s, 0.0), Vector2(0.034 * s, nozzle_len * 0.45), Vector2(mr, nozzle_len * 0.96), Vector2(mr, nozzle_len)]), Pal.HULL, 16)
	kit.turned(Vector3(0, 0, nz - nozzle_len * 0.92), Vector3(0, 0, nz - nozzle_len - 0.004), PackedVector2Array([Vector2(mr + 0.002, 0.0), Vector2(mr + 0.004, nozzle_len * 0.08), Vector2(mr - 0.004, nozzle_len * 0.08 + 0.004)]), Pal.AMBER, 16)
	kit.rubber()
	kit.turned(Vector3(0, 0, nz - nozzle_len), Vector3(0, 0, nz - nozzle_len * 0.5), PackedVector2Array([Vector2(mr - 0.004, 0.0), Vector2(0.03 * s, nozzle_len * 0.5)]), Pal.CHARCOAL, 16)
	kit.cast()
	kit.tube(Vector3(0, 0, nz - 0.004), Vector3(0, 0, nz - 0.02 * s), 0.038 * s, 0.038 * s, Pal.GRAPHITE, 12)
	if int(mods.get("long_nozzle", 0)) > 0:
		# extension collars
		kit.cast()
		for i in int(mods.get("long_nozzle", 0)):
			var cz := nz - nozzle_len * (0.2 + 0.14 * float(i))
			kit.tube(Vector3(0, 0, cz), Vector3(0, 0, cz - 0.01 * s), 0.0375 * s, 0.0375 * s, Pal.GRAPHITE, 12)
	if tier >= 2:
		# twin turbines on the flanks
		for sx: float in [-1.0, 1.0]:
			var tx := 0.088 * s * sx
			kit.paint()
			kit.turned(Vector3(tx, 0.005 * s, 0.09 * s), Vector3(tx, 0.005 * s, -0.09 * s), PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.02 * s, 0.004), Vector2(0.03 * s, 0.03 * s), Vector2(0.03 * s, 0.14 * s), Vector2(0.034 * s, 0.18 * s)]), Pal.HULL_SHADE, 12, true)
			kit.cast()
			kit.turned(Vector3(tx, 0.005 * s, -0.082 * s), Vector3(tx, 0.005 * s, -0.096 * s), PackedVector2Array([Vector2(0.036 * s, 0.0), Vector2(0.036 * s, 0.014 * s), Vector2(0.026 * s, 0.014 * s)]), Pal.GRAPHITE, 12)
			kit.rubber()
			kit.tube(Vector3(tx, 0.005 * s, -0.094 * s), Vector3(tx, 0.005 * s, -0.086 * s), 0.026 * s, 0.026 * s, Pal.CHARCOAL, 12)
			kit.surf(0.25).set_emission(1.2)
			kit.block(Vector3(tx + 0.031 * s * sx, 0.005 * s, 0.0), Vector3(0.004, 0.012, 0.07) * s, Pal.TEAL, 0.002)
			kit.set_emission(0.0)
			kit.bare()
			kit.tube(Vector3(0.06 * s * sx, 0.005 * s, 0.03 * s), Vector3(tx - 0.02 * s * sx, 0.005 * s, 0.03 * s), 0.01 * s, 0.01 * s, Pal.STEEL_DARK, 6)
	_part(root, kit, mat, "Body")
	# ---- intake fan inside the mouth
	var spin := _node(root, "Spin", Vector3(0, 0, nz - nozzle_len * 0.62))
	var fan := MeshKit.new().cast()
	for i in 5:
		var a := TAU * float(i) / 5.0
		fan.hbox(Transform3D(Basis.from_euler(Vector3(0, 0, a)) * Basis.from_euler(Vector3(0, 0.55, 0)), Vector3(cos(a + PI * 0.5), sin(a + PI * 0.5), 0) * 0.019 * s), Vector3(0.012 * s, 0.03 * s, 0.003), Pal.STEEL_DARK, 0.001)
	fan.tube(Vector3(0, 0, 0.008), Vector3(0, 0, -0.012), 0.008 * s, 0.006 * s, Pal.GRAPHITE, 8)
	_part(spin, fan, mat, "Fan")
	out["spin"] = spin
	_muzzle(out, Vector3(0, 0, nz - nozzle_len))


# ------------------------------------------------------------------ cannon

static func _cannon(out: Dictionary, tier: int, mods: Dictionary, mat: Material) -> void:
	var root: Node3D = out["root"]
	var kit := MeshKit.new()
	var big := 1.0 + 0.09 * float(mods.get("bigger_boom", 0))
	var fuse := int(mods.get("quick_fuse", 0))
	var s := 1.0 if tier == 1 else 1.22
	var br := 0.05 * s * big           # bore radius
	var y := 0.025 * s                 # barrel axis height above the grip
	var len := (0.36 if tier == 1 else 0.46) * s
	# ---- receiver
	kit.paint()
	kit.block(Vector3(0, y, 0.06 * s), Vector3(0.115, 0.12, 0.2) * s, Pal.HULL, 0.024 * s)
	kit.block(Vector3(0, y, 0.165 * s), Vector3(0.105, 0.11, 0.022) * s, Pal.GRAPHITE, 0.01 * s)
	kit.block(Vector3(0, y, 0.0), Vector3(0.1165, 0.1215, 0.02) * s, Pal.AMBER, 0.005)
	# breech lever on the left
	kit.bare()
	kit.tube(Vector3(-0.058 * s, y + 0.02 * s, 0.09 * s), Vector3(-0.075 * s, y + 0.02 * s, 0.09 * s), 0.008 * s, 0.008 * s, Pal.STEEL, 8)
	kit.rubber()
	kit.sphere(Vector3(-0.082 * s, y + 0.02 * s, 0.09 * s), 0.012 * s, Pal.RUBBER, Vector3.ONE, 8, 5)
	# shoulder stock stub
	kit.rubber()
	kit.block(Vector3(0, y - 0.01 * s, 0.2 * s), Vector3(0.07, 0.1, 0.05) * s, Pal.RUBBER, 0.02 * s)
	# charge cells on the left (lit = loaded); Quick Fuse adds an auto-loader rail with more cells
	for i in 3:
		_lamp(kit, Vector3(-0.0585 * s, y - 0.02 * s, (0.04 + 0.03 * float(i)) * s), Pal.AMBER, 0.006 * s, 1.5)
	if fuse > 0:
		kit.cast()
		kit.block(Vector3(-0.07 * s, y + 0.055 * s, 0.07 * s), Vector3(0.03, 0.03, 0.15) * s, Pal.GRAPHITE, 0.008 * s)
		for i in 2 + 2 * fuse:
			kit.paint()
			kit.turned(Vector3(-0.07 * s, y + 0.07 * s, (0.13 - 0.022 * float(i)) * s), Vector3(-0.07 * s, y + 0.094 * s, (0.13 - 0.022 * float(i)) * s),
				PackedVector2Array([Vector2(0.008 * s, 0.0), Vector2(0.008 * s, 0.018 * s), Vector2(0.0, 0.024 * s)]), Pal.AMBER, 8)
	_pistol_grip(kit, Vector3(0, y - 0.058 * s, 0.07 * s), 0.12 * s, s)
	_trigger(kit, Vector3(0, y - 0.062 * s, 0.03 * s), s)
	# foregrip
	kit.cast()
	kit.block(Vector3(0, y - 0.075 * s, -0.14 * s), Vector3(0.03, 0.03, 0.05) * s, Pal.GRAPHITE, 0.008 * s)
	kit.rubber()
	kit.tube(Vector3(0, y - 0.085 * s, -0.14 * s), Vector3(0, y - 0.17 * s, -0.125 * s), 0.016 * s, 0.015 * s, Pal.RUBBER, 8)
	# sight: a simple ring on a post
	kit.cast()
	kit.block(Vector3(0, y + 0.07 * s, 0.03 * s), Vector3(0.012, 0.025, 0.012) * s, Pal.GRAPHITE, 0.003)
	kit.torus(Transform3D(Basis.from_euler(Vector3(PI * 0.5, 0, 0)), Vector3(0, y + 0.098 * s, 0.03 * s)), 0.013 * s, 0.0025 * s, Pal.GRAPHITE, 12, 5)
	_part(root, kit, mat, "Body")

	# ---- barrel assembly (recoils along Z)
	var recoil := _node(root, "Recoil", Vector3(0, y, -0.04 * s))
	var bk := MeshKit.new()
	bk.cast()
	bk.turned(Vector3.ZERO, Vector3(0, 0, -len), PackedVector2Array([Vector2(br + 0.016 * s, 0.0), Vector2(br + 0.016 * s, len * 0.3), Vector2(br + 0.008 * s, len * 0.34),
		Vector2(br + 0.008 * s, len * 0.82), Vector2(br + 0.02 * s, len * 0.86), Vector2(br + 0.02 * s, len), Vector2(br, len)]), Pal.GRAPHITE, 18)
	# bore
	bk.rubber()
	bk.turned(Vector3(0, 0, -len), Vector3(0, 0, -len * 0.6), PackedVector2Array([Vector2(br, 0.0), Vector2(br * 0.9, len * 0.4), Vector2(0.0, len * 0.4)]), Pal.CHARCOAL, 18)
	# painted shroud over the rear half with a belt stripe
	bk.paint()
	bk.turned(Vector3(0, 0, -0.01 * s), Vector3(0, 0, -len * 0.3), PackedVector2Array([Vector2(br + 0.019 * s, 0.0), Vector2(br + 0.019 * s, len * 0.3 - 0.016 * s), Vector2(br + 0.016 * s, len * 0.3 - 0.01 * s)]), Pal.HULL, 18)
	# muzzle brake slots
	bk.rubber()
	for i in 3:
		var mz := -len * (0.88 + 0.035 * float(i))
		for a: float in [0.0, PI * 0.5, PI, PI * 1.5]:
			bk.hbox(Transform3D(Basis.from_euler(Vector3(0, 0, a)), Vector3(cos(a + PI * 0.5), sin(a + PI * 0.5), 0) * (br + 0.02 * s) + Vector3(0, 0, mz)), Vector3(0.022 * s, 0.003, 0.008 * s), Pal.CHARCOAL, 0.001)
	if tier >= 2:
		# Planet Cracker: heat-sink discs, three energy coils and stabiliser vanes
		bk.cast()
		for i in 5:
			var fz := -len * (0.38 + 0.045 * float(i))
			bk.tube(Vector3(0, 0, fz), Vector3(0, 0, fz - 0.005 * s), br + 0.022 * s, br + 0.022 * s, Pal.STEEL_DARK, 16)
		bk.surf(0.25).set_emission(1.5)
		for i in 3:
			var ez := -len * (0.64 + 0.06 * float(i))
			bk.turned(Vector3(0, 0, ez), Vector3(0, 0, ez - 0.01 * s), PackedVector2Array([Vector2(br + 0.0095 * s, 0.0), Vector2(br + 0.0095 * s, 0.01 * s)]), Pal.TEAL, 16)
		bk.set_emission(0.0)
		bk.paint()
		for i in 3:
			var va := TAU * float(i) / 3.0 + PI * 0.5
			var vb := Basis(Vector3(0, 0, -1), Vector3(cos(va), sin(va), 0), Vector3(-sin(va), cos(va), 0))
			bk.prism(PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.09 * s, 0.0), Vector2(0.07 * s, 0.03 * s), Vector2(0.015 * s, 0.03 * s)]), -0.004, 0.004,
				Transform3D(vb, Vector3(cos(va), sin(va), 0) * (br + 0.018 * s) + Vector3(0, 0, -len * 0.84)), Pal.HULL_SHADE)
		# capacitor tank under the receiver end of the barrel
		bk.paint()
		bk.turned(Vector3(0, -br - 0.04 * s, -0.01 * s), Vector3(0, -br - 0.04 * s, -len * 0.3), PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.022 * s, 0.006), Vector2(0.026 * s, 0.02 * s),
			Vector2(0.026 * s, len * 0.3 - 0.03 * s), Vector2(0.0, len * 0.3 - 0.01 * s)]), Pal.HULL_SHADE, 12, true)
	# Bigger Boom (mod): reinforcing bands around the chamber, one per level
	for i in int(mods.get("bigger_boom", 0)):
		var bz := -len * (0.31 + 0.05 * float(i))
		bk.bare()
		bk.tube(Vector3(0, 0, bz), Vector3(0, 0, bz - 0.012 * s), br + 0.0125 * s, br + 0.0125 * s, Pal.BRASS, 16)
	_part(recoil, bk, mat, "Barrel")
	out["recoil"] = recoil
	_muzzle(out, Vector3(0, y, -0.04 * s - len))
