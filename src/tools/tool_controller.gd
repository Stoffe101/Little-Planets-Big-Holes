class_name ToolController
extends Node3D
## Owns the first-person tool: input, behaviour (swing / drill / vacuum / cannon), viewmodel
## animation and all the moment-to-moment feedback that makes digging feel good.
## Lives under the player's camera (Player.tool_mount).

signal used(family_id: String, result: Dictionary)
signal blocked(material_index: int)
signal equipped(family_id: String)
signal hint(text: String)

## Rest pose per pose-class: [position, rotation in degrees, scale]. Hand tools are carried
## across the body; powered tools are shouldered straight ahead, which is a large part of why
## the first powered purchase feels different.
const REST := {
	"hand": [Vector3(0.26, -0.27, -0.42), Vector3(36, 16, -8), 1.15],
	"power": [Vector3(0.21, -0.22, -0.38), Vector3(11, 12, -4), 1.0],
	"drill": [Vector3(0.215, -0.215, -0.43), Vector3(5, 9, 0), 1.0],
	"vacuum": [Vector3(0.22, -0.25, -0.44), Vector3(6, 9, 0), 1.0],
	"cannon": [Vector3(0.21, -0.225, -0.43), Vector3(4, 8, 0), 1.0],
}
const IMPACT_T := 0.4
const SOUND_BY_MATERIAL := {"soft": "dig_soft", "stone": "dig_stone", "hard": "dig_hard", "ore": "dig_ore", "crystal": "dig_crystal"}

var world: Node3D                      ## World (untyped to avoid a cyclic class reference)
var player: Player
var family_id := ""
var stats: Dictionary = {}
var model: Dictionary = {}
var holder: Node3D
var enabled := true
var cooldown := 0.0
var cooldown_total := 0.001
var _swing_t := -1.0
var _swing_dur := 0.3
var _impact_done := true
var _equip_t := 1.0
var _pending_family := ""
var _spin_speed := 0.0
var _kick := 0.0
var _shake := 0.0
var _piston := 0.0
var _sway := Vector2.ZERO
var _last_cam_basis := Basis.IDENTITY
var _drill_contact := false
var _vacuuming := false
var _shots: Array[Dictionary] = []
var _hint_cooldown := 0.0
var _flash := 0.0
var _time := 0.0
var _inspect := 0.0              ## > 0 while showing off a freshly bought tool or attachment
var _recoil_slide := 0.0         ## cannon barrel travel 0..1
var _land := 0.0                 ## landing dip impulse
var _piston_rest := -0.3
var _recoil_rest := 0.0
var _pos_spring := Vector3.ZERO  ## smoothed positional offset (sway, bob)
var _rot_spring := Vector3.ZERO
var _reload_click := false
var _pending_inspect := ""       ## family whose new purchase is waiting to be shown off
## Test hooks: set to drive the tool without real input.
var forced_use := false
var forced_use_enabled := false


func setup(w: Node3D, p: Player) -> void:
	world = w
	player = p
	holder = Node3D.new()
	holder.name = "Holder"
	add_child(holder)
	GameState.tools_changed.connect(_on_tools_changed)
	GameState.equipped_changed.connect(_on_equipped_changed)
	GameState.purchase_made.connect(_on_purchase)
	_equip_now(GameState.equipped)


func _on_tools_changed() -> void:
	if family_id == "":
		return
	stats = GameState.tool_stats(family_id)
	_rebuild_model()


## A new tier or attachment for a tool: hold it up for a moment once the player can see it
## (purchases normally happen inside the shop, and a brand-new family is equipped right after).
## Driven by purchases only - discoveries also emit tools_changed and must not trigger it.
func _on_purchase(kind: String, id: String) -> void:
	var fam := ""
	if kind == "tier":
		for f in GameData.tool_families:
			for t: Dictionary in f["tiers"]:
				if str(t["id"]) == id:
					fam = str(f["id"])
	elif kind == "mod":
		fam = id.split("/")[0]
	if fam != "":
		_pending_inspect = fam


func _on_equipped_changed(fam: String) -> void:
	if fam == family_id:
		return
	_pending_family = fam
	if _equip_t >= 1.0:
		_equip_t = -1.0   # lower the current tool first
	Audio.play("equip", -8.0, 1.0, 0.05)


