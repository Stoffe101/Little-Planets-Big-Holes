class_name Hud
extends CanvasLayer
## In-game HUD: credits, backpack, objective tracker, tool hotbar, crosshair, interaction
## prompt, pickup feed, hints, discovery popups and the F3 debug overlay.

var world: World
var root: Control
var _money_label: Label
var _money_shown := 0.0
var _money_delta: Label
var _pack_bar: ProgressBar
var _pack_label: Label
var _pack_panel: PanelContainer
var _pack_full_label: Label
var _obj_text: Label
var _obj_bar: ProgressBar
var _obj_progress: Label
var _obj_reward: Label
var _obj_panel: PanelContainer
var _hotbar: HBoxContainer
var _slots: Array[Dictionary] = []
var _tool_name: Label
var _cooldown_bar: ProgressBar
var _crosshair: Control
var _prompt: PanelContainer
var _prompt_label: Label
var _feed: VBoxContainer
var _feed_entries: Dictionary = {}     ## material index -> {label, units, time}
var _toasts: VBoxContainer
var _depth_label: Label
var _jet_bar: ProgressBar
var _scan_label: Label
var _discovery: PanelContainer
var _debug: Label
var _save_label: Label
var _banner: Label
var _pack_shake := 0.0
var _interact_target: Object
var _debug_timer := 0.0
var _last_hint := ""
var _last_hint_time := -10.0


func setup(w: World) -> void:
	world = w
	layer = 5
	root = Control.new()
	root.name = "HudRoot"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UiTheme.theme()
	add_child(root)
	_build()
	GameState.money_changed.connect(_on_money_changed)
	GameState.inventory_changed.connect(_refresh_pack)
	GameState.inventory_full.connect(_on_full)
	GameState.objective_changed.connect(_refresh_objective)
	GameState.objective_completed.connect(_on_objective_completed)
	GameState.tools_changed.connect(_refresh_hotbar)
	GameState.equipped_changed.connect(func(_f: String) -> void: _refresh_hotbar())
	GameState.gear_changed.connect(func(_g: String) -> void:
		_refresh_pack()
		_refresh_hotbar())
	world.message.connect(_on_message)
	world.discovery_popup.connect(show_discovery)
	_money_shown = float(GameState.money)
	_refresh_pack()
	_refresh_objective()
	_refresh_hotbar()


# ------------------------------------------------------------------ construction

func _margin(parent: Control, preset: Control.LayoutPreset, offset: Vector2) -> MarginContainer:
	var m := MarginContainer.new()
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(m)
	m.set_anchors_and_offsets_preset(preset, Control.PRESET_MODE_MINSIZE)
	m.add_theme_constant_override("margin_left", int(absf(offset.x)))
	m.add_theme_constant_override("margin_right", int(absf(offset.x)))
	m.add_theme_constant_override("margin_top", int(absf(offset.y)))
	m.add_theme_constant_override("margin_bottom", int(absf(offset.y)))
	m.grow_horizontal = Control.GROW_DIRECTION_BOTH
	m.grow_vertical = Control.GROW_DIRECTION_BOTH
	return m


func _panel(color := UiTheme.PANEL, alpha := 0.86) -> PanelContainer:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("panel", UiTheme.panel_box(color, 20, alpha))
	return p


