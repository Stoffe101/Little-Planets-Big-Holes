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
const PROTECT_RADIUS := 7.5

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
var fill: DirectionalLight3D
var is_ready := false
var persist_terrain := true
var _autosave := 0.0
var _sun_axis := Vector3(0.45, 0.2, 0.87).normalized()
var _base_ambient := 0.3
var _pending_tracker: Variant = null
var _ambient_color := Color.WHITE
var bloom := 0.0                 ## planet "awakened" glow (after finding the heart)


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

	_build_optional_systems()

	var spawn := planet.geology.spawn_position()
	player.teleport(spawn + planet.geology.landing_dir * 3.0, Vector3(1, 0, 0.3))
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
			sys.call("setup", self)
	if GameState.has_discovery(str((planet.config.get("core", {}) as Dictionary).get("discovery", ""))):
		bloom = 1.0
	player.input_enabled = true
	tools.enabled = true
	is_ready = true
	ready_to_play.emit()


# ------------------------------------------------------------------ look

func _build_environment(cfg: Dictionary) -> void:
	var pal: Dictionary = cfg.get("palette", {})
	sky_material = ShaderMaterial.new()
	sky_material.shader = SKY_SHADER
	sky_material.set_shader_parameter("top_color", Color(str(pal.get("sky_top", "#1d1b54"))))
	sky_material.set_shader_parameter("mid_color", Color(str(pal.get("sky_mid", "#5b4bc4"))))
	sky_material.set_shader_parameter("horizon_color", Color(str(pal.get("sky_horizon", "#ff9fb0"))))
	sky_material.set_shader_parameter("glow_color", Color(str(pal.get("sky_glow", "#ffd59a"))))
	sky_material.set_shader_parameter("sun_color", Color(str(pal.get("sun", "#fff2c9"))))
	# The "other" planet hangs in the sky.
	for other_id in GameData.planet_order:
		if other_id != str(cfg.get("id", "")):
			var opal: Dictionary = (GameData.planet(other_id).get("palette", {}) as Dictionary)
			var g: Array = opal.get("grass", ["#5fe3c9"])
			sky_material.set_shader_parameter("planet_a_color", Color(str(g[0])))
			break
	var sky := Sky.new()
	sky.sky_material = sky_material
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	sky.process_mode = Sky.PROCESS_MODE_REALTIME

	environment = Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	_ambient_color = Color(str(pal.get("ambient", "#b9b4ff")))
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = _ambient_color
	environment.ambient_light_energy = _base_ambient
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	# Linear tonemapping keeps the hand-picked palette exactly as authored (lit surfaces sum to ~1.0).
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment.glow_enabled = true
	environment.glow_intensity = 0.7
	environment.glow_strength = 0.9
	environment.glow_bloom = 0.0
	environment.glow_hdr_threshold = 1.1
	environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	environment.ssao_enabled = true
	environment.ssao_radius = 1.6
	environment.ssao_intensity = 1.3
	environment.ssao_power = 1.5
	environment.adjustment_enabled = true
	environment.adjustment_saturation = 1.06
	environment.adjustment_contrast = 1.03
	environment.fog_enabled = true
	environment.fog_light_color = Color(str(pal.get("fog", "#7d6fd6")))
	environment.fog_density = 0.0016
	environment.fog_sky_affect = 0.0
	var we := WorldEnvironment.new()
	we.name = "Environment"
	we.environment = environment
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = Color(str(pal.get("sun", "#fff2c9")))
	sun.light_energy = 0.74
	sun.shadow_enabled = true
	sun.shadow_bias = 0.08
	sun.shadow_normal_bias = 2.6
	sun.shadow_blur = 2.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 95.0
	sun.directional_shadow_fade_start = 0.85
	add_child(sun)
	# A cool fill from the opposite side keeps the shaded half of the planet colourful.
	fill = DirectionalLight3D.new()
	fill.name = "Fill"
	fill.light_color = Color(str(pal.get("rim", "#8ff0ff")))
	fill.light_energy = 0.1
	fill.shadow_enabled = false
	add_child(fill)
	_update_sun(Vector3.UP, 1.0)


## The sun follows the player around the planet so the bit you are playing on is always lit.
func _update_sun(up: Vector3, weight: float) -> void:
	var tangent := _sun_axis - up * _sun_axis.dot(up)
	if tangent.length() < 0.05:
		tangent = up.cross(Vector3.RIGHT)
	var from := (up * 0.78 + tangent.normalized() * 0.62).normalized()
	var cur := sun.global_basis.z.normalized() if sun.is_inside_tree() else from
	var dir := cur.slerp(from, weight).normalized() if cur.dot(from) > -0.999 else from
	var side := dir.cross(Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT).normalized()
	var b := Basis(side, dir.cross(side).normalized(), dir)
	if sun.is_inside_tree():
		sun.global_basis = b
		fill.global_basis = Basis(-side, b.y, -dir)
	else:
		sun.basis = b
		fill.basis = Basis(-side, b.y, -dir)
	sky_material.set_shader_parameter("sun_dir", dir)


func _process(delta: float) -> void:
	if player == null or planet == null:
		return
	GameState.playtime += delta
	var up := player.up
	_update_sun(up, clampf(delta * 1.5, 0.0, 1.0))
	sky_material.set_shader_parameter("up_dir", up)
	# Underground: dim the ambient so caves feel like caves and glowing ore pops.
	var under := clampf((player.depth - 2.0) / 9.0, 0.0, 1.0)
	environment.ambient_light_energy = lerpf(_base_ambient, 0.07, under)
	sky_material.set_shader_parameter("underground", under * 0.6)
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
	var chance := GameState.luck_chance()
	if chance > 0.0 and randf() < chance * clampf(float(result.get("volume", 1.0)) / 4.0, 0.4, 2.0):
		var gem := GameData.mat_index(str(planet.config.get("bonus_gem", "amethyst")))
		var up := planet.up_at(pos)
		pickups.spawn(gem, 1 + randi() % 2, pos + up * 0.4, up * 6.0 + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)))
		fx.sparks(pos + up * 0.4, up, GameData.materials[gem]["color2_c"], 24)
		fx.floating_text(pos + up * 0.8, "LUCKY!", UiTheme.YELLOW, 0.9)
		Audio.play("rare", -2.0)
		GameState.add_stat("bonus_gems")
	if props != null and props.has_method("on_dig"):
		props.call("on_dig", pos, float(result.get("radius", 1.0)))
	if secrets != null and secrets.has_method("on_dig"):
		secrets.call("on_dig", pos, float(result.get("radius", 1.0)))


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
