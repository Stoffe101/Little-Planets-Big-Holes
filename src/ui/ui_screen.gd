class_name UiScreen
extends Control
## Base for modal screens: a dimmed backdrop with a centred, titled panel and a close button.

signal closed()

var content: VBoxContainer
var title_label: Label
var _margin: MarginContainer


func build(title: String, side_margin := 300, top_margin := 110, color := UiTheme.YELLOW) -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = UiTheme.theme()
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0.06, 0.04, 0.14, 0.66)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	_margin = MarginContainer.new()
	_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	_margin.add_theme_constant_override("margin_left", side_margin)
	_margin.add_theme_constant_override("margin_right", side_margin)
	_margin.add_theme_constant_override("margin_top", top_margin)
	_margin.add_theme_constant_override("margin_bottom", top_margin)
	add_child(_margin)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.panel_box(UiTheme.PANEL, 28, 0.98))
	_margin.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	panel.add_child(v)
	var header := HBoxContainer.new()
	v.add_child(header)
	title_label = UiTheme.label(title, 44, color, true)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_label)
	var close := UiTheme.button("Close  [Esc]", UiTheme.PINK, 24)
	close.pressed.connect(close_screen)
	header.add_child(close)
	content = VBoxContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 12)
	v.add_child(content)


func open_screen() -> void:
	visible = true
	Audio.play("ui_open", -8.0)
	refresh()


func close_screen() -> void:
	if not visible:
		return
	visible = false
	Audio.play("ui_close", -8.0)
	closed.emit()


func refresh() -> void:
	pass


func clear_content() -> void:
	for c in content.get_children():
		content.remove_child(c)
		c.queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("pause"):
		close_screen()
		get_viewport().set_input_as_handled()
