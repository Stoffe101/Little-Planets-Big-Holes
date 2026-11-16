class_name World
extends Node3D
## One loaded planet plus everything that lives on it: player, tools, pickups, effects,
## the rocket base, props, discoveries and helper bots. Created by Main for the current planet
## and thrown away when the player flies somewhere else.

signal ready_to_play()
signal message(text: String, kind: String)
signal discovery_popup(id: String)
signal scan_done(found: int)

const SKY_SHADER := preload("res://shaders/sky.gdshader")
const AUTOSAVE_INTERVAL := 75.0
const PROTECT_RADIUS := 10.5         ## shielded ground under the whole outpost (pads, crates, solar array)

var planet_id := "pipseed"
var planet: Planet
var player: Player
var dig: DigSystem
var pickups: PickupManager
var fx: FxManager
var tools: ToolController
var base: Node3D                 ## RocketBase
var props: Node3D                ## PropField
var secrets: Node3D              ## SecretsManager (artifacts, caverns, core)
var robots: Node3D               ## RobotManager
var scanner: Node                ## Scanner
var environment: Environment
var sky_material: ShaderMaterial
var sun: DirectionalLight3D
var is_ready := false
var persist_terrain := true
var _autosave := 0.0
var _sun_axis := Vector3(0.45, 0.2, 0.87).normalized()
var _base_ambient := 1.0
var _look: Dictionary = {}       ## the planet's "look" block (lighting tuning)
var underground := 0.0           ## 0 on the surface .. 1 deep below (drives ambient, fog, audio)
var _pending_tracker: Variant = null
var bloom := 0.0                 ## planet "awakened" glow (after finding the heart)
var resurveyed := false         ## this save last played an older terrain generation of the planet
var setup_ms: Dictionary = {}    ## system name -> milliseconds spent in setup (perf tools, tests)


func start(p_id: String, with_persistence := true) -> void:
	planet_id = p_id
	persist_terrain = with_persistence
	name = "World"
	var cfg := GameData.planet(planet_id)
	_build_environment(cfg)

	planet = Planet.new()
	var db := SaveSystem.terrain_db_path(planet_id) if with_persistence else ""
	planet.setup(cfg, db, GameState.slot_seed)
	add_child(planet)

	dig = DigSystem.new()
	dig.name = "DigSystem"
	add_child(dig)
	dig.setup(planet)

	fx = FxManager.new()
	fx.name = "Fx"
	add_child(fx)
	fx.setup(planet)

	player = Player.new()
	player.name = "Player"
	player.planet = planet
	add_child(player)
	player.input_enabled = false

	pickups = PickupManager.new()
	pickups.name = "Pickups"
	add_child(pickups)
	pickups.setup(planet, player)
	pickups.collected.connect(_on_pickup_collected)

	tools = ToolController.new()
	tools.name = "Tools"
	player.tool_mount.add_child(tools)
	tools.setup(self, player)
	tools.enabled = false
	tools.hint.connect(func(t: String) -> void: message.emit(t, "hint"))
	player.landed.connect(tools.on_landed)

	_build_optional_systems()

	var spawn := planet.geology.spawn_position()
	player.teleport(spawn + planet.geology.landing_dir * 3.0, Vector3(1, 0, 0.3))
	# Terrain streaming (full-resolution voxels, collision) follows the player from now on.
	planet.attach_viewer(player)
	planet.loaded.connect(_on_planet_loaded)
	if planet.is_loaded:
		_on_planet_loaded()


## Systems added in later phases register themselves here; each one is optional so the core
## loop (planet + player + digging) can run and be tested on its own.
func _build_optional_systems() -> void:
	if ResourceLoader.exists("res://src/planet/prop_field.gd"):
		props = (load("res://src/planet/prop_field.gd") as GDScript).new()
		props.name = "Props"
		add_child(props)
	if ResourceLoader.exists("res://src/base/rocket_base.gd"):
		base = (load("res://src/base/rocket_base.gd") as GDScript).new()
		base.name = "Base"
		add_child(base)
	if ResourceLoader.exists("res://src/planet/secrets_manager.gd"):
		secrets = (load("res://src/planet/secrets_manager.gd") as GDScript).new()
		secrets.name = "Secrets"
		add_child(secrets)
	if ResourceLoader.exists("res://src/entities/robot_manager.gd"):
		robots = (load("res://src/entities/robot_manager.gd") as GDScript).new()
		robots.name = "Robots"
		add_child(robots)
	if ResourceLoader.exists("res://src/game/scanner.gd"):
		scanner = (load("res://src/game/scanner.gd") as GDScript).new()
		scanner.name = "Scanner"
		add_child(scanner)