func _build() -> void:
	# ---- top-left: money + backpack
	var tl := _margin(root, Control.PRESET_TOP_LEFT, Vector2(28, 24))
	tl.grow_horizontal = Control.GROW_DIRECTION_END
	tl.grow_vertical = Control.GROW_DIRECTION_END
	var tl_box := VBoxContainer.new()
	tl_box.add_theme_constant_override("separation", 10)
	tl_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tl.add_child(tl_box)
	var money_panel := _panel()
	tl_box.add_child(money_panel)
	var mh := HBoxContainer.new()
	mh.add_theme_constant_override("separation", 12)
	money_panel.add_child(mh)
	mh.add_child(UiIcon.make("coin", UiTheme.YELLOW, 46))
	_money_label = UiTheme.label("0", 40, UiTheme.CREAM, true)
	_money_label.custom_minimum_size = Vector2(130, 0)
	mh.add_child(_money_label)
	_money_delta = UiTheme.hud_label("", 30, UiTheme.GREEN)
	_money_delta.modulate.a = 0.0
	mh.add_child(_money_delta)

	_pack_panel = _panel()
	tl_box.add_child(_pack_panel)
	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", 4)
	_pack_panel.add_child(pv)
	var ph := HBoxContainer.new()
	ph.add_theme_constant_override("separation", 12)
	pv.add_child(ph)
	ph.add_child(UiIcon.make("pack", UiTheme.PINK, 40))
	_pack_bar = ProgressBar.new()
	_pack_bar.custom_minimum_size = Vector2(190, 26)
	_pack_bar.show_percentage = false
	_pack_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ph.add_child(_pack_bar)
	_pack_label = UiTheme.label("0 / 40", 26, UiTheme.CREAM, true)
	ph.add_child(_pack_label)
	_pack_full_label = UiTheme.label("BACKPACK FULL - sell at the rocket!", 20, UiTheme.YELLOW, true)
	_pack_full_label.visible = false
	pv.add_child(_pack_full_label)

	_debug = UiTheme.hud_label("", 18, UiTheme.CREAM)
	_debug.visible = bool(Settings.get_value("show_debug"))
	tl_box.add_child(_debug)

	# ---- top-right: objective
	var tr := _margin(root, Control.PRESET_TOP_RIGHT, Vector2(28, 24))
	tr.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	tr.grow_vertical = Control.GROW_DIRECTION_END
	_obj_panel = _panel()
	_obj_panel.custom_minimum_size = Vector2(430, 0)
	tr.add_child(_obj_panel)
	var ov := VBoxContainer.new()
	ov.add_theme_constant_override("separation", 6)
	_obj_panel.add_child(ov)
	var oh := HBoxContainer.new()
	oh.add_theme_constant_override("separation", 8)
	ov.add_child(oh)
	oh.add_child(UiIcon.make("star", UiTheme.YELLOW, 28))
	oh.add_child(UiTheme.label("NEXT GOAL", 20, UiTheme.YELLOW, true))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	oh.add_child(spacer)
	_obj_reward = UiTheme.label("", 20, UiTheme.GREEN, true)
	oh.add_child(_obj_reward)
	_obj_text = UiTheme.label("", 25, UiTheme.CREAM)
	_obj_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_obj_text.custom_minimum_size = Vector2(390, 0)
	ov.add_child(_obj_text)
	var obh := HBoxContainer.new()
	obh.add_theme_constant_override("separation", 10)
	ov.add_child(obh)
	_obj_bar = ProgressBar.new()
	_obj_bar.custom_minimum_size = Vector2(0, 18)
	_obj_bar.show_percentage = false
	_obj_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_obj_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_obj_bar.add_theme_stylebox_override("fill", UiTheme.box(UiTheme.YELLOW, 8, 3, UiTheme.INK, 0, 0))
	obh.add_child(_obj_bar)
	_obj_progress = UiTheme.label("", 20, UiTheme.MUTED, true)
	obh.add_child(_obj_progress)

	# ---- right: pickup feed
	var rc := _margin(root, Control.PRESET_CENTER_RIGHT, Vector2(28, 0))
	rc.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_feed = VBoxContainer.new()
	_feed.alignment = BoxContainer.ALIGNMENT_END
	_feed.add_theme_constant_override("separation", 2)
	_feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rc.add_child(_feed)

	# ---- top-centre: toasts + banner
	var tc := _margin(root, Control.PRESET_CENTER_TOP, Vector2(0, 110))
	tc.grow_vertical = Control.GROW_DIRECTION_END
	var tcv := VBoxContainer.new()
	tcv.add_theme_constant_override("separation", 8)
	tcv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tc.add_child(tcv)
	_banner = UiTheme.hud_label("", 44, UiTheme.YELLOW)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.modulate.a = 0.0
	tcv.add_child(_banner)
	_toasts = VBoxContainer.new()
	_toasts.add_theme_constant_override("separation", 6)
	_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tcv.add_child(_toasts)

	# ---- centre: crosshair + prompt
	_crosshair = _Crosshair.new()
	_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_crosshair)
	_crosshair.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_crosshair.custom_minimum_size = Vector2(64, 64)
	_crosshair.size = Vector2(64, 64)
	_crosshair.position -= Vector2(32, 32)

	var pc := _margin(root, Control.PRESET_CENTER, Vector2(0, 0))
	pc.position.y += 120
	_prompt = _panel(UiTheme.PANEL_DARK, 0.9)
	_prompt.visible = false
	pc.add_child(_prompt)
	var prh := HBoxContainer.new()
	prh.add_theme_constant_override("separation", 12)
	_prompt.add_child(prh)
	var key := PanelContainer.new()
	key.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.YELLOW, 10, 0, UiTheme.YELLOW.darkened(0.4), 4, 12))
	key.add_child(UiTheme.label("E", 26, UiTheme.INK, true))
	prh.add_child(key)
	_prompt_label = UiTheme.label("", 26, UiTheme.CREAM, true)
	prh.add_child(_prompt_label)

	# ---- bottom-centre: hotbar
	var bc := _margin(root, Control.PRESET_CENTER_BOTTOM, Vector2(0, 26))
	bc.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var bv := VBoxContainer.new()
	bv.add_theme_constant_override("separation", 6)
	bv.alignment = BoxContainer.ALIGNMENT_END
	bv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bc.add_child(bv)
	_tool_name = UiTheme.hud_label("", 26, UiTheme.CREAM)
	_tool_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bv.add_child(_tool_name)
	_cooldown_bar = ProgressBar.new()
	_cooldown_bar.custom_minimum_size = Vector2(240, 10)
	_cooldown_bar.show_percentage = false
	_cooldown_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_cooldown_bar.add_theme_stylebox_override("fill", UiTheme.box(UiTheme.PINK, 5, 0, UiTheme.INK, 0, 0))
	_cooldown_bar.modulate.a = 0.0
	bv.add_child(_cooldown_bar)
	_hotbar = HBoxContainer.new()
	_hotbar.add_theme_constant_override("separation", 12)
	_hotbar.alignment = BoxContainer.ALIGNMENT_CENTER
	_hotbar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bv.add_child(_hotbar)
	for fam in GameData.tool_families:
		var slot := PanelContainer.new()
		slot.custom_minimum_size = Vector2(92, 92)
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_hotbar.add_child(slot)
		var icon := UiIcon.make(str(fam["id"]), Color(str(fam["color"])), 64)
		icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		slot.add_child(icon)
		var num := UiTheme.hud_label(str(int(fam["slot"])), 20, UiTheme.CREAM)
		num.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		num.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		slot.add_child(num)
		_slots.append({"id": fam["id"], "panel": slot, "icon": icon, "color": Color(str(fam["color"]))})

	# ---- bottom-right: depth, jets, scanner, save
	var br := _margin(root, Control.PRESET_BOTTOM_RIGHT, Vector2(28, 26))
	br.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	br.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var brv := VBoxContainer.new()
	brv.alignment = BoxContainer.ALIGNMENT_END
	brv.add_theme_constant_override("separation", 6)
	brv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	br.add_child(brv)
	_save_label = UiTheme.hud_label("", 20, UiTheme.MUTED)
	_save_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_save_label.modulate.a = 0.0
	brv.add_child(_save_label)
	_scan_label = UiTheme.hud_label("", 22, UiTheme.SKY)
	_scan_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	brv.add_child(_scan_label)
	_jet_bar = ProgressBar.new()
	_jet_bar.custom_minimum_size = Vector2(200, 16)
	_jet_bar.show_percentage = false
	_jet_bar.size_flags_horizontal = Control.SIZE_SHRINK_END
	_jet_bar.max_value = 1.0
	_jet_bar.step = 0.001
	_jet_bar.add_theme_stylebox_override("fill", UiTheme.box(UiTheme.ORANGE, 7, 3, UiTheme.INK, 0, 0))
	brv.add_child(_jet_bar)
	_depth_label = UiTheme.hud_label("", 28, UiTheme.CREAM)
	_depth_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	brv.add_child(_depth_label)

	# ---- discovery popup
	var dc := _margin(root, Control.PRESET_CENTER_TOP, Vector2(0, 200))
	dc.grow_vertical = Control.GROW_DIRECTION_END
	_discovery = _panel(UiTheme.PANEL, 0.96)
	_discovery.custom_minimum_size = Vector2(720, 0)
	_discovery.visible = false
	dc.add_child(_discovery)


