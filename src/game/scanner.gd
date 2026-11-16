class_name Scanner
extends Node3D
## Scanner gadget (Q). Sends a pulse ring through the ground: ore lights up in the terrain
## shader as the ring passes, and floating markers point at the richest deposits. Higher levels
## reach further and also reveal buried artifacts, hidden caverns and the planet's heart.

signal pulsed(found_ore: int, found_secrets: int)

const COOLDOWN := 3.5
const PULSE_SPEED := 26.0
const MARKER_LIFETIME := 12.0

var world: World
var cooldown := 0.0
var _pulse_origin := Vector3.ZERO
var _pulse_radius := -1.0
var _pulse_range := 0.0
var _markers: Array[Dictionary] = []     ## {node, life, pos}
var _marker_mesh: ArrayMesh


func setup(w: World) -> void:
	world = w


func _unhandled_input(event: InputEvent) -> void:
	if world == null or world.player == null or world.player.controls_locked:
		return
	if event.is_action_pressed("scan"):
		try_scan()


func can_scan() -> bool:
	return GameState.gear_level("scanner") > 0 and cooldown <= 0.0


func try_scan() -> bool:
	if GameState.gear_level("scanner") <= 0:
		world.message.emit("You need a scanner - buy the Pocket Pinger at the Outfitter.", "hint")
		return false
	if cooldown > 0.0:
		return false
	cooldown = COOLDOWN
	var origin := world.player.global_position + world.player.up * 1.0
	var max_range := GameState.scanner_range()
	_pulse_origin = origin
	_pulse_radius = 0.0
	_pulse_range = max_range
	Audio.play("scan", -2.0)
	GameState.add_stat("scans")

	var level := GameState.gear_level("scanner")
	# ore: coarse search of the deterministic geology, skipping anything already dug out
	var step := 2.0 if max_range <= 20.0 else (3.0 if max_range <= 34.0 else 5.0)
	var ores := world.planet.geology.find_ore_near(origin, max_range, step, 60)
	var shown := 0
	var used: Array[Vector3] = []
	for o in ores:
		if shown >= 5 + level * 2:
			break
		var p: Vector3 = o["pos"]
		if not world.planet.is_solid(p):
			continue
		var crowded := false
		for u in used:
			if u.distance_to(p) < 5.0:
				crowded = true
				break
		if crowded:
			continue
		used.append(p)
		var def: Dictionary = GameData.materials[int(o["mat"])]
		_add_marker(p, def["color2_c"], str(def["name"]), float(o["dist"]) / PULSE_SPEED)
		shown += 1
	var secrets_found := 0
	if level >= 2 and world.secrets != null:
		for t: Dictionary in world.secrets.call("scan_targets"):
			var p2: Vector3 = t["pos"]
			var d := p2.distance_to(origin)
			if d > max_range * (1.6 if level >= 3 else 1.0):
				continue
			var label := "?" if t["kind"] == "artifact" else ("Cavern" if t["kind"] == "place" else "Heart")
			_add_marker(p2, Pal.TEAL, label, d / PULSE_SPEED, 1.4)
			secrets_found += 1
	elif level == 1 and world.secrets != null:
		# The basic pinger cannot pinpoint secrets but it does chirp when one is close.
		for t: Dictionary in world.secrets.call("scan_targets"):
			if t["kind"] == "artifact" and (t["pos"] as Vector3).distance_to(origin) < max_range:
				_add_marker(t["pos"], Pal.TEAL, "?", (t["pos"] as Vector3).distance_to(origin) / PULSE_SPEED, 1.3)
				secrets_found += 1
				break
	if shown == 0 and secrets_found == 0:
		world.message.emit("Scanner: nothing interesting nearby. Try somewhere else or dig deeper.", "hint")
	pulsed.emit(shown, secrets_found)
	return true


func _add_marker(pos: Vector3, color: Color, text: String, delay: float, size := 1.0) -> void:
	if _marker_mesh == null:
		var kit := MeshKit.new()
		kit.surf(0.3)
		kit.emission = 1.6
		kit.crystal(Vector3(0, -0.2, 0), Vector3(0, 0.2, 0), 0.09, Color.WHITE, 4, 0.5)
		kit.crystal(Vector3(0, 0.0, 0), Vector3(0, -0.2, 0), 0.09, Color.WHITE, 4, 0.5)
		_marker_mesh = kit.commit()
	var node := Node3D.new()
	add_child(node)
	node.global_position = pos
	var mi := MeshInstance3D.new()
	mi.mesh = _marker_mesh
	var mat := MeshKit.new_material(1.0, 0.0)
	mat.set_shader_parameter("tint", color)
	mat.render_priority = 10
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.scale = Vector3.ONE * size
	node.add_child(mi)
	var l := Label3D.new()
	l.text = text
	l.font = UiTheme.font_bold()
	l.font_size = 48
	l.pixel_size = 0.0007
	l.fixed_size = true
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.modulate = color
	l.outline_size = 8
	l.outline_modulate = Color(0.06, 0.07, 0.09)
	l.render_priority = 6
	node.add_child(l)
	node.visible = false
	_markers.append({"node": node, "life": MARKER_LIFETIME + delay, "delay": delay, "pos": pos, "label": l, "mesh": mi, "text": text})


func _process(delta: float) -> void:
	cooldown = maxf(0.0, cooldown - delta)
	if world == null or world.planet == null:
		return
	if _pulse_radius >= 0.0:
		_pulse_radius += PULSE_SPEED * delta
		var strength := 1.0 - smoothstep(_pulse_range * 0.75, _pulse_range * 1.15, _pulse_radius)
		world.planet.set_scan_pulse(_pulse_origin, _pulse_radius, strength)
		if _pulse_radius > _pulse_range * 1.15 + 14.0:
			_pulse_radius = -1.0
			world.planet.set_scan_pulse(_pulse_origin, -1.0, 0.0)
	var i := _markers.size() - 1
	var up := world.player.up if world.player != null else Vector3.UP
	var eye := world.player.eye_position() if world.player != null else Vector3.ZERO
	while i >= 0:
		var m := _markers[i]
		m["life"] = float(m["life"]) - delta
		m["delay"] = float(m["delay"]) - delta
		var node: Node3D = m["node"]
		if float(m["delay"]) <= 0.0 and not node.visible:
			node.visible = true
			Audio.play("blip", -10.0, 1.0 + randf() * 0.4, 0.0, 0.04)
		var label: Label3D = m["label"]
		var dist := (m["pos"] as Vector3).distance_to(eye)
		label.text = "%s\n%dm" % [m["text"], int(round(dist))]
		label.position = up * 0.6
		(m["mesh"] as Node3D).rotate_y(delta * 2.5)
		var life: float = m["life"]
		var a := clampf(life / 1.5, 0.0, 1.0)
		label.modulate.a = a
		label.outline_modulate.a = a
		# markers vanish once you have dug the deposit out
		if life <= 0.0 or (float(m["delay"]) <= 0.0 and dist < 1.6):
			node.queue_free()
			_markers.remove_at(i)
		i -= 1