func _on_planet_loaded() -> void:
	# Stand the player on the real (possibly previously excavated) ground next to the pad.
	var geo := planet.geology
	var side := geo.landing_dir.cross(Vector3(1, 0, 0.2)).normalized()
	var stand_dir := (geo.landing_dir + side * 0.06).normalized()
	var ground := planet.ground_point(stand_dir)
	player.teleport(ground + stand_dir * 0.15, -side + Vector3(0.3, 0, 0.2))
	for sys: Node in [props, base, secrets, robots, scanner]:
		if sys != null and sys.has_method("setup"):
			var t0 := Time.get_ticks_usec()
			sys.call("setup", self)
			setup_ms[sys.name] = (Time.get_ticks_usec() - t0) / 1000.0
	if GameState.has_discovery(str((planet.config.get("core", {}) as Dictionary).get("discovery", ""))):
		bloom = 1.0
	if base != null and base.has_method("arrival"):
		var spot: Array = base.call("arrival")
		player.teleport(spot[0], spot[1])
	player.input_enabled = true
	tools.enabled = true
	is_ready = true
	ready_to_play.emit()
	_check_terrain_generation()


## A save made on an older terrain generation of this planet: tell the player once, then
## remember that they have seen the new ground. (Progress is untouched; see SaveSystem.)
func _check_terrain_generation() -> void:
	var gen := planet.geology.generation
	var seen := int(GameState.terrain_generations.get(planet_id, gen))
	GameState.terrain_generations[planet_id] = gen
	if seen >= gen or not persist_terrain:
		return
	resurveyed = true
	var pname := str(planet.config.get("name", planet_id))
	get_tree().create_timer(2.0).timeout.connect(func() -> void:
		message.emit("%s has been resurveyed - it is much bigger now. Your credits, tools and upgrades are all here; old dig sites are archived in the save folder." % pname, "notice"))


# ------------------------------------------------------------------ look