# ------------------------------------------------------------------ refreshers

func _on_money_changed(_amount: int, delta: int) -> void:
	if delta != 0:
		_money_delta.text = ("+%s" if delta > 0 else "-%s") % GameData.format_money(absi(delta))
		_money_delta.add_theme_color_override("font_color", UiTheme.GREEN if delta > 0 else UiTheme.RED)
		_money_delta.modulate.a = 1.0
		var tw := create_tween()
		tw.tween_interval(1.1)
		tw.tween_property(_money_delta, "modulate:a", 0.0, 0.5)
		_money_label.pivot_offset = _money_label.size * 0.5
		var pop := create_tween()
		pop.tween_property(_money_label, "scale", Vector2(1.18, 1.18), 0.07)
		pop.tween_property(_money_label, "scale", Vector2.ONE, 0.18)


func _refresh_pack() -> void:
	var cap := GameState.capacity()
	var n := GameState.inventory_count()
	_pack_bar.max_value = cap
	_pack_bar.value = n
	_pack_label.text = "%d / %d" % [n, cap]
	var full := n >= cap
	_pack_full_label.visible = full
	var col := UiTheme.RED if full else (UiTheme.ORANGE if float(n) / float(maxi(cap, 1)) > 0.8 else UiTheme.TEAL)
	_pack_bar.add_theme_stylebox_override("fill", UiTheme.box(col, 8, 3, UiTheme.INK, 0, 0))


