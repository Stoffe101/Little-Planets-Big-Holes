class_name Navigation
extends Node3D
## Finding your way on a 2.5 km-around planet:
##   * regions - which named area you are in; entering a new one is announced and remembered,
##   * survey relays - tall masts at the regions; walk up to one to bring it online, then travel
##     between online relays (and the outpost) from the map,
##   * recall - return to the outpost from anywhere,
##   * one player waypoint per planet,
##   * markers() - what the compass strip and the map draw.
##
## Directions use the planet's own frame: the map is an azimuthal equidistant projection centred
## on the landing site (distances from home are true), and compass north points at the -Z pole.
## Persistent bits live in GameState.flags, so they survive saves without a new save field.

signal region_changed(region: Dictionary)
signal relay_activated(id: String)
signal travelled(to: String)

const RELAY_ACTIVATE_DISTANCE := 7.0
const RELAY_USE_DISTANCE := 9.0
const OUTPOST_USE_DISTANCE := 16.0
const NORTH := Vector3(0, 0, -1)

var world: World
var planet: Planet
var geo: Geology
var relays: Array[Dictionary] = []     ## {id, name, pos, up, node, beacon, light}
var current_region := {}
var _check := 0.0
var _time := 0.0


func setup(w: World) -> void:
	world = w
	planet = w.planet
	geo = planet.geology
	for r: Dictionary in planet.config.get("relays", []):
		var d := Vector3(r["dir"][0], r["dir"][1], r["dir"][2]).normalized()
		var pos := d * geo.surface_radius(d)
		var rel := {"id": str(r["id"]), "name": str(r.get("name", r["id"])), "pos": pos, "up": d}
		relays.append(rel)
		_build_relay(rel)
	_update_region(true)


func _flag(kind: String, id := "") -> String:
	return "%s/%s/%s" % [kind, geo.id, id] if id != "" else "%s/%s" % [kind, geo.id]


# ------------------------------------------------------------------ regions

func region_at(p: Vector3) -> Dictionary:
	return geo.region_at(p.normalized())


func region_visited(id: String) -> bool:
	return GameState.has_flag(_flag("region", id))


func _update_region(silent := false) -> void:
	if world.player == null:
		return
	var r := region_at(world.player.global_position)
	var id := str(r.get("id", ""))
	if id == str(current_region.get("id", "")):
		return
	current_region = r
	if id == "":
		return
	var first := not region_visited(id)
	GameState.set_flag(_flag("region", id))
	if not silent:
		region_changed.emit(r)
		if first:
			GameState.add_stat("regions_found")


# ------------------------------------------------------------------ relays

func relay_active(id: String) -> bool:
	return GameState.has_flag(_flag("relay", id))


func active_relays() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for r in relays:
		if relay_active(r["id"]):
			out.append(r)
	return out


## Where the player may travel from right now: "outpost", a relay id, or "" (nowhere).
func travel_origin() -> String:
	if world.player == null:
		return ""
	var p := world.player.global_position
	if world.base != null and p.distance_to(geo.spawn_position()) < OUTPOST_USE_DISTANCE:
		return "outpost"
	for r in relays:
		if relay_active(r["id"]) and p.distance_to(r["pos"]) < RELAY_USE_DISTANCE:
			return str(r["id"])
	return ""


## Travel targets with whether each is reachable now: [{id, name, pos, ok, why}].
func travel_targets() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var origin := travel_origin()
	out.append({"id": "outpost", "name": "Outpost", "pos": geo.spawn_position(), "ok": origin != "outpost", "why": "You are here" if origin == "outpost" else ""})
	for r in relays:
		var ok: bool = relay_active(r["id"]) and origin != "" and origin != r["id"]
		var why := ""
		if not relay_active(r["id"]):
			why = "Not online yet - walk up to it"
		elif origin == r["id"]:
			why = "You are here"
		elif origin == "":
			why = "Travel from a relay or the outpost"
		out.append({"id": r["id"], "name": r["name"], "pos": r["pos"], "ok": ok, "why": why})
	return out


## Teleports the player to the outpost (recall: allowed from anywhere) or an online relay
## (only from another relay or the outpost). Returns false if not allowed.
func travel(to: String) -> bool:
	var target := Vector3.ZERO
	var look := Vector3.ZERO
	if to == "outpost":
		if world.base == null or not world.base.has_method("arrival"):
			return false
		var spot: Array = world.base.call("arrival")
		target = spot[0]
		look = spot[1]
	else:
		var origin := travel_origin()
		var rel := {}
		for r in relays:
			if r["id"] == to:
				rel = r
		if rel.is_empty() or not relay_active(to) or origin == "" or origin == to:
			return false
		var up: Vector3 = rel["up"]
		var side := up.cross(Vector3(0.3, 0.1, 0.9)).normalized()
		target = (rel["pos"] as Vector3) + side * 3.2 + up * 1.2
		look = -side
	world.fx.shock_ring(world.player.global_position + world.player.up * 0.2, world.player.up, 2.2, Pal.ION, 0.5)
	Audio.play("jet_puff", -2.0, 0.6)
	world.player.teleport(target, look)
	if world.props != null:
		world.props.call("update_now", target)
	GameState.add_stat("travels")
	travelled.emit(to)
	return true


