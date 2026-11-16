class_name MainMenu
extends Control
## Title screen: Continue / New game / Settings / Quit beside the turning planet.

signal continue_requested()
signal new_game_requested()
signal quit_requested()

var _continue_btn: Button
var _summary: Label
var _settings: UiScreen
var _confirm: UiScreen
var _notice: Label


func _init() -> void:
	name = "MainMenu"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = UiTheme.theme()
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 110)
	margin.add_theme_constant_override("margin_top", 120)
	margin.add_theme_constant_override("margin_bottom", 60)
	margin.add_theme_constant_override("margin_right", 60)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(v)
	v.add_child(UiTheme.caps("A planetary excavation sim", 15, UiTheme.ACCENT))
	var t1 := UiTheme.hud_label("Little Planets,", 56, UiTheme.TEXT)
	t1.add_theme_font_override("font", UiTheme.font_regular())
	v.add_child(t1)
	var t2 := UiTheme.hud_label("Big Holes", 104, UiTheme.TEXT)
	t2.add_theme_font_override("font", UiTheme.font_bold())
	v.add_child(t2)
	var rule := ColorRect.new()
	rule.color = UiTheme.ACCENT
	rule.custom_minimum_size = Vector2(96, 4)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	v.add_child(rule)
	var sub := UiTheme.hud_label("Start with a rusty scoop. End up moving mountains.", 20, UiTheme.DIM)
	v.add_child(sub)
	v.add_child(UiTheme.spacer(false, Vector2(0, 30)))

	_continue_btn = UiTheme.button("Continue", UiTheme.ACCENT, 22)
	_continue_btn.custom_minimum_size = Vector2(320, 54)
	_continue_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_continue_btn.pressed.connect(func() -> void: continue_requested.emit())
	v.add_child(_continue_btn)
	_summary = UiTheme.hud_label("", 15, UiTheme.DIM)
	v.add_child(_summary)
	var new_btn := UiTheme.ghost_button("New game", 20)
	new_btn.custom_minimum_size = Vector2(320, 48)
	new_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	new_btn.pressed.connect(_on_new)
	v.add_child(new_btn)
	var set_btn := UiTheme.ghost_button("Settings", 20)
	set_btn.custom_minimum_size = Vector2(320, 48)
	set_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	set_btn.pressed.connect(func() -> void: _settings.open_screen())
	v.add_child(set_btn)
	var quit_btn := UiTheme.ghost_button("Quit", 20)
	quit_btn.custom_minimum_size = Vector2(320, 48)
	quit_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	quit_btn.pressed.connect(func() -> void: quit_requested.emit())
	v.add_child(quit_btn)
	_notice = UiTheme.hud_label("", 17, UiTheme.ORANGE)
	v.add_child(_notice)

	var ver := UiTheme.hud_label("v%s" % ProjectSettings.get_setting("application/config/version", "0.2.0"), 14, UiTheme.DIM)
	add_child(ver)
	ver.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 24)
	ver.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	ver.grow_vertical = Control.GROW_DIRECTION_BEGIN

	_settings = UiScreen.new()
	_settings.build("Settings", 420, 80)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var sp := SettingsPanel.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(sp)
	_settings.content.add_child(scroll)
	add_child(_settings)

	_confirm = UiScreen.new()
	_confirm.build("Start over?", 600, 360)
	var msg := UiTheme.label("This erases your current save: every credit, upgrade and hole.", 19, UiTheme.TEXT)
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_confirm.content.add_child(msg)
	_confirm.content.add_child(UiTheme.spacer())
	var yes := UiTheme.button("Erase and start a new game", UiTheme.BAD, 19)
	yes.pressed.connect(func() -> void:
		_confirm.visible = false
		new_game_requested.emit())
	_confirm.content.add_child(yes)
	add_child(_confirm)


func refresh() -> void:
	var info := SaveSystem.peek()
	_continue_btn.visible = not info.is_empty()
	_summary.visible = not info.is_empty()
	if not info.is_empty():
		var mins := int(float(info["playtime"]) / 60.0)
		var pname := str(GameData.planet(str(info["planet"])).get("name", "?"))
		_summary.text = "%s   ·   %s credits   ·   %d discoveries   ·   %dh %02dm" % [pname, GameData.format_money(int(info["money"])), int(info["discoveries"]), mins / 60, mins % 60]


func show_notice(text: String) -> void:
	_notice.text = text


func _on_new() -> void:
	if SaveSystem.has_save():
		_confirm.open_screen()
	else:
		new_game_requested.emit()
