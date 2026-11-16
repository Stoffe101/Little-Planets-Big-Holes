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
	build("Paused", 330, 90)
	closed.connect(func() -> void: resume_requested.emit())
	var split := HBoxContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_theme_constant_override("separation", 28)
	content.add_child(split)
	_buttons = VBoxContainer.new()
	_buttons.add_theme_constant_override("separation", 10)
	_buttons.custom_minimum_size = Vector2(300, 0)
	split.add_child(_buttons)
	for b: Array in [["Resume", true, "resume"], ["Save game", false, "save"], ["Main menu", false, "menu"], ["Quit to desktop", false, "quit"]]:
		var btn := UiTheme.button(str(b[0]), UiTheme.ACCENT, 20) if b[1] else UiTheme.ghost_button(str(b[0]), 20)
		btn.custom_minimum_size = Vector2(0, 48)
		var what := str(b[2])
		btn.pressed.connect(func() -> void: _on_button(what))
		_buttons.add_child(btn)
	_buttons.add_child(UiTheme.spacer(false, Vector2(0, 12)))
	_buttons.add_child(UiTheme.caps("Controls", 13, UiTheme.DIM))
	for row: Array in [["W A S D", "Move"], ["Shift / Space", "Sprint / jump"], ["Left mouse", "Use tool"], ["1-4 / wheel", "Switch tool"],
			["E", "Interact"], ["Q", "Scanner"], ["Tab", "Journal"], ["F5", "Quick save"], ["F3", "Performance overlay"]]:
		var h := HBoxContainer.new()
		var k := UiTheme.label(str(row[0]), 15, UiTheme.TEXT, true)
		k.custom_minimum_size = Vector2(130, 0)
		h.add_child(k)
		h.add_child(UiTheme.label(str(row[1]), 15, UiTheme.DIM))
		_buttons.add_child(h)
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