func _check_relays() -> void:
	var p := world.player.global_position
	for r in relays:
		if not relay_active(r["id"]) and p.distance_to(r["pos"]) < RELAY_ACTIVATE_DISTANCE:
			GameState.set_flag(_flag("relay", r["id"]))
			_light_relay(r, true)
			Audio.play("discovery", -4.0, 1.3)
			world.fx.shock_ring((r["pos"] as Vector3) + (r["up"] as Vector3) * 0.3, r["up"], 4.0, Pal.ION, 0.8)
			relay_activated.emit(r["id"])
			world.message.emit("%s online - travel here from the map (M) at any relay or the outpost" % r["name"], "notice")


## A survey relay: a tall tripod mast you can see from far away, with a gimbal ring and a
## beacon that lights up once the relay is online.
func _build_relay(r: Dictionary) -> void:
	var node := Node3D.new()
	node.name = "Relay_" + str(r["id"])
	add_child(node)
	var up: Vector3 = r["up"]
	var x := up.cross(Vector3(0.3, 0.1, 0.9)).normalized()
	node.global_transform = Transform3D(Basis(x, up, x.cross(up).normalized()), (r["pos"] as Vector3) - up * 0.25)
	var kit := MeshKit.new()
	kit.matte()
	kit.lathe(PackedVector2Array([Vector2(1.6, -0.8), Vector2(1.6, 0.25), Vector2(1.45, 0.32), Vector2(0.0, 0.32)]), Transform3D.IDENTITY, Pal.CONCRETE, 18, false, true)
	for k in 3:
		var a := TAU * float(k) / 3.0
		var foot := Vector3(cos(a), 0.3, sin(a)) * 1.35
		kit.cast()
		kit.tube(foot, Vector3(0, 6.2, 0), 0.07, 0.05, Pal.BRONZE, 8)
		kit.disc(Transform3D(Basis.IDENTITY, foot - Vector3(0, 0.02, 0)), 0.2, 0.0, 0.08, Pal.BRONZE, 10)
		kit.bare()
		kit.tube(foot * 0.5 + Vector3(0, 2.2, 0), Vector3(0, 3.0, 0), 0.025, 0.025, Pal.COPPER, 6)
	kit.paint()
	kit.turned(Vector3(0, 0.3, 0), Vector3(0, 1.6, 0), PackedVector2Array([Vector2(0.38, 0.0), Vector2(0.38, 1.1), Vector2(0.3, 1.3)]), Pal.ENAMEL, 16, false, true)
	kit.cast()
	kit.torus(Transform3D(Basis.IDENTITY, Vector3(0, 0.75, 0)), 0.4, 0.035, Pal.BRONZE, 20, 5)
	kit.bare()
	kit.tube(Vector3(0, 1.6, 0), Vector3(0, 8.6, 0), 0.07, 0.045, Pal.STEEL, 8)
	kit.cast()
	kit.torus(Transform3D(Basis.from_euler(Vector3(PI * 0.5, 0, 0)), Vector3(0, 7.6, 0)), 0.6, 0.04, Pal.BRONZE, 28, 6)
	kit.torus(Transform3D(Basis.from_euler(Vector3(0, 0, PI * 0.5)), Vector3(0, 7.6, 0)), 0.5, 0.035, Pal.COPPER, 28, 6)
	_dial_plate(kit)
	node.add_child(kit.instance())
	var beacon := MeshKit.new().surf(0.3)
	beacon.set_emission(1.0)
	beacon.sphere(Vector3(0, 8.75, 0), 0.22, Pal.ION, Vector3.ONE, 12, 7)
	var bmat := MeshKit.new_material(0.05)
	var bn := beacon.instance(bmat, false)
	node.add_child(bn)
	var light := OmniLight3D.new()
	light.light_color = Pal.ION
	light.omni_range = 9.0
	light.light_energy = 0.0
	light.position = Vector3(0, 8.4, 0)
	node.add_child(light)
	var label := Label3D.new()
	label.text = str(r["name"]).to_upper()
	label.font = UiTheme.font_bold()
	label.font_size = 96
	label.pixel_size = 0.004
	label.modulate = Pal.CREAM
	label.outline_size = 0
	label.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	label.position = Vector3(0, 2.3, 0)
	node.add_child(label)
	var body := StaticBody3D.new()
	body.collision_layer = 4
	body.collision_mask = 0
	var shape := CylinderShape3D.new()
	shape.radius = 0.5
	shape.height = 8.0
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = Vector3(0, 4.0, 0)
	body.add_child(cs)
	node.add_child(body)
	r["node"] = node
	r["beacon_mat"] = bmat
	r["light"] = light
	_light_relay(r, relay_active(r["id"]))


