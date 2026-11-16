class_name ToolModels
extends RefCounted
## Procedural models for every tool tier. Each tier has its own silhouette and colours, and
## purchased mods add visible parts, so an upgrade is always something you can SEE.
##
## Convention: the grip is at the origin, the working end points along -Z, +Y is up.
## build() returns {"root": Node3D, "spin": Node3D or null, "piston": Node3D or null,
##                  "muzzle": Node3D} - spin/piston are animated by ToolController.

const WOOD := Color("#b07a45")
const WOOD_DARK := Color("#7a4e2a")
const RUST := Color("#c26a3a")
const RUST_DARK := Color("#8f4526")
const STEEL := Color("#cfd8ea")
const STEEL_DARK := Color("#7f8aa6")
const BLUE := Color("#4f8dff")
const BLUE_DARK := Color("#2f5fd0")
const YELLOW := Color("#ffd23f")
const ORANGE := Color("#ff9438")
const RED := Color("#ff5d5d")
const TEAL := Color("#39d6c4")
const TEAL_DARK := Color("#1f9c94")
const PURPLE := Color("#a478ff")
const PURPLE_DARK := Color("#6a48c9")
const PINK := Color("#ff6f9f")
const INK := Color("#2a2540")
const WHITE := Color("#f6f3ff")
const GLOW_CYAN := Color("#8ffcff")
const GLOW_YELLOW := Color("#fff08a")


static func build(family_id: String, tier: int, mods: Dictionary = {}, viewmodel := true) -> Dictionary:
	var root := Node3D.new()
	root.name = "Tool_%s_%d" % [family_id, tier]
	var mat: ShaderMaterial = MeshKit.new_viewmodel_material() if viewmodel else MeshKit.new_material()
	var out := {"root": root, "spin": null, "piston": null, "muzzle": null, "material": mat}
	match family_id:
		"shovel": _shovel(out, tier, mods, mat)
		"drill": _drill(out, tier, mods, mat)
		"vacuum": _vacuum(out, tier, mods, mat)
		"cannon": _cannon(out, tier, mods, mat)
	if out["muzzle"] == null:
		var m := Node3D.new()
		m.name = "Muzzle"
		m.position = Vector3(0, 0, -0.6)
		root.add_child(m)
		out["muzzle"] = m
	return out


static func _part(parent: Node3D, kit: MeshKit, mat: Material, part_name: String, pos := Vector3.ZERO) -> MeshInstance3D:
	var mi := kit.instance(mat, false)
	mi.name = part_name
	mi.position = pos
	parent.add_child(mi)
	return mi


static func _muzzle(out: Dictionary, pos: Vector3) -> void:
	var m := Node3D.new()
	m.name = "Muzzle"
	m.position = pos
	(out["root"] as Node3D).add_child(m)
	out["muzzle"] = m


# ------------------------------------------------------------------ shovels