func _on_full() -> void:
	_pack_shake = 1.0
	Audio.play("ui_error", -10.0, 1.0, 0.0, 2.5)


func _refresh_objective() -> void:
	var o := GameState.current_objective()
	_obj_panel.visible = not o.is_empty()
	if o.is_empty():
		return
	_obj_text.text = str(o["text"])
	var reward := int(o.get("reward", 0))
	_obj_reward.text = "+%s" % GameData.format_money(reward) if reward > 0 else ""
	var prog := GameState.objective_progress()
	_obj_bar.max_value = 1.0
	_obj_bar.step = 0.001
	_obj_bar.value = float(prog["ratio"])
	_obj_progress.text = str(prog["label"])
	_obj_bar.visible = str(prog["label"]) != ""
	_obj_progress.visible = _obj_bar.visible


func _on_objective_completed(o: Dictionary) -> void:
	Audio.play("objective", -3.0)
	show_banner("GOAL COMPLETE!  +%s" % GameData.format_money(int(o.get("reward", 0))) if int(o.get("reward", 0)) > 0 else "GOAL COMPLETE!", UiTheme.YELLOW)
	_obj_panel.pivot_offset = _obj_panel.size * 0.5
	var tw := create_tween()
	tw.tween_property(_obj_panel, "scale", Vector2(1.08, 1.08), 0.1)
	tw.tween_property(_obj_panel, "scale", Vector2.ONE, 0.25)