func _equip_now(fam: String) -> void:
	family_id = fam
	stats = GameState.tool_stats(fam)
	_rebuild_model()
	_swing_t = -1.0
	_impact_done = true
	_spin_speed = 0.0
	_stop_loops()
	equipped.emit(fam)


func _rebuild_model() -> void:
	for c in holder.get_children():
		c.queue_free()
	var mods := {}
	for m: Dictionary in GameData.family(family_id).get("mods", []):
		mods[m["id"]] = GameState.mod_level(family_id, m["id"])
	model = ToolModels.build(family_id, GameState.tier_of(family_id), mods, true)
	holder.add_child(model["root"])
	if model.get("piston") != null:
		_piston_rest = (model["piston"] as Node3D).position.z
	if model.get("recoil") != null:
		_recoil_rest = (model["recoil"] as Node3D).position.z


## Which rest pose the current tool uses.
func pose_class() -> String:
	match behavior():
		"swing": return "power" if int(stats.get("auto", 0)) == 1 else "hand"
		"drill": return "drill"
		"vacuum": return "vacuum"
		"cannon": return "cannon"
	return "hand"


func _stop_loops() -> void:
	Audio.set_loop("drill_loop", false)
	Audio.set_loop("vacuum_loop", false)
	Audio.set_loop("thumper_loop", false)
	_vacuuming = false
	_drill_contact = false


func behavior() -> String:
	return str(GameData.family(family_id).get("behavior", "swing"))


func cooldown_ratio() -> float:
	return clampf(cooldown / maxf(cooldown_total, 0.001), 0.0, 1.0)


# ------------------------------------------------------------------ input

func _unhandled_input(event: InputEvent) -> void:
	if not enabled or player.controls_locked or player.transit_hold:
		return
	for slot in range(1, 5):
		if event.is_action_pressed("tool_%d" % slot):
			var fam := GameData.family_for_slot(slot)
			if not fam.is_empty() and GameState.owns_family(fam["id"]):
				GameState.set_equipped(fam["id"])
			elif not fam.is_empty():
				hint.emit("You don't own a %s yet - visit the Workshop." % fam["name"])
	if event.is_action_pressed("tool_next"):
		_cycle(1)
	elif event.is_action_pressed("tool_prev"):
		_cycle(-1)


func _cycle(dir: int) -> void:
	var owned := GameState.owned_families()
	if owned.size() < 2:
		return
	var i := owned.find(GameState.equipped)
	GameState.set_equipped(owned[posmod(i + dir, owned.size())])


func _wants_use() -> bool:
	if forced_use_enabled:
		return forced_use
	return Input.is_action_pressed("use_tool") and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED


# ------------------------------------------------------------------ main loop

func _physics_process(delta: float) -> void:
	if world == null or player == null:
		return
	_time += delta
	cooldown = maxf(0.0, cooldown - delta)
	_hint_cooldown = maxf(0.0, _hint_cooldown - delta)
	var using: bool = enabled and not player.controls_locked and not player.transit_hold and _equip_t >= 1.0 and _wants_use()
	match behavior():
		"swing": _tick_swing(delta, using)
		"drill": _tick_drill(delta, using)
		"vacuum": _tick_vacuum(delta, using)
		"cannon": _tick_cannon(delta, using)
	_tick_shots(delta)


func _aim(reach: float) -> Dictionary:
	var from := player.eye_position()
	var dir := player.aim_direction()
	var space := player.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * reach, 1 | 4)
	q.exclude = [player.get_rid()]
	var hit := space.intersect_ray(q)
	if not hit.is_empty() and not (hit["collider"] is Formation) and not (hit["collider"] is VoxelTerrain):
		# trees, rocks and machines do not stop a shovel: dig the ground behind them
		q.collision_mask = 1
		hit = space.intersect_ray(q)
	if hit.is_empty():
		return {}
	hit["dir"] = dir
	return hit