static func _shovel(out: Dictionary, tier: int, mods: Dictionary, mat: Material) -> void:
	var root: Node3D = out["root"]
	var kit := MeshKit.new()
	var wide := 1.0 + 0.16 * float(mods.get("wide_scoop", 0))
	var quick := int(mods.get("quick_hands", 0))
	var teeth := int(mods.get("ore_tooth", 0))
	var trench := int(mods.get("trench_blade", 0)) > 0
	var tilt := Basis.from_euler(Vector3(deg_to_rad(-14.0), 0, 0))
	var tip_z := -0.7
	match tier:
		1:
			# Rusty Scoop: stubby wooden handle, small dented rust blade.
			kit.tube(Vector3(0, 0, 0.2), Vector3(0, 0, -0.36), 0.024, 0.021, WOOD, 8)
			kit.sphere(Vector3(0, 0, 0.22), 0.036, WOOD_DARK, Vector3.ONE, 8, 5)
			kit.tube(Vector3(0, 0, -0.34), Vector3(0, 0, -0.42), 0.03, 0.036, STEEL_DARK, 8)
			kit.rbox(Transform3D(tilt, Vector3(0, -0.012, -0.53)), Vector3(0.21 * wide, 0.04, 0.27), RUST, 0.45)
			kit.rbox(Transform3D(tilt, Vector3(0.03, 0.0, -0.5)), Vector3(0.05, 0.036, 0.07), RUST_DARK, 0.6)
			kit.rbox(Transform3D(tilt, Vector3(-0.04, 0.0, -0.57)), Vector3(0.04, 0.036, 0.05), RUST_DARK, 0.6)
			tip_z = -0.64
		2:
			# Sturdy Spade: long yellow shaft, red D-grip, pointed blue-steel blade.
			kit.tube(Vector3(0, 0, 0.16), Vector3(0, 0, -0.42), 0.023, 0.021, YELLOW, 8)
			kit.torus(Transform3D(Basis.from_euler(Vector3(0, 0, PI * 0.5)), Vector3(0, 0, 0.23)), 0.055, 0.019, RED, 14, 6)
			kit.tube(Vector3(0, 0, -0.4), Vector3(0, 0, -0.48), 0.03, 0.04, STEEL_DARK, 8)
			kit.rbox(Transform3D(tilt, Vector3(0, -0.012, -0.6)), Vector3(0.26 * wide, 0.04, 0.3), BLUE, 0.4)
			kit.cone(Vector3(0, -0.04, -0.73), Vector3(0, -0.08, -0.88), 0.11 * wide, BLUE_DARK, 4)
			kit.rbox(Transform3D(tilt, Vector3(0, 0.01, -0.52)), Vector3(0.22 * wide, 0.03, 0.035), STEEL, 0.5)
			tip_z = -0.82
		3:
			# Thumper 3000: orange power unit with a piston driving a chunky hazard blade.
			kit.rbox(Transform3D(Basis.IDENTITY, Vector3(0, 0.0, -0.08)), Vector3(0.13, 0.13, 0.34), ORANGE, 0.4)
			kit.rbox(Transform3D(Basis.IDENTITY, Vector3(0, -0.11, 0.02)), Vector3(0.06, 0.16, 0.07), INK, 0.5)
			kit.tube(Vector3(0.085, 0.02, -0.02), Vector3(0.085, 0.02, -0.2), 0.035, 0.035, STEEL, 8)
			kit.sphere(Vector3(0.085, 0.02, -0.02), 0.035, STEEL, Vector3.ONE, 8, 5)
			kit.set_emission(1.6)
			kit.sphere(Vector3(0, 0.072, -0.02), 0.022, GLOW_CYAN, Vector3.ONE, 8, 5)
			kit.set_emission(0.0)
			kit.tube(Vector3(0, 0, -0.25), Vector3(0, 0, -0.33), 0.05, 0.042, STEEL_DARK, 10)
			kit.rbox(Transform3D(Basis.IDENTITY, Vector3(-0.07, 0.03, -0.1)), Vector3(0.03, 0.05, 0.2), YELLOW, 0.5)
			# moving head
			var head := MeshKit.new()
			head.tube(Vector3(0, 0, 0.02), Vector3(0, 0, -0.2), 0.03, 0.03, STEEL, 8)
			head.rbox(Transform3D(tilt, Vector3(0, -0.02, -0.32)), Vector3(0.26 * wide, 0.045, 0.3), YELLOW, 0.4)
			head.rbox(Transform3D(tilt, Vector3(0, -0.018, -0.25)), Vector3(0.265 * wide, 0.047, 0.045), INK, 0.4)
			head.rbox(Transform3D(tilt, Vector3(0, -0.018, -0.37)), Vector3(0.265 * wide, 0.047, 0.045), INK, 0.4)
			head.cone(Vector3(0, -0.055, -0.45), Vector3(0, -0.095, -0.58), 0.11 * wide, STEEL, 4)
			_add_blade_mods(head, tilt, wide, teeth, trench, -0.47, 0.13)
			var piston := Node3D.new()
			piston.name = "Piston"
			piston.position = Vector3(0, 0, -0.32)
			root.add_child(piston)
			_part(piston, head, mat, "Head")
			out["piston"] = piston
			tip_z = -0.9
		_:
			# Mega Scooper: hydraulic bucket with teeth and twin rams.
			kit.rbox(Transform3D(Basis.IDENTITY, Vector3(0, 0.0, -0.06)), Vector3(0.17, 0.16, 0.4), PURPLE, 0.4)
			kit.rbox(Transform3D(Basis.IDENTITY, Vector3(0, -0.13, 0.03)), Vector3(0.065, 0.18, 0.075), INK, 0.5)
			kit.rbox(Transform3D(Basis.IDENTITY, Vector3(0, 0.09, -0.02)), Vector3(0.09, 0.05, 0.2), YELLOW, 0.5)
			kit.set_emission(1.8)
			kit.sphere(Vector3(0.0, 0.125, -0.02), 0.025, GLOW_YELLOW, Vector3.ONE, 8, 5)
			kit.sphere(Vector3(0.0, 0.125, -0.09), 0.025, GLOW_CYAN, Vector3.ONE, 8, 5)
			kit.set_emission(0.0)
			for sx: float in [-1.0, 1.0]:
				kit.tube(Vector3(0.1 * sx, 0.0, 0.0), Vector3(0.1 * sx, 0.0, -0.26), 0.036, 0.036, STEEL, 8)
				kit.tube(Vector3(0.1 * sx, 0.0, -0.26), Vector3(0.1 * sx, -0.01, -0.4), 0.022, 0.022, WHITE, 8)
			var bucket := MeshKit.new()
			bucket.rbox(Transform3D(tilt, Vector3(0, -0.03, -0.32)), Vector3(0.42 * wide, 0.06, 0.36), YELLOW, 0.35)
			for sx2: float in [-1.0, 1.0]:
				bucket.rbox(Transform3D(tilt, Vector3(0.2 * wide * sx2, 0.02, -0.32)), Vector3(0.04, 0.14, 0.36), ORANGE, 0.4)
			bucket.rbox(Transform3D(tilt, Vector3(0, 0.03, -0.17)), Vector3(0.42 * wide, 0.14, 0.05), ORANGE, 0.4)
			for i in 5:
				var tx := (float(i) - 2.0) * 0.085 * wide
				bucket.cone(Vector3(tx, -0.07, -0.49), Vector3(tx, -0.1, -0.6), 0.03, STEEL, 5)
			_add_blade_mods(bucket, tilt, wide * 1.5, teeth, trench, -0.5, 0.2)
			var ram := Node3D.new()
			ram.name = "Piston"
			ram.position = Vector3(0, 0, -0.3)
			root.add_child(ram)
			_part(ram, bucket, mat, "Bucket")
			out["piston"] = ram
			tip_z = -0.95
	if tier <= 2:
		_add_blade_mods(kit, tilt, wide, teeth, trench, -0.6 if tier == 1 else -0.72, 0.075 if tier == 1 else 0.1)
	# Quick Hands: bright grip tape, one band per level.
	for i in quick:
		var z := 0.1 - float(i) * 0.07
		kit.tube(Vector3(0, 0, z), Vector3(0, 0, z - 0.035), 0.029, 0.029, [PINK, TEAL, WHITE][i % 3], 8)
	_part(root, kit, mat, "Body")
	_muzzle(out, Vector3(0, -0.05, tip_z))