func show_banner(text: String, color: Color, hold := 1.8) -> void:
	_banner.text = text
	_banner.add_theme_color_override("font_color", color)
	_banner.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(_banner, "modulate:a", 1.0, 0.15)
	tw.tween_interval(hold)
	tw.tween_property(_banner, "modulate:a", 0.0, 0.6)


func _refresh_hotbar() -> void:
	for s in _slots:
		var owned := GameState.owns_family(s["id"])
		var selected: bool = GameState.equipped == s["id"]
		var panel: PanelContainer = s["panel"]
		var bg := UiTheme.PANEL_LIGHT if selected else UiTheme.PANEL_DARK
		var sb := UiTheme.box(Color(bg.r, bg.g, bg.b, 0.92), 18, 5 if selected else 4, UiTheme.YELLOW if selected else UiTheme.INK, 0, 8)
		panel.add_theme_stylebox_override("panel", sb)
		var icon: UiIcon = s["icon"]
		icon.icon = str(s["id"]) if owned else "lock"
		icon.color = (s["color"] as Color) if owned else Color(0.45, 0.43, 0.6)
		panel.modulate = Color(1, 1, 1, 1.0 if owned else 0.6)
		panel.scale = Vector2.ONE * (1.08 if selected else 1.0)
		panel.pivot_offset = Vector2(46, 92)
	var def := GameState.current_tier_def(GameState.equipped)
	_tool_name.text = str(def.get("name", ""))


# ------------------------------------------------------------------ messages

func _on_message(text: String, kind: String) -> void:
	match kind:
		"pickup":
			var parts := text.split("|")
			_feed_add(int(parts[0]), int(parts[1]))
		"hint":
			toast(text, UiTheme.CREAM)
		"save":
			_save_label.text = text
			_save_label.modulate.a = 1.0
			var tw := create_tween()
			tw.tween_interval(1.5)
			tw.tween_property(_save_label, "modulate:a", 0.0, 0.8)
		_:
			toast(text, UiTheme.CREAM)


func toast(text: String, color := UiTheme.CREAM) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if text == _last_hint and now - _last_hint_time < 2.5:
		return
	_last_hint = text
	_last_hint_time = now
	while _toasts.get_child_count() >= 3:
		var old := _toasts.get_child(0)
		_toasts.remove_child(old)
		old.queue_free()
	var p := _panel(UiTheme.PANEL_DARK, 0.88)
	p.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	p.add_child(UiTheme.label(text, 24, color, true))
	_toasts.add_child(p)
	var tw := p.create_tween()
	tw.tween_interval(2.8)
	tw.tween_property(p, "modulate:a", 0.0, 0.5)
	tw.tween_callback(p.queue_free)


func _feed_add(mat: int, units: int) -> void:
	var def := GameData.materials[mat]
	var now := Time.get_ticks_msec() / 1000.0
	if _feed_entries.has(mat) and is_instance_valid(_feed_entries[mat]["label"]) and now - float(_feed_entries[mat]["time"]) < 2.2:
		var e: Dictionary = _feed_entries[mat]
		e["units"] = int(e["units"]) + units
		e["time"] = now
		(e["label"] as Label).text = "+%d  %s" % [e["units"], def["name"]]
		(e["label"] as Label).modulate.a = 1.0
		return
	if _feed.get_child_count() >= 6:
		var old := _feed.get_child(0)
		_feed.remove_child(old)
		old.queue_free()
	var l := UiTheme.hud_label("+%d  %s" % [units, def["name"]], 24, (def["color2_c"] as Color).lightened(0.25))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_feed.add_child(l)
	_feed_entries[mat] = {"label": l, "units": units, "time": now}