## Crystal formations crack and shatter instead of being dug.
func _hit_formation(hit: Dictionary, continuous := false) -> void:
	var f := hit["collider"] as Formation
	var ok := f.hit(int(stats.get("power", 1)), world, float(stats.get("ore_yield", 0.0)))
	if ok:
		_kick = 0.8
		player.add_trauma(0.16)
		player.add_recoil(Vector2(randf_range(-0.008, 0.008), 0.018))
	else:
		world.fx.sparks(hit["position"], hit["normal"])
		Audio.play("clang", -5.0 if not continuous else -11.0, 1.2, 0.1, 0.09 if continuous else 0.0)
		_kick = 1.0
		player.add_trauma(0.15)
		_blocked_hint(f.material_index)


func _dig_opts() -> Dictionary:
	return {"ore_yield": float(stats.get("ore_yield", 0.0)), "source": family_id}


# ------------------------------------------------------------------ swing (shovels)

func _tick_swing(delta: float, using: bool) -> void:
	var cd := float(stats.get("cooldown", 0.5))
	if using and cooldown <= 0.0 and _swing_t < 0.0:
		_swing_t = 0.0
		_swing_dur = clampf(cd * 0.92, 0.16, 0.44)
		_impact_done = false
		cooldown = cd
		cooldown_total = cd
		Audio.play("swish", -15.0, 1.0 + (0.5 - cd) * 0.6, 0.08)
	if _swing_t >= 0.0:
		_swing_t += delta / _swing_dur
		if not _impact_done and _swing_t >= IMPACT_T:
			_impact_done = true
			_swing_impact()
		if _swing_t >= 1.0:
			_swing_t = -1.0
	var powered := int(stats.get("auto", 0)) == 1
	Audio.set_loop("thumper_loop", powered and using, 1.0, -14.0)


func _swing_impact() -> void:
	var radius := float(stats.get("radius", 0.9))
	var power := int(stats.get("power", 1))
	var hit := _aim(float(stats.get("reach", 3.2)))
	if hit.is_empty():
		return
	if hit["collider"] is Formation:
		_hit_formation(hit)
		return
	var dir: Vector3 = hit["dir"]
	var pos: Vector3 = hit["position"]
	if world.is_protected(pos):
		_on_protected(pos, hit["normal"])
		return
	var result: Dictionary
	if int(stats.get("trench", 0)) == 1:
		result = world.dig.dig_capsule(pos + dir * radius * 0.3, pos + dir * radius * 2.6, radius * 0.9, power, _dig_opts())
	else:
		result = world.dig.dig_sphere(pos + dir * radius * 0.35, radius, power, _dig_opts())
	_feedback(result, pos, hit["normal"], dir, radius)
	if int(stats.get("auto", 0)) == 1:
		_piston = 1.0


# ------------------------------------------------------------------ drill

func _tick_drill(delta: float, using: bool) -> void:
	var target_spin := 38.0 if using else 0.0
	_spin_speed = move_toward(_spin_speed, target_spin, delta * (160.0 if using else 60.0))
	_drill_contact = false
	if using and _spin_speed > 18.0 and cooldown <= 0.0:
		var cd := float(stats.get("cooldown", 0.13))
		cooldown = cd
		cooldown_total = cd
		var radius := float(stats.get("radius", 1.0))
		var hit := _aim(float(stats.get("reach", 3.6)))
		if not hit.is_empty() and hit["collider"] is Formation:
			_drill_contact = true
			cooldown = maxf(cd, 0.3)
			_hit_formation(hit, true)
		elif not hit.is_empty():
			var pos: Vector3 = hit["position"]
			var dir: Vector3 = hit["dir"]
			if world.is_protected(pos):
				_on_protected(pos, hit["normal"])
			else:
				var result: Dictionary = world.dig.dig_sphere(pos + dir * radius * 0.55, radius, int(stats.get("power", 4)), _dig_opts())
				_drill_contact = bool(result["ok"]) or bool(result["blocked"])
				_feedback(result, pos, hit["normal"], dir, radius, true)
	Audio.set_loop("drill_loop", using, 1.18 if _drill_contact else 0.92, -9.0 if _drill_contact else -13.0)
	if using:
		_shake = maxf(_shake, 0.5 if _drill_contact else 0.2)


# ------------------------------------------------------------------ vacuum