static func _add_blade_mods(kit: MeshKit, tilt: Basis, wide: float, teeth: int, trench: bool, front_z: float, half_w: float) -> void:
	# Ore Tooth: serrated steel teeth along the leading edge.
	if teeth > 0:
		var n := 3 + teeth
		for i in n:
			var x := lerpf(-half_w, half_w, float(i) / float(n - 1)) * wide
			kit.cone(Vector3(x, -0.045, front_z), Vector3(x, -0.07, front_z - 0.07), 0.018, STEEL, 4)
	# Trench Blade: a long centre fin.
	if trench:
		kit.rbox(Transform3D(tilt, Vector3(0, 0.03, front_z + 0.1)), Vector3(0.022, 0.07, 0.34), TEAL, 0.5)
		kit.set_emission(1.2)
		kit.sphere(Vector3(0, 0.07, front_z + 0.22), 0.016, GLOW_CYAN, Vector3.ONE, 6, 4)
		kit.set_emission(0.0)


# ------------------------------------------------------------------ drills

static func _drill(out: Dictionary, tier: int, mods: Dictionary, mat: Material) -> void:
	var root: Node3D = out["root"]
	var kit := MeshKit.new()
	var bore := 1.0 + 0.14 * float(mods.get("wide_bore", 0))
	var turbo := int(mods.get("turbo", 0))
	var fracture := int(mods.get("fracture_bit", 0))
	var shaft := 0.12 * float(mods.get("long_shaft", 0))
	var body_col := TEAL if tier == 1 else (WHITE if tier == 2 else ORANGE)
	var body_dark := TEAL_DARK if tier == 1 else (BLUE if tier == 2 else RED)
	var s := 1.0 if tier < 3 else 1.22
	# body + grip
	kit.rbox(Transform3D(Basis.IDENTITY, Vector3(0, 0.0, -0.05)), Vector3(0.15, 0.15, 0.36) * s, body_col, 0.4)
	kit.rbox(Transform3D(Basis.IDENTITY, Vector3(0, -0.13 * s, 0.03)), Vector3(0.06, 0.19, 0.07) * s, INK, 0.5)
	kit.rbox(Transform3D(Basis.IDENTITY, Vector3(0, -0.07 * s, -0.12)), Vector3(0.05, 0.05, 0.12) * s, YELLOW, 0.5)
	kit.rbox(Transform3D(Basis.IDENTITY, Vector3(0, 0.085 * s, -0.02)), Vector3(0.08, 0.04, 0.2) * s, body_dark, 0.5)
	kit.tube(Vector3(0, 0, -0.22 * s), Vector3(0, 0, -0.3 * s - shaft), 0.062 * s, 0.05 * s, STEEL_DARK, 10)
	# vents
	for i in 3:
		kit.rbox(Transform3D(Basis.IDENTITY, Vector3(0.077 * s, 0.01, (-0.12 + 0.07 * i) * s)), Vector3(0.012, 0.07, 0.03) * s, INK, 0.5)
	# Turbo Motor: exhaust pipes, one per level
	for i in turbo:
		var px := (-0.05 + 0.05 * float(i)) * s
		kit.tube(Vector3(px, 0.07 * s, 0.1 * s), Vector3(px, 0.11 * s, 0.17 * s), 0.016 * s, 0.02 * s, STEEL, 6)
	kit.set_emission(1.6)
	kit.sphere(Vector3(-0.05 * s, 0.078 * s, 0.11 * s), 0.016 * s, GLOW_CYAN if tier != 3 else GLOW_YELLOW, Vector3.ONE, 6, 4)
	kit.set_emission(0.0)
	_part(root, kit, mat, "Body")

	# spinning bit
	var spin := Node3D.new()
	spin.name = "Spin"
	spin.position = Vector3(0, 0, -0.3 * s - shaft)
	root.add_child(spin)
	var bit := MeshKit.new()
	var bit_col := STEEL if tier == 1 else GLOW_CYAN
	var tip_len := (0.34 if tier < 3 else 0.5) * s
	if tier == 2:
		bit.set_emission(0.5)
	var count := 1 if tier != 2 else 3
	for b in count:
		var off := Vector3.ZERO
		if count > 1:
			var ang := TAU * float(b) / float(count)
			off = Vector3(cos(ang), sin(ang), 0) * 0.04 * s * bore
		var rad := (0.075 if count == 1 else 0.045) * s * bore
		bit.cone(off, off + Vector3(0, 0, -tip_len), rad, bit_col, 8)
		# spiral ridges
		for r in 4:
			var f := float(r) / 4.0
			var ring_r := rad * (1.0 - f) + 0.004
			bit.torus(Transform3D(Basis.from_euler(Vector3(PI * 0.5, 0, 0.35)), off + Vector3(0, 0, -tip_len * (f + 0.08))), ring_r, 0.012 * s, STEEL_DARK if tier == 1 else WHITE, 10, 5)
	bit.set_emission(0.0)
	if tier == 3:
		bit.tube(Vector3.ZERO, Vector3(0, 0, -0.06), 0.11 * s * bore, 0.09 * s * bore, YELLOW, 10)
	# Fracture Bit: pink carbide studs
	if fracture > 0:
		bit.set_emission(0.8)
		for i in 3 * fracture:
			var a := TAU * float(i) / float(3 * fracture)
			bit.sphere(Vector3(cos(a), sin(a), 0) * 0.06 * s * bore + Vector3(0, 0, -0.05), 0.014 * s, PINK, Vector3.ONE, 6, 4)
		bit.set_emission(0.0)
	_part(spin, bit, mat, "Bit")
	out["spin"] = spin
	_muzzle(out, Vector3(0, 0, -0.3 * s - shaft - tip_len))


