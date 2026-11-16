class_name MainMenu
extends Control
## Title screen: Continue / New Game / Settings / Quit over the 3D toy-planet backdrop.

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
	margin.add_theme_constant_override("margin_left", 120)
	margin.add_theme_constant_override("margin_top", 90)
	margin.add_theme_constant_override("margin_bottom", 60)
	margin.add_theme_constant_override("margin_right", 60)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	v.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(v)
	var t1 := UiTheme.hud_label("Little Planets,", 92, UiTheme.CREAM)
	v.add_child(t1)
	var t2 := UiTheme.hud_label("BIG HOLES", 148, UiTheme.YELLOW)
	t2.add_theme_constant_override("outline_size", 34)
	v.add_child(t2)
	var sub := UiTheme.hud_label("Start with a rusty scoop. End up moving mountains.", 30, UiTheme.TEAL)
	v.add_child(sub)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 36)
	v.add_child(gap)

	_continue_btn = UiTheme.button("Continue", UiTheme.GREEN, 36)
	_continue_btn.custom_minimum_size = Vector2(440, 84)
	_continue_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_continue_btn.pressed.connect(func() -> void: continue_requested.emit())
	v.add_child(_continue_btn)
	_summary = UiTheme.hud_label("", 22, UiTheme.MUTED)
	v.add_child(_summary)
	var new_btn := UiTheme.button("New Game", UiTheme.YELLOW, 32)
	new_btn.custom_minimum_size = Vector2(440, 72)
	new_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	new_btn.pressed.connect(_on_new)
	v.add_child(new_btn)
	var set_btn := UiTheme.button("Settings", UiTheme.SKY, 32)
	set_btn.custom_minimum_size = Vector2(440, 72)
	set_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	set_btn.pressed.connect(func() -> void: _settings.open_screen())
	v.add_child(set_btn)
	var quit_btn := UiTheme.button("Quit", UiTheme.PINK, 32)
	quit_btn.custom_minimum_size = Vector2(440, 72)
	quit_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	quit_btn.pressed.connect(func() -> void: quit_requested.emit())
	v.add_child(quit_btn)
	_notice = UiTheme.hud_label("", 24, UiTheme.ORANGE)
	v.add_child(_notice)

	var ver := UiTheme.hud_label("v%s  -  first playable" % ProjectSettings.get_setting("application/config/version", "0.1.0"), 20, UiTheme.MUTED)
	add_child(ver)
	ver.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 24)
	ver.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	ver.grow_vertical = Control.GROW_DIRECTION_BEGIN

	_settings = UiScreen.new()
	_settings.build("SETTINGS", 420, 80, UiTheme.SKY)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var sp := SettingsPanel.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(sp)
	_settings.content.add_child(scroll)
	add_child(_settings)

	_confirm = UiScreen.new()
	_confirm.build("START OVER?", 520, 330, UiTheme.ORANGE)
	var msg := UiTheme.label("This erases your current save - every credit, upgrade and hole.", 24, UiTheme.CREAM)
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_confirm.content.add_child(msg)
	var yes := UiTheme.button("Yes, fresh planet please", UiTheme.ORANGE, 28)
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
		_summary.text = "%s  -  %s credits  -  %d discoveries  -  %dh %02dm" % [pname, GameData.format_money(int(info["money"])), int(info["discoveries"]), mins / 60, mins % 60]


func show_notice(text: String) -> void:
	_notice.text = text


func _on_new() -> void:
	if SaveSystem.has_save():
		_confirm.open_screen()
	else:
		new_game_requested.emit()