func _tick_vacuum(delta: float, using: bool) -> void:
	_spin_speed = move_toward(_spin_speed, 30.0 if using else 0.0, delta * 90.0)
	var pulling := 0
	if using:
		pulling = world.pickups.vacuum(player.eye_position(), player.aim_direction(), float(stats.get("range", 10.0)), float(stats.get("cone", 32.0)))
		if GameState.is_full() and _hint_cooldown <= 0.0:
			_hint_cooldown = 3.0
			hint.emit("Backpack full! Sell at the Depot.")
		_shake = maxf(_shake, 0.12 + 0.04 * minf(float(pulling), 5.0))
	_vacuuming = using
	Audio.set_loop("vacuum_loop", using, 1.0 + 0.05 * minf(float(pulling), 6.0), -10.0)


# ------------------------------------------------------------------ cannon

func _tick_cannon(_delta: float, using: bool) -> void:
	if using and cooldown <= 0.0:
		var cd := float(stats.get("cooldown", 2.4))
		cooldown = cd
		cooldown_total = cd
		var dir := player.aim_direction()
		var origin := player.eye_position() + dir * 0.9 - player.camera.global_basis.y * 0.15
		var node := _make_shot()
		world.add_child(node)
		node.global_position = origin
		_shots.append({"node": node, "pos": origin, "vel": dir * 34.0 + player.velocity * 0.5, "life": 5.0,
			"radius": float(stats.get("radius", 3.4)), "power": int(stats.get("power", 3)), "opts": _dig_opts()})
		_kick = 1.0
		_recoil_slide = 1.0
		_reload_click = true
		player.add_recoil(Vector2(randf_range(-0.01, 0.01), 0.05))
		player.add_trauma(0.25)
		Audio.play("cannon_fire", -3.0, 1.0, 0.05)
		used.emit(family_id, {})


func _make_shot() -> Node3D:
	var kit := MeshKit.new()
	# a seismic charge: graphite canister with an amber band and a lit fuse cap
	kit.cast()
	kit.turned(Vector3(0, 0, 0.16), Vector3(0, 0, -0.16), PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.1, 0.02), Vector2(0.12, 0.06), Vector2(0.12, 0.26), Vector2(0.08, 0.32), Vector2(0.0, 0.32)]), Pal.BRONZE, 12, true)
	kit.paint()
	kit.turned(Vector3(0, 0, 0.04), Vector3(0, 0, -0.04), PackedVector2Array([Vector2(0.123, 0.0), Vector2(0.123, 0.08)]), Pal.JADE, 12)
	kit.surf(0.3).set_emission(2.2)
	kit.sphere(Vector3(0, 0, -0.16), 0.05, Pal.JADE, Vector3.ONE, 8, 5)
	kit.emission = 0.0
	var mi := kit.instance(MeshKit.material(), false)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.8, 0.5)
	light.light_energy = 0.8
	light.omni_range = 4.0
	mi.add_child(light)
	return mi


func _tick_shots(delta: float) -> void:
	var i := _shots.size() - 1
	while i >= 0:
		var s := _shots[i]
		var node: Node3D = s["node"]
		var pos: Vector3 = s["pos"]
		var vel: Vector3 = s["vel"]
		vel += world.planet.gravity_at(pos) * delta * 0.55
		var next := pos + vel * delta
		s["life"] = float(s["life"]) - delta
		var exploded := false
		# sub-step so a fast shot cannot tunnel through thin ground
		var steps := maxi(1, int(ceil(vel.length() * delta / 0.4)))
		for k in range(1, steps + 1):
			var p := pos.lerp(next, float(k) / float(steps))
			if world.planet.sdf_at(p) < 0.0:
				_explode(s, p)
				exploded = true
				break
		if exploded or float(s["life"]) <= 0.0:
			node.queue_free()
			_shots.remove_at(i)
		else:
			s["pos"] = next
			s["vel"] = vel
			node.global_position = next
			node.rotate_object_local(Vector3.RIGHT, delta * 12.0)
		i -= 1