# ------------------------------------------------------------------ vacuum

static func _vacuum(out: Dictionary, tier: int, mods: Dictionary, mat: Material) -> void:
	var root: Node3D = out["root"]
	var kit := MeshKit.new()
	var nozzle_len := 0.3 + 0.07 * float(mods.get("long_nozzle", 0))
	var mouth := 1.0 + 0.18 * float(mods.get("wide_mouth", 0))
	var body := PURPLE if tier == 1 else TEAL
	var body_dark := PURPLE_DARK if tier == 1 else TEAL_DARK
	# canister
	kit.rbox(Transform3D(Basis.IDENTITY, Vector3(0, 0.02, 0.0)), Vector3(0.18, 0.19, 0.3), body, 0.5)
	kit.sphere(Vector3(0, 0.1, 0.02), 0.08, WHITE, Vector3(1, 0.8, 1.2), 10, 6)
	kit.set_emission(1.2)
	kit.sphere(Vector3(0, 0.11, 0.02), 0.045, GLOW_CYAN if tier == 1 else GLOW_YELLOW, Vector3(1, 0.8, 1.2), 8, 5)
	kit.set_emission(0.0)
	kit.rbox(Transform3D(Basis.IDENTITY, Vector3(0, -0.13, 0.04)), Vector3(0.06, 0.17, 0.07), INK, 0.5)
	kit.rbox(Transform3D(Basis.IDENTITY, Vector3(0, 0.02, 0.16)), Vector3(0.12, 0.12, 0.05), body_dark, 0.5)
	# hose rings + nozzle
	for i in 3:
		kit.torus(Transform3D(Basis.from_euler(Vector3(PI * 0.5, 0, 0)), Vector3(0, 0.0, -0.17 - 0.04 * i)), 0.05, 0.014, INK if i % 2 == 0 else YELLOW, 12, 5)
	kit.tube(Vector3(0, 0, -0.26), Vector3(0, 0, -0.26 - nozzle_len), 0.045, 0.1 * mouth, WHITE, 12, false)
	kit.torus(Transform3D(Basis.from_euler(Vector3(PI * 0.5, 0, 0)), Vector3(0, 0, -0.26 - nozzle_len)), 0.1 * mouth, 0.018, YELLOW, 14, 6)
	if tier >= 2:
		for sx: float in [-1.0, 1.0]:
			kit.tube(Vector3(0.12 * sx, 0.03, 0.12), Vector3(0.12 * sx, 0.03, -0.12), 0.055, 0.05, WHITE, 10)
			kit.torus(Transform3D(Basis.from_euler(Vector3(PI * 0.5, 0, 0)), Vector3(0.12 * sx, 0.03, -0.12)), 0.05, 0.014, ORANGE, 12, 5)
	_part(root, kit, mat, "Body")
	# spinning fan inside the nozzle
	var spin := Node3D.new()
	spin.name = "Spin"
	spin.position = Vector3(0, 0, -0.26 - nozzle_len * 0.85)
	root.add_child(spin)
	var fan := MeshKit.new()
	for i in 4:
		var a := TAU * float(i) / 4.0
		fan.rbox(Transform3D(Basis.from_euler(Vector3(0.5, 0, a)), Vector3(cos(a), sin(a), 0) * 0.04 * mouth), Vector3(0.07 * mouth, 0.02, 0.03), PINK, 0.5)
	fan.sphere(Vector3.ZERO, 0.02, INK, Vector3.ONE, 6, 4)
	_part(spin, fan, mat, "Fan")
	out["spin"] = spin
	_muzzle(out, Vector3(0, 0, -0.26 - nozzle_len))


