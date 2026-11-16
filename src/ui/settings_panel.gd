class_name SettingsPanel
extends VBoxContainer
## Reusable settings list (used by the pause menu and the main menu).


func _init() -> void:
	add_theme_constant_override("separation", 8)
	_section("CONTROLS")
	_slider("Mouse sensitivity", "mouse_sensitivity", 0.05, 0.8, 0.01)
	_slider("Field of view", "fov", 60.0, 105.0, 1.0)
	_toggle("Invert Y axis", "invert_y")
	_toggle("Toggle sprint (instead of hold)", "toggle_sprint")
	_section("COMFORT")
	_slider("Camera shake", "camera_shake", 0.0, 1.0, 0.05)
	_slider("View bobbing", "view_bob", 0.0, 1.0, 0.05)
	_slider("Interface size", "ui_scale", 0.8, 1.4, 0.05)
	_section("SOUND")
	_slider("Master volume", "master_volume", 0.0, 1.0, 0.05)
	_slider("Effects volume", "sfx_volume", 0.0, 1.0, 0.05)
	_slider("Music volume", "music_volume", 0.0, 1.0, 0.05)
	_section("DISPLAY")
	_toggle("Fullscreen", "fullscreen")
	_toggle("V-Sync", "vsync")
	_slider("3D render scale", "render_scale", 0.5, 1.0, 0.05)
	_slider("Shadow quality", "shadow_quality", 0.0, 3.0, 1.0)
	var reset := UiTheme.button("Reset to defaults", UiTheme.MUTED, 22)
	reset.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	reset.pressed.connect(func() -> void:
		Settings.reset_to_defaults()
		for c in get_children():
			if c.has_meta("sync"):
				(c.get_meta("sync") as Callable).call())
	add_child(reset)


func _section(text: String) -> void:
	add_child(UiTheme.label(text, 22, UiTheme.YELLOW, true))


func _slider(text: String, key: String, lo: float, hi: float, step: float) -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	var l := UiTheme.label(text, 22, UiTheme.CREAM)
	l.custom_minimum_size = Vector2(330, 0)
	h.add_child(l)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = float(Settings.get_value(key))
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.custom_minimum_size = Vector2(260, 30)
	h.add_child(s)
	var val := UiTheme.label("", 22, UiTheme.MUTED, true)
	val.custom_minimum_size = Vector2(80, 0)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(val)
	var is_int: bool = Settings.DEFAULTS[key] is int
	var show := func(v: float) -> void:
		val.text = str(int(v)) if (is_int or step >= 1.0) else ("%d%%" % int(round(v * 100.0)) if hi <= 1.4 and key != "mouse_sensitivity" else "%.2f" % v)
	show.call(s.value)
	s.value_changed.connect(func(v: float) -> void:
		Settings.set_value(key, int(v) if is_int else v)
		show.call(v))
	h.set_meta("sync", func() -> void:
		s.set_value_no_signal(float(Settings.get_value(key)))
		show.call(s.value))
	add_child(h)


func _toggle(text: String, key: String) -> void:
	var c := CheckButton.new()
	c.text = text
	c.button_pressed = bool(Settings.get_value(key))
	c.toggled.connect(func(on: bool) -> void:
		Settings.set_value(key, on)
		Audio.play("ui_click", -8.0))
	c.set_meta("sync", func() -> void: c.set_pressed_no_signal(bool(Settings.get_value(key))))
	add_child(c)