func _explode(shot: Dictionary, pos: Vector3) -> void:
	var radius: float = shot["radius"]
	var up: Vector3 = world.planet.up_at(pos)
	if world.is_protected(pos):
		world.fx.sparks(pos, up)
		Audio.play_at("clang", pos, 0.0)
		hint.emit("The launch pad is shielded.")
		return
	var result: Dictionary = world.dig.dig_sphere(pos, radius, int(shot["power"]), shot["opts"])
	var color := Color("#8a6748")
	if int(result["dominant"]) >= 0:
		color = GameData.materials[int(result["dominant"])]["color_c"]
	world.fx.explosion(pos, radius, color)
	Audio.play_at("boom", pos, 4.0, 1.0 - (radius - 3.0) * 0.04, 0.05)
	var dist := player.global_position.distance_to(pos)
	player.add_trauma(clampf(1.1 - dist / (radius * 6.0), 0.1, 0.9))
	if bool(result["ok"]):
		world.pickups.burst(result["yields"], pos + up * radius * 0.3, up, radius, 16)
		world.on_dig(result, pos)
	elif bool(result["blocked"]):
		_blocked_hint(int(result["hard_material"]))
	used.emit(family_id, result)


# ------------------------------------------------------------------ feedback

func _feedback(result: Dictionary, pos: Vector3, normal: Vector3, dir: Vector3, radius: float, continuous := false) -> void:
	if bool(result["empty"]):
		return
	if bool(result["blocked"]):
		world.fx.sparks(pos, normal)
		Audio.play("clang", -4.0 if not continuous else -10.0, 1.0, 0.1, 0.09 if continuous else 0.0)
		_kick = 1.0
		player.add_recoil(Vector2(randf_range(-0.012, 0.012), 0.03 if not continuous else 0.008))
		player.add_trauma(0.22 if not continuous else 0.08)
		_blocked_hint(int(result["hard_material"]))
		blocked.emit(int(result["hard_material"]))
		used.emit(family_id, result)
		return
	var mat := int(result["dominant"])
	var def: Dictionary = GameData.materials[maxi(mat, 0)]
	var color: Color = def["color_c"]
	var amount := clampf(radius, 0.6, 3.0)
	world.fx.dig_burst(pos, normal, color, amount * (0.55 if continuous else 1.0), not continuous or randf() < 0.35)
	var cat := str(def["category"])
	if (cat == "ore" or cat == "crystal" or cat == "exotic") and (not continuous or randf() < 0.25):
		world.fx.sparks(pos, normal, def["color2_c"], 5)
	var sound: String = SOUND_BY_MATERIAL.get(str(def.get("sound", "soft")), "dig_soft")
	Audio.play(sound, -3.0 if not continuous else -9.0, 1.0 + (1.2 - radius) * 0.12, 0.1, 0.07 if continuous else 0.0)
	if bool(result["hit_hard"]) and not continuous:
		Audio.play("clang", -14.0, 1.25, 0.1)
	_kick = 0.6 if not continuous else 0.25
	player.add_recoil(Vector2(randf_range(-0.006, 0.006), 0.012 if not continuous else 0.003))
	player.add_trauma((0.07 + radius * 0.035) * (0.4 if continuous else 1.0))
	# chunks hop out towards the player so they are easy to grab
	var up_here: Vector3 = world.planet.up_at(pos)
	var toward := (-dir + up_here * 0.5).normalized()
	world.pickups.burst(result["yields"], pos - dir * 0.25, toward, radius, 5 if continuous else 7)
	world.on_dig(result, pos)
	used.emit(family_id, result)


func _blocked_hint(mat: int) -> void:
	if mat < 0 or _hint_cooldown > 0.0:
		return
	_hint_cooldown = 2.5
	var def: Dictionary = GameData.materials[mat]
	hint.emit("%s is too hard for this tool (needs power %d)" % [def["name"], int(def["hardness"])])


func _on_protected(pos: Vector3, normal: Vector3) -> void:
	world.fx.sparks(pos, normal, Pal.ION, 6)
	Audio.play("clang", -10.0, 1.4, 0.05, 0.15)
	_kick = 0.5
	if _hint_cooldown <= 0.0:
		_hint_cooldown = 3.0
		hint.emit("The launch pad is shielded - dig a little further out.")


# ------------------------------------------------------------------ viewmodel animation