## Big celebratory popup for discoveries.
func show_discovery(id: String) -> void:
	var d := GameData.discovery(id)
	if d.is_empty():
		return
	for c in _discovery.get_children():
		c.queue_free()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	_discovery.add_child(v)
	var kind := str(d.get("kind", "artifact"))
	var head := UiTheme.label({"artifact": "ARTIFACT FOUND!", "place": "PLACE DISCOVERED!", "core": "PLANET HEART AWAKENED!"}.get(kind, "DISCOVERY!"), 26, UiTheme.YELLOW, true)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(head)
	var title := UiTheme.label(str(d["name"]), 44, UiTheme.CREAM, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var desc := UiTheme.label(str(d["desc"]), 24, UiTheme.MUTED)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.custom_minimum_size = Vector2(660, 0)
	v.add_child(desc)
	if int(d.get("reward", 0)) > 0:
		var r := UiTheme.label("+%s credits" % GameData.format_money(int(d["reward"])), 30, UiTheme.GREEN, true)
		r.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(r)
	if d.has("unlock_text"):
		var u := UiTheme.label(str(d["unlock_text"]), 24, UiTheme.TEAL, true)
		u.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		u.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		u.custom_minimum_size = Vector2(660, 0)
		v.add_child(u)
	_discovery.visible = true
	_discovery.modulate.a = 0.0
	_discovery.scale = Vector2(0.8, 0.8)
	_discovery.pivot_offset = Vector2(360, 80)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_discovery, "modulate:a", 1.0, 0.25)
	tw.tween_property(_discovery, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.chain().tween_interval(5.5 if kind != "core" else 8.0)
	tw.chain().tween_property(_discovery, "modulate:a", 0.0, 0.7)
	tw.chain().tween_callback(func() -> void: _discovery.visible = false)


# ------------------------------------------------------------------ per-frame

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_debug"):
		_debug.visible = not _debug.visible
		Settings.set_value("show_debug", _debug.visible)
	if world == null or world.player == null or world.player.controls_locked:
		return
	if event.is_action_pressed("interact") and _interact_target != null and is_instance_valid(_interact_target):
		var action: Variant = _interact_target.get_meta("action", null)
		if action is Callable:
			(action as Callable).call()
			get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if world == null or world.player == null:
		return
	# money roll-up
	_money_shown = lerpf(_money_shown, float(GameState.money), clampf(delta * 9.0, 0.0, 1.0))
	if absf(_money_shown - float(GameState.money)) < 0.6:
		_money_shown = float(GameState.money)
	_money_label.text = GameData.format_money(int(round(_money_shown)))

	# backpack shake when full
	if _pack_shake > 0.0:
		_pack_shake = maxf(0.0, _pack_shake - delta * 2.5)
		_pack_panel.position.x = sin(_pack_shake * 40.0) * 7.0 * _pack_shake

	var player := world.player
	# depth / altitude
	var d := player.depth
	_depth_label.text = "Depth  %d m" % int(round(d)) if d > 1.0 else ""
	var jets := int(GameState.gear_value("jets"))
	_jet_bar.visible = jets >= 2
	_jet_bar.value = player.jet_fuel
	if GameState.gear_level("scanner") > 0 and world.scanner != null:
		var cd: float = world.scanner.get("cooldown")
		_scan_label.text = "[Q] Scan ready" if cd <= 0.0 else "Scanner  %.1fs" % cd
		_scan_label.modulate.a = 1.0 if cd <= 0.0 else 0.6
	else:
		_scan_label.text = ""

	# cannon / slow tool cooldown bar
	var tools := world.tools
	if tools != null and tools.cooldown_total > 0.8:
		_cooldown_bar.max_value = 1.0
		_cooldown_bar.step = 0.001
		_cooldown_bar.value = 1.0 - tools.cooldown_ratio()
		_cooldown_bar.modulate.a = lerpf(_cooldown_bar.modulate.a, 1.0 if tools.cooldown > 0.0 else 0.0, clampf(delta * 8.0, 0.0, 1.0))
	else:
		_cooldown_bar.modulate.a = 0.0

	# feed fade
	var now := Time.get_ticks_msec() / 1000.0
	for mat: int in _feed_entries.keys():
		var e: Dictionary = _feed_entries[mat]
		if not is_instance_valid(e["label"]):
			_feed_entries.erase(mat)
			continue
		var age := now - float(e["time"])
		if age > 2.2:
			(e["label"] as Label).modulate.a = clampf(1.0 - (age - 2.2) / 0.6, 0.0, 1.0)
			if age > 2.9:
				(e["label"] as Label).queue_free()
				_feed_entries.erase(mat)

	_update_interaction()
	(_crosshair as _Crosshair).interact = _interact_target != null
	_crosshair.visible = not player.controls_locked

	if _debug.visible:
		_debug_timer -= delta
		if _debug_timer <= 0.0:
			_debug_timer = 0.25
			_update_debug()


func _update_interaction() -> void:
	var player := world.player
	_interact_target = null
	if not player.controls_locked:
		var from := player.eye_position()
		var q := PhysicsRayQueryParameters3D.create(from, from + player.aim_direction() * 4.6, 1 | 4 | 8)
		q.exclude = [player.get_rid()]
		var hit := player.get_world_3d().direct_space_state.intersect_ray(q)
		if not hit.is_empty() and (hit["collider"] as Object).has_meta("prompt"):
			_interact_target = hit["collider"]
	if _interact_target != null:
		_prompt_label.text = str(_interact_target.get_meta("prompt"))
		_prompt.visible = true
	else:
		_prompt.visible = false


func _update_debug() -> void:
	var p := world.planet
	var stats: Dictionary = VoxelEngine.get_stats()
	var tasks: Dictionary = stats.get("tasks", {})
	var mem: Dictionary = stats.get("memory_pools", {})
	var lines: Array[String] = []
	lines.append("FPS %d   frame %.1f ms" % [Engine.get_frames_per_second(), 1000.0 / maxf(Engine.get_frames_per_second(), 1.0)])
	lines.append("draw calls %d   prims %dk" % [int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)), int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000.0)])
	lines.append("voxel tasks: gen %d  mesh %d  stream %d  main %d" % [int(tasks.get("generation", 0)), int(tasks.get("meshing", 0)), int(tasks.get("streaming", 0)), int(tasks.get("main_thread", 0))])
	lines.append("voxel blocks %d   voxel mem %.1f MB" % [int(mem.get("block_count", 0)), float(mem.get("voxel_used", 0)) / 1048576.0])
	lines.append("digs %d   last %.2f ms   avg %.2f ms" % [world.dig.total_digs, world.dig.last_dig_usec / 1000.0, world.dig.average_dig_ms()])
	lines.append("pickups %d   props %s   bots %s" % [world.pickups.count(), str(world.props.get("prop_count")) if world.props != null else "-", str((world.robots.get("bots") as Array).size()) if world.robots != null else "-"])
	lines.append("static mem %.0f MB   planet load %d ms" % [OS.get_static_memory_usage() / 1048576.0, p.load_time_ms])
	lines.append("pos r=%.1f  depth %.1f  mat %s" % [world.player.global_position.length(), world.player.depth, GameData.mat_id(p.material_at(world.player.global_position - world.player.up * 0.5))])
	_debug.text = "\n".join(lines)


class _Crosshair:
	extends Control
	var interact := false:
		set(v):
			if v != interact:
				interact = v
				queue_redraw()

	func _draw() -> void:
		var c := size * 0.5
		var ink := Color(0.1, 0.07, 0.2, 0.85)
		if interact:
			draw_arc(c, 13.0, 0, TAU, 24, ink, 6.0, true)
			draw_arc(c, 13.0, 0, TAU, 24, UiTheme.YELLOW, 3.0, true)
		else:
			draw_circle(c, 5.0, ink)
			draw_circle(c, 3.0, Color(1, 1, 1, 0.95))