static func _dial_plate(kit: MeshKit) -> void:
	kit.gloss()
	kit.disc(Transform3D(Basis.from_euler(Vector3(PI * 0.5, 0, 0)), Vector3(0, 1.15, 0.39)), 0.2, 0.0, 0.01, Pal.CREAM, 16)
	kit.cast()
	kit.torus(Transform3D(Basis.from_euler(Vector3(PI * 0.5, 0, 0)), Vector3(0, 1.15, 0.395)), 0.2, 0.02, Pal.BRONZE, 16, 5)


func _light_relay(r: Dictionary, on: bool) -> void:
	(r["beacon_mat"] as ShaderMaterial).set_shader_parameter("emission_scale", 2.2 if on else 0.05)
	(r["light"] as OmniLight3D).light_energy = 1.2 if on else 0.0


# ------------------------------------------------------------------ waypoint

func waypoint() -> Variant:
	var v: Variant = GameState.flags.get(_flag("waypoint"), null)
	if v is Array and (v as Array).size() == 3:
		return Vector3(float(v[0]), float(v[1]), float(v[2]))
	return null


func set_waypoint(dir: Variant) -> void:
	if dir == null:
		GameState.flags.erase(_flag("waypoint"))
		return
	var d: Vector3 = (dir as Vector3).normalized()
	var p := d * geo.surface_radius(d)
	GameState.flags[_flag("waypoint")] = [p.x, p.y, p.z]


# ------------------------------------------------------------------ markers & geometry

## Everything worth pointing at: [{pos, label, kind}] with kind in
## outpost / waypoint / relay / relay_off / place.
func markers() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.append({"pos": geo.spawn_position(), "label": "Outpost", "kind": "outpost"})
	var wp: Variant = waypoint()
	if wp != null:
		out.append({"pos": wp, "label": "Waypoint", "kind": "waypoint"})
	for r in relays:
		out.append({"pos": r["pos"], "label": r["name"], "kind": "relay" if relay_active(r["id"]) else "relay_off"})
	if world.secrets != null:
		for pl: Dictionary in world.secrets.get("places"):
			if GameState.has_discovery(pl["id"]):
				out.append({"pos": pl["center"], "label": str(GameData.discovery(pl["id"]).get("name", pl["id"])), "kind": "place"})
	return out


## Great-circle distance in metres along the original surface radius.
func surface_distance(a: Vector3, b: Vector3) -> float:
	return acos(clampf(a.normalized().dot(b.normalized()), -1.0, 1.0)) * geo.radius


## Signed angle (radians, + = to the right) from the player's view direction to `target`,
## measured in the local horizontal plane.
func bearing_to(target: Vector3) -> float:
	var p := world.player
	var up := p.up
	var to := target - p.global_position
	var flat := to - up * to.dot(up)
	var fwd := -p.camera.global_basis.z
	fwd = fwd - up * fwd.dot(up)
	if flat.length() < 0.01 or fwd.length() < 0.01:
		return 0.0
	return -fwd.normalized().signed_angle_to(flat.normalized(), up)


## Compass heading of the player's view in radians (0 = north, + clockwise).
func heading() -> float:
	var p := world.player
	var up := p.up
	var north := NORTH - up * NORTH.dot(up)
	if north.length() < 0.01:
		north = Vector3.RIGHT - up * Vector3.RIGHT.dot(up)
	var fwd := -p.camera.global_basis.z
	fwd = fwd - up * fwd.dot(up)
	if fwd.length() < 0.01:
		return 0.0
	return north.normalized().signed_angle_to(fwd.normalized(), -up)


## Map projection (azimuthal equidistant around the landing site): direction -> [-1, 1]^2.
func to_map(dir: Vector3) -> Vector2:
	var d := dir.normalized()
	var t := acos(clampf(d.dot(geo.landing_dir), -1.0, 1.0))
	var e1 := Vector3.RIGHT
	var e2 := Vector3.BACK
	var flat := Vector2(d.dot(e1), d.dot(e2))
	if flat.length() < 0.00001:
		return Vector2.ZERO
	return flat.normalized() * (t / PI)


static func from_map_static(uv: Vector2, landing: Vector3) -> Vector3:
	var rho := uv.length()
	if rho < 0.00001:
		return landing
	var t := minf(rho, 1.0) * PI
	var b := atan2(uv.y, uv.x)
	return Vector3(sin(t) * cos(b), cos(t), sin(t) * sin(b))


func from_map(uv: Vector2) -> Vector3:
	return from_map_static(uv, geo.landing_dir)


# ------------------------------------------------------------------ runtime

func _process(delta: float) -> void:
	_time += delta
	if world == null or world.player == null or not world.is_ready:
		return
	_check -= delta
	if _check <= 0.0:
		_check = 0.35
		_update_region()
		_check_relays()
	for r in relays:
		if relay_active(r["id"]):
			(r["beacon_mat"] as ShaderMaterial).set_shader_parameter("emission_scale", 2.0 + 0.6 * sin(_time * 2.2 + float(hash(r["id"]) % 7)))