func _process(delta: float) -> void:
	if holder == null or player == null:
		return
	# equip lower / raise
	if _equip_t < 0.0:
		_equip_t += delta * 6.5
		if _equip_t >= 0.0:
			_equip_now(_pending_family)
			_equip_t = 0.0
	elif _equip_t < 1.0:
		_equip_t = minf(1.0, _equip_t + delta * 4.2)
	elif _pending_family != "" and _pending_family != family_id:
		_equip_t = -1.0      # a switch was requested while the tool was still being raised
	var hidden := absf(_equip_t) if _equip_t < 0.0 else 1.0 - _ease_out_back(_equip_t)   # 0 = fully raised

	# look sway: the tool lags slightly behind camera rotation
	var cam_b := player.camera.global_basis
	var rel := _last_cam_basis.inverse() * cam_b
	_last_cam_basis = cam_b
	var e := rel.get_euler()
	if absf(e.x) + absf(e.y) > 0.5:
		e = Vector3.ZERO      # teleport or planet change, not a look movement
	_sway = _sway.lerp(Vector2(clampf(e.y, -0.2, 0.2), clampf(e.x, -0.2, 0.2)) * 5.0, clampf(delta * 14.0, 0.0, 1.0))
	_sway = _sway.lerp(Vector2.ZERO, clampf(delta * 7.0, 0.0, 1.0))

	_kick = lerpf(_kick, 0.0, clampf(delta * 11.0, 0.0, 1.0))
	_shake = lerpf(_shake, 0.0, clampf(delta * 10.0, 0.0, 1.0))
	_piston = lerpf(_piston, 0.0, clampf(delta * 18.0, 0.0, 1.0))
	_recoil_slide = lerpf(_recoil_slide, 0.0, clampf(delta * 5.0, 0.0, 1.0))
	_land = lerpf(_land, 0.0, clampf(delta * 8.0, 0.0, 1.0))
	if _pending_inspect != "" and not player.controls_locked and _equip_t >= 1.0 and _pending_family in ["", family_id]:
		if _pending_inspect == family_id:
			_flash = 1.0
			_inspect = 1.0
			Audio.play("equip", -6.0, 0.9, 0.03)
		_pending_inspect = ""
	_flash = maxf(0.0, _flash - delta * 2.2)
	_inspect = maxf(0.0, _inspect - delta / 1.5)

	var cls := pose_class()
	var rest: Array = REST.get(cls, REST["hand"])
	var pos: Vector3 = rest[0]
	var rot: Vector3 = rest[1] * (PI / 180.0)
	var powered := cls != "hand"

	# ---- soft secondary motion, smoothed so nothing ever snaps
	var speed := (player.velocity - player.up * player.velocity.dot(player.up)).length()
	var walk := clampf(speed / Player.WALK_SPEED, 0.0, 1.5) if player.is_on_floor() else 0.0
	var want_pos := Vector3(sin(_time * 1.1) * 0.0025, sin(_time * 1.7) * 0.004, 0.0)                       # breathing
	want_pos += Vector3(cos(_time * 7.2) * 0.008, -absf(sin(_time * 7.2)) * 0.011, 0.0) * walk             # walk bob
	want_pos += Vector3(-_sway.x * 0.035, _sway.y * 0.035, 0.0)
	var want_rot := Vector3(-_sway.y * 0.28, -_sway.x * 0.36, -_sway.x * 0.26)
	want_rot.z += sin(_time * 7.2) * 0.012 * walk
	if not player.is_on_floor():
		want_pos.y += clampf(-player.vertical_speed * 0.004, -0.035, 0.035)      # tool floats up as you fall
		want_rot.x += clampf(player.vertical_speed * 0.006, -0.06, 0.06)
	_pos_spring = _pos_spring.lerp(want_pos, clampf(delta * 16.0, 0.0, 1.0))
	_rot_spring = _rot_spring.lerp(want_rot, clampf(delta * 16.0, 0.0, 1.0))
	pos += _pos_spring
	rot += _rot_spring
	pos.y -= _land * 0.05
	rot.x -= _land * 0.08

	# ---- tool specific
	if _swing_t >= 0.0:
		if powered:
			# powered shovel: the housing stays shouldered, the head does the hitting
			var punch := sin(clampf(_swing_t / IMPACT_T, 0.0, 1.0) * PI * 0.5) if _swing_t < IMPACT_T else 1.0 - (_swing_t - IMPACT_T) / (1.0 - IMPACT_T)
			pos.z -= punch * 0.06
			pos.y -= punch * 0.012
			rot.x -= punch * 0.055
		else:
			var sw := _swing_pose(_swing_t)
			pos += sw[0]
			rot += sw[1]
	pos.z += _kick * (0.035 if powered else 0.055)
	rot.x += _kick * (0.05 if powered else 0.1)
	if cls == "cannon":
		pos.z += _recoil_slide * 0.05
		rot.x += _recoil_slide * _recoil_slide * 0.22
	if _shake > 0.01:
		pos += Vector3(sin(_time * 91.0), sin(_time * 77.0 + 1.0), sin(_time * 83.0 + 2.0)) * 0.0028 * _shake
		rot.z += sin(_time * 67.0) * 0.006 * _shake
	if cls == "drill":
		# torque: the body twists against the spin, and leans into the rock while cutting
		rot.z += clampf(_spin_speed / 38.0, 0.0, 1.0) * 0.06
		if _drill_contact:
			pos.z -= 0.028
	if cls == "vacuum" and _vacuuming:
		pos.z -= 0.012
		rot.x += 0.02

	# ---- showing off a new purchase: lift it into view and turn it over once
	if _inspect > 0.0:
		var k := sin(clampf(_inspect, 0.0, 1.0) * PI)
		k = k * k * (3.0 - 2.0 * k)
		# held up at arm's length: clearly presented, but the view ahead stays open
		pos = pos.lerp(Vector3(0.13, -0.15, -0.66), k * 0.85)
		rot.x += k * 0.2
		rot.y += k * 0.7 + sin((1.0 - _inspect) * TAU) * 0.3 * k
	# lowered while switching
	pos.y -= hidden * 0.42
	rot.x -= hidden * 0.8
	rot.z -= hidden * 0.25

	holder.position = pos
	holder.rotation = rot
	holder.scale = Vector3.ONE * float(rest[2])

	if model.get("spin") != null:
		(model["spin"] as Node3D).rotate_object_local(Vector3.FORWARD, _spin_speed * delta)
	if model.get("piston") != null:
		var piston: Node3D = model["piston"]
		piston.position.z = lerpf(piston.position.z, _piston_rest - _piston * 0.13, clampf(delta * 45.0, 0.0, 1.0))
	if model.get("recoil") != null:
		(model["recoil"] as Node3D).position.z = _recoil_rest + _recoil_slide * 0.07
	if model.has("material"):
		(model["material"] as ShaderMaterial).set_shader_parameter("flash", _flash * _flash)
	# cannon: a small "ready" click when the reload finishes
	if cls == "cannon" and _reload_click and cooldown <= 0.0 and cooldown_total > 0.5:
		_reload_click = false
		_kick = maxf(_kick, 0.18)
		Audio.play("equip", -12.0, 1.5, 0.03)