## Sky, ambient light, tonemapping and the sun. All colours come from the planet's `palette`
## (data/planets/*.json); see docs/ART_DIRECTION.md for the reasoning behind the numbers.
func _build_environment(cfg: Dictionary) -> void:
	var pal: Dictionary = cfg.get("palette", {})
	_look = (cfg.get("look", {}) as Dictionary).duplicate()
	# Dev override for look experiments: LPBH_LOOK='{"sun_energy": 2.0, "tonemap": "filmic"}'
	var override: Variant = JSON.parse_string(OS.get_environment("LPBH_LOOK")) if OS.has_environment("LPBH_LOOK") else null
	if override is Dictionary:
		_look.merge(override as Dictionary, true)
	sky_material = ShaderMaterial.new()
	sky_material.shader = SKY_SHADER
	sky_material.set_shader_parameter("top_color", Color(str(pal.get("sky_top", "#0b1424"))))
	sky_material.set_shader_parameter("mid_color", Color(str(pal.get("sky_mid", "#3f6f9e"))))
	sky_material.set_shader_parameter("horizon_color", Color(str(pal.get("sky_horizon", "#b9ccd4"))))
	sky_material.set_shader_parameter("glow_color", Color(str(pal.get("sky_glow", "#f1e2c4"))))
	sky_material.set_shader_parameter("ground_color", Color(str(pal.get("sky_ground", "#3a4034"))))
	sky_material.set_shader_parameter("sun_color", Color(str(pal.get("sun", "#fff1d6"))))
	sky_material.set_shader_parameter("atmosphere", float(_look.get("atmosphere", 1.0)))
	sky_material.set_shader_parameter("star_amount", float(_look.get("stars", 0.6)))
	sky_material.set_shader_parameter("nebula_amount", float(_look.get("nebula", 0.0)))
	sky_material.set_shader_parameter("nebula_color", Color(str(pal.get("nebula", "#1a2a52"))))
	# The "other" planet hangs in the sky, in its own colours as seen from space.
	for other_id in GameData.planet_order:
		if other_id != str(cfg.get("id", "")):
			var opal: Dictionary = (GameData.planet(other_id).get("palette", {}) as Dictionary)
			var from_space: Array = opal.get("from_space", ["#7f93a0", "#5d6f66"])
			sky_material.set_shader_parameter("planet_a_color", Color(str(from_space[0])))
			sky_material.set_shader_parameter("planet_a_color2", Color(str(from_space[1])))
			break
	var sky := Sky.new()
	sky.sky_material = sky_material
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	sky.process_mode = Sky.PROCESS_MODE_REALTIME

	environment = Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	# Ambient comes mostly from the sky itself (soft, directional, slightly blue from above and
	# ground-coloured from below) with a little flat colour so shaded faces never go dead.
	_base_ambient = float(_look.get("ambient_energy", 1.0))
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_color = Color(str(pal.get("ambient", "#c4d2e6")))
	environment.ambient_light_sky_contribution = float(_look.get("sky_contribution", 0.75))
	environment.ambient_light_energy = _base_ambient
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.tonemap_mode = {"linear": Environment.TONE_MAPPER_LINEAR, "filmic": Environment.TONE_MAPPER_FILMIC,
		"aces": Environment.TONE_MAPPER_ACES, "agx": Environment.TONE_MAPPER_AGX}.get(str(_look.get("tonemap", "agx")), Environment.TONE_MAPPER_AGX)
	environment.tonemap_exposure = float(_look.get("exposure", 1.0))
	environment.tonemap_white = 6.0
	# Glow is reserved for genuinely hot pixels (the sun disc, status lights, exotic gems).
	environment.glow_enabled = true
	environment.glow_intensity = 0.28
	environment.glow_strength = 0.9
	environment.glow_bloom = 0.0
	environment.glow_hdr_threshold = 1.6
	environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	if RenderingServer.get_current_rendering_method() == "forward_plus":
		environment.ssao_enabled = true
		environment.ssao_radius = 1.2
		environment.ssao_intensity = 1.6
		environment.ssao_power = 1.4
		environment.ssao_detail = 0.4
		environment.ssao_light_affect = 0.08
	environment.adjustment_enabled = true
	environment.adjustment_saturation = float(_look.get("saturation", 1.0))
	environment.adjustment_contrast = float(_look.get("contrast", 1.04))
	# Fog only matters underground (the horizon of a tiny planet is too close for aerial haze):
	# it gives tunnels depth. Density is driven from _process.
	environment.fog_enabled = true
	environment.fog_light_color = Color(str(pal.get("fog", "#1b1f26")))
	environment.fog_light_energy = 1.0
	environment.fog_sun_scatter = 0.0
	environment.fog_density = 0.0
	environment.fog_sky_affect = 0.0
	var we := WorldEnvironment.new()
	we.name = "Environment"
	we.environment = environment
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = Color(str(pal.get("sun", "#fff1d6")))
	sun.light_energy = float(_look.get("sun_energy", 1.5))
	sun.light_angular_distance = 0.6
	sun.shadow_enabled = true
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.6
	sun.shadow_blur = 1.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 110.0
	sun.directional_shadow_fade_start = 0.85
	sun.directional_shadow_blend_splits = true
	add_child(sun)
	_update_sun(Vector3.UP, 1.0)


## The sun follows the player around the planet so the bit you are playing on is always lit,
## at a fixed mid-morning elevation that gives long readable shadows.
func _update_sun(up: Vector3, weight: float) -> void:
	var tangent := _sun_axis - up * _sun_axis.dot(up)
	if tangent.length() < 0.05:
		tangent = up.cross(Vector3.RIGHT)
	var elevation := deg_to_rad(float(_look.get("sun_elevation", 40.0)))
	var from := (up * sin(elevation) + tangent.normalized() * cos(elevation)).normalized()
	var cur := sun.global_basis.z.normalized() if sun.is_inside_tree() else from
	var dir := cur.slerp(from, weight).normalized() if cur.dot(from) > -0.999 else from
	var side := dir.cross(Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT).normalized()
	var b := Basis(side, dir.cross(side).normalized(), dir)
	if sun.is_inside_tree():
		sun.global_basis = b
	else:
		sun.basis = b
	sky_material.set_shader_parameter("sun_dir", dir)