# ------------------------------------------------------------------ cannon

static func _cannon(out: Dictionary, tier: int, mods: Dictionary, mat: Material) -> void:
	var root: Node3D = out["root"]
	var kit := MeshKit.new()
	var big := 1.0 + 0.1 * float(mods.get("bigger_boom", 0))
	var fuse := int(mods.get("quick_fuse", 0))
	var s := 1.0 if tier == 1 else 1.3
	var body := PINK if tier == 1 else INK
	var trim := YELLOW if tier == 1 else GLOW_YELLOW
	kit.tube(Vector3(0, 0.02, 0.22 * s), Vector3(0, 0.02, -0.38 * s), 0.085 * s * big, 0.095 * s * big, body, 12)
	kit.torus(Transform3D(Basis.from_euler(Vector3(PI * 0.5, 0, 0)), Vector3(0, 0.02, -0.38 * s)), 0.1 * s * big, 0.028 * s, trim, 14, 6)
	kit.torus(Transform3D(Basis.from_euler(Vector3(PI * 0.5, 0, 0)), Vector3(0, 0.02, -0.1 * s)), 0.092 * s * big, 0.018 * s, WHITE, 14, 6)
	kit.torus(Transform3D(Basis.from_euler(Vector3(PI * 0.5, 0, 0)), Vector3(0, 0.02, 0.12 * s)), 0.09 * s * big, 0.018 * s, WHITE, 14, 6)
	kit.sphere(Vector3(0, 0.02, 0.22 * s), 0.085 * s * big, body.darkened(0.15), Vector3.ONE, 10, 6)
	kit.rbox(Transform3D(Basis.IDENTITY, Vector3(0, -0.12 * s, 0.0)), Vector3(0.06, 0.17, 0.07) * s, INK if tier == 1 else PURPLE, 0.5)
	kit.rbox(Transform3D(Basis.IDENTITY, Vector3(0, -0.1 * s, -0.2 * s)), Vector3(0.05, 0.1, 0.05) * s, INK if tier == 1 else PURPLE, 0.5)
	# sight
	kit.rbox(Transform3D(Basis.IDENTITY, Vector3(0, 0.13 * s, -0.05)), Vector3(0.03, 0.05, 0.12) * s, WHITE, 0.5)
	for i in fuse:
		kit.tube(Vector3(0.09 * s, 0.06, 0.1 - 0.1 * i), Vector3(0.14 * s, 0.1, 0.1 - 0.1 * i), 0.014, 0.014, TEAL, 6)
		kit.set_emission(1.5)
		kit.sphere(Vector3(0.14 * s, 0.1, 0.1 - 0.1 * i), 0.02, GLOW_CYAN, Vector3.ONE, 6, 4)
		kit.set_emission(0.0)
	kit.set_emission(2.0 if tier == 2 else 1.2)
	kit.sphere(Vector3(0, 0.02, -0.33 * s), 0.06 * s * big, GLOW_YELLOW if tier == 2 else ORANGE, Vector3.ONE, 10, 6)
	if tier == 2:
		for i in 3:
			kit.sphere(Vector3(0, 0.125 * s, 0.14 - 0.1 * i), 0.022, PINK, Vector3.ONE, 6, 4)
	kit.set_emission(0.0)
	_part(root, kit, mat, "Body")
	_muzzle(out, Vector3(0, 0.02, -0.42 * s))
