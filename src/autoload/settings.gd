extends Node
## User settings (persisted to user://settings.cfg) and input-map registration.
## Autoload name: Settings

signal changed(key: String)

const PATH := "user://settings.cfg"

const DEFAULTS := {
	"mouse_sensitivity": 0.22,
	"invert_y": false,
	"fov": 80.0,
	"master_volume": 0.9,
	"sfx_volume": 0.9,
	"music_volume": 0.55,
	"camera_shake": 0.7,
	"view_bob": 0.4,
	"fullscreen": false,
	"vsync": true,
	"shadow_quality": 2,
	"render_scale": 1.0,
	"show_debug": false,
	"toggle_sprint": false,
	"reduce_flashes": false,
	"ui_scale": 1.0,
}

var _values: Dictionary = {}

## action -> [default physical keycodes / mouse buttons]. Mouse buttons are encoded as negative numbers.
const ACTIONS := {
	"move_forward": [KEY_W, KEY_UP],
	"move_back": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"jump": [KEY_SPACE],
	"sprint": [KEY_SHIFT],
	"use_tool": [-MOUSE_BUTTON_LEFT],
	"alt_tool": [-MOUSE_BUTTON_RIGHT],
	"interact": [KEY_E],
	"scan": [KEY_Q],
	"tool_1": [KEY_1],
	"tool_2": [KEY_2],
	"tool_3": [KEY_3],
	"tool_4": [KEY_4],
	"tool_next": [-MOUSE_BUTTON_WHEEL_DOWN],
	"tool_prev": [-MOUSE_BUTTON_WHEEL_UP],
	"journal": [KEY_TAB, KEY_J],
	"pause": [KEY_ESCAPE],
	"toggle_debug": [KEY_F3],
	"quick_save": [KEY_F5],
	"screenshot": [KEY_F12],
}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_values = DEFAULTS.duplicate()
	_register_actions()
	load_settings()
	apply_all()


func _register_actions() -> void:
	for action: String in ACTIONS:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.3)
		for code: int in ACTIONS[action]:
			if code < 0:
				var mb := InputEventMouseButton.new()
				mb.button_index = -code as MouseButton
				InputMap.action_add_event(action, mb)
			else:
				var k := InputEventKey.new()
				k.physical_keycode = code as Key
				InputMap.action_add_event(action, k)


func get_value(key: String) -> Variant:
	return _values.get(key, DEFAULTS.get(key))


func set_value(key: String, value: Variant, save := true) -> void:
	_values[key] = value
	_apply(key)
	changed.emit(key)
	if save:
		save_settings()


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	for key: String in DEFAULTS:
		if cfg.has_section_key("settings", key):
			var v: Variant = cfg.get_value("settings", key)
			if typeof(v) == typeof(DEFAULTS[key]) or (v is float and DEFAULTS[key] is int) or (v is int and DEFAULTS[key] is float):
				_values[key] = v


func save_settings() -> void:
	var cfg := ConfigFile.new()
	for key: String in _values:
		cfg.set_value("settings", key, _values[key])
	cfg.save(PATH)


func reset_to_defaults() -> void:
	_values = DEFAULTS.duplicate()
	apply_all()
	save_settings()
	for key: String in DEFAULTS:
		changed.emit(key)


func apply_all() -> void:
	for key: String in _values:
		_apply(key)


func _apply(key: String) -> void:
	if DisplayServer.get_name() == "headless":
		if key.ends_with("_volume"):
			_apply_volume(key)
		return
	match key:
		"fullscreen":
			var want := DisplayServer.WINDOW_MODE_FULLSCREEN if _values[key] else DisplayServer.WINDOW_MODE_WINDOWED
			if DisplayServer.window_get_mode() != want:
				DisplayServer.window_set_mode(want)
		"vsync":
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if _values[key] else DisplayServer.VSYNC_DISABLED)
		"master_volume", "sfx_volume", "music_volume":
			_apply_volume(key)
		"shadow_quality":
			var q: int = _values[key]
			var sizes := [1024, 2048, 4096, 8192]
			RenderingServer.directional_shadow_atlas_set_size(sizes[clampi(q, 0, 3)], true)
		"render_scale":
			var tree := get_tree()
			if tree and tree.root:
				tree.root.scaling_3d_scale = clampf(_values[key], 0.5, 1.0)
		"ui_scale":
			var tree := get_tree()
			if tree and tree.root:
				tree.root.content_scale_factor = clampf(_values[key], 0.75, 1.5)


func _apply_volume(key: String) -> void:
	var bus_name := {"master_volume": "Master", "sfx_volume": "SFX", "music_volume": "Music"}[key] as String
	var idx := AudioServer.get_bus_index(bus_name)
	if idx >= 0:
		var v: float = _values[key]
		AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(v, 0.0001)))
		AudioServer.set_bus_mute(idx, v <= 0.001)