func _process(delta: float) -> void:
	if player == null or planet == null:
		return
	GameState.playtime += delta
	var up := player.up
	_update_sun(up, clampf(delta * 1.5, 0.0, 1.0))
	sky_material.set_shader_parameter("up_dir", up)
	var eye_r := maxf(player.eye_position().length(), 1.0)
	var limb := clampf(planet.geology.radius / eye_r, 0.0, 1.0)
	sky_material.set_shader_parameter("horizon_dip", sqrt(1.0 - limb * limb))
	# Underground: the sky's contribution fades with depth so caves are lit by the headlamp,
	# the cavern lights and whatever glows - never pitch black, never flat.
	var under := clampf((player.depth - 1.5) / 9.0, 0.0, 1.0)
	underground = under
	environment.ambient_light_energy = lerpf(_base_ambient, _base_ambient * float(_look.get("cave_ambient", 0.3)), under)
	environment.fog_density = lerpf(0.0, 0.012, under)
	sky_material.set_shader_parameter("underground", under * 0.8)
	Audio.set_underground(under)
	Audio.set_ambience((1.0 - under) * float(_look.get("wind", 1.0)), under)
	planet.material.set_shader_parameter("bloom_amount", bloom)

	if is_ready and persist_terrain:
		_autosave += delta
		if _autosave >= AUTOSAVE_INTERVAL:
			_autosave = 0.0
			save_all(false)


# ------------------------------------------------------------------ gameplay hooks

## True if `pos` is inside the shielded column under the rocket base (so the base never floats).
func is_protected(pos: Vector3) -> bool:
	var geo := planet.geology
	var r := pos.length()
	if r < 0.01:
		return false
	var ang := acos(clampf(pos.dot(geo.landing_dir) / r, -1.0, 1.0))
	return ang * geo.radius < PROTECT_RADIUS and geo.depth_at(pos) < 14.0


## Called by tools after every successful dig.
func on_dig(result: Dictionary, pos: Vector3) -> void:
	# Lucky Charm: an occasional bonus gem pops out with fanfare.
	if randf() < luck_roll_chance(float(result.get("volume", 1.0))):
		var gem := GameData.mat_index(str(planet.config.get("lucky_gem", planet.config.get("bonus_gem", "amethyst"))))
		var up := planet.up_at(pos)
		pickups.spawn(gem, 1 + randi() % 2, pos + up * 0.4, up * 6.0 + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)))
		fx.sparks(pos + up * 0.4, up, GameData.materials[gem]["color2_c"], 10)
		fx.floating_text(pos + up * 0.8, "Lucky find", UiTheme.YELLOW, 0.8)
		Audio.play("rare", -2.0)
		GameState.add_stat("bonus_gems")
	if props != null and props.has_method("on_dig"):
		props.call("on_dig", pos, float(result.get("radius", 1.0)))
	if secrets != null and secrets.has_method("on_dig"):
		secrets.call("on_dig", pos, float(result.get("radius", 1.0)))


## Chance that one dig of `volume` cubic metres pops a lucky gem. Small bites count less; big
## bites do not count more, so a fast power tool cannot turn the charm into the main income.
static func luck_roll_chance(volume: float) -> float:
	return GameState.luck_chance() * clampf(volume / 4.0, 0.4, 1.0)


var _combo := 0
var _combo_time := 0.0

func _on_pickup_collected(mat: int, units: int, _pos: Vector3) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	_combo = _combo + 1 if now - _combo_time < 0.7 else 0
	_combo_time = now
	var def := GameData.materials[mat]
	var rich := str(def["category"]) != "soil" and str(def["category"]) != "rock"
	Audio.play("collect_gem" if rich else "collect", -9.0, 1.0 + minf(float(_combo), 12.0) * 0.045, 0.02, 0.03)
	message.emit("%d|%d" % [mat, units], "pickup")


func discover(id: String) -> void:
	if GameState.discover(id):
		Audio.play("discovery", 0.0)
		discovery_popup.emit(id)
		save_all(false)


# ------------------------------------------------------------------ saving

## Saves progress and terrain. With `blocking`, waits for the voxel stream to finish writing.
func save_all(blocking: bool) -> bool:
	if not persist_terrain:
		return true
	var ok := SaveSystem.save_game()
	if blocking:
		ok = planet.save_terrain_blocking() and ok
	else:
		_pending_tracker = planet.save_terrain()
	message.emit("Saved" if ok else "Save failed!", "save")
	return ok


func shutdown() -> void:
	Audio.stop_all_loops()
	if persist_terrain and planet != null and planet.is_loaded:
		save_all(true)