static func _ease_out_back(t: float) -> float:
	var c := 1.4
	var u := t - 1.0
	return 1.0 + (c + 1.0) * u * u * u + c * u * u


## Called by the world when the player lands so the tool dips with the impact.
func on_landed(impact: float) -> void:
	_land = clampf(impact * 0.06, 0.0, 1.0)


## Offsets for the hand-shovel swing: wind-up, fast strike (impact at IMPACT_T), settling recovery.
func _swing_pose(t: float) -> Array:
	var pitch := 0.0
	var fwd := 0.0
	var drop := 0.0
	var roll := 0.0
	if t < 0.16:
		var a := ease(t / 0.16, 0.5)
		pitch = lerpf(0.0, 0.42, a)
		fwd = lerpf(0.0, 0.05, a)
		drop = lerpf(0.0, 0.04, a)
	elif t < IMPACT_T:
		var a2 := ease((t - 0.16) / (IMPACT_T - 0.16), 2.4)
		pitch = lerpf(0.42, -0.72, a2)
		fwd = lerpf(0.05, -0.2, a2)
		drop = lerpf(0.04, -0.07, a2)
		roll = lerpf(0.0, -0.2, a2)
	else:
		var a3 := (t - IMPACT_T) / (1.0 - IMPACT_T)
		var spring := 1.0 - (1.0 - a3) * (1.0 - a3) * cos(a3 * 6.0)
		pitch = lerpf(-0.72, 0.0, spring)
		fwd = lerpf(-0.2, 0.0, spring)
		drop = lerpf(-0.07, 0.0, spring)
		roll = lerpf(-0.2, 0.0, spring)
	return [Vector3(-fwd * 0.3, drop, fwd), Vector3(pitch, fwd * 0.5, roll)]
