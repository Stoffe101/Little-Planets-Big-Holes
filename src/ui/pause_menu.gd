class_name PauseMenu
extends UiScreen
## Pause menu with settings. The scene tree is paused while it is open.

signal resume_requested()
signal save_requested()
signal main_menu_requested()
signal quit_requested()

var _settings_scroll: ScrollContainer
var _buttons: VBoxContainer


func _init() -> void:
	name = "PauseMenu"
	process_mode = Node.PROCESS_MODE_ALWAYS
	build("PAUSED", 330, 90, UiTheme.PINK)
	closed.connect(func() -> void: resume_requested.emit())
	var split := HBoxContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_theme_constant_override("separation", 26)
	content.add_child(split)
	_buttons = VBoxContainer.new()
	_buttons.add_theme_constant_override("separation", 14)
	_buttons.custom_minimum_size = Vector2(320, 0)
	split.add_child(_buttons)
	for b: Array in [["Resume", UiTheme.GREEN, "resume"], ["Save game", UiTheme.SKY, "save"], ["Main menu", UiTheme.YELLOW, "menu"], ["Quit to desktop", UiTheme.PINK, "quit"]]:
		var btn := UiTheme.button(str(b[0]), b[1], 28)
		btn.custom_minimum_size = Vector2(0, 64)
		var what := str(b[2])
		btn.pressed.connect(func() -> void: _on_button(what))
		_buttons.add_child(btn)
	var keys := UiTheme.label("WASD move  -  Shift sprint  -  Space jump\nLeft mouse dig  -  1-4 / wheel tools\nE interact  -  Q scan  -  Tab journal\nF3 debug  -  F5 quick save", 19, UiTheme.MUTED)
	_buttons.add_child(keys)
	_settings_scroll = ScrollContainer.new()
	_settings_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_settings_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_settings_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	split.add_child(_settings_scroll)
	var sp := SettingsPanel.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_settings_scroll.add_child(sp)


func _on_button(what: String) -> void:
	match what:
		"resume": close_screen()
		"save": save_requested.emit()
		"menu": main_menu_requested.emit()
		"quit": quit_requested.emit()
