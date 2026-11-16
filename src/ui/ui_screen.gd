class_name UiScreen
extends Control
## Base for modal screens: a dimmed backdrop with a centred, titled panel and a close button.

signal closed()

const MAX_WIDTH := 1500.0

var content: VBoxContainer
var title_label: Label
var _margin: MarginContainer
var _side_margin := 300


func build(title: String, side_margin := 300, top_margin := 110, _color := UiTheme.ACCENT) -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = UiTheme.theme()
	visible = false
	_side_margin = side_margin
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.04, 0.05, 0.66)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	_margin = MarginContainer.new()
	_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	_margin.add_theme_constant_override("margin_top", top_margin)
	_margin.add_theme_constant_override("margin_bottom", top_margin)
	add_child(_margin)
	resized.connect(_fit_margins)
	_fit_margins()
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.panel_box(UiTheme.PANEL, 10, 0.97, 24))
	_margin.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	panel.add_child(v)
	var header := HBoxContainer.new()
	v.add_child(header)
	title_label = UiTheme.label(title, 30, UiTheme.TEXT, true)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_label)
	var close := UiTheme.ghost_button("Close   Esc", 17)
	close.pressed.connect(close_screen)
	header.add_child(close)
	v.add_child(UiTheme.divider())
	content = VBoxContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 12)
	v.add_child(content)


## Side margins grow on wide screens so the panel never stretches past MAX_WIDTH.
func _fit_margins() -> void:
	if _margin == null:
		return
	var side := maxf(float(_side_margin), (size.x - MAX_WIDTH) * 0.5)
	_margin.add_theme_constant_override("margin_left", int(side))
	_margin.add_theme_constant_override("margin_right", int(side))


func open_screen() -> void:
	visible = true
	_fit_margins()
	Audio.play("ui_open", -10.0)
	refresh()


func close_screen() -> void:
	if not visible:
		return
	visible = false
	Audio.play("ui_close", -10.0)
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
