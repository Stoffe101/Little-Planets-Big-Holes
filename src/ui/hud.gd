class_name Hud
extends CanvasLayer
## In-game HUD. Deliberately quiet: small translucent chips in the corners, the world in the
## middle. Credits and backpack (top-left), current objective (top-right), tool bar (bottom
## centre), depth / base bearing / scanner / jets (bottom-right), first-minutes control hints
## (bottom-left), crosshair with a cooldown arc, interaction prompt, pickup feed, toasts,
## discovery cards and the F3 debug overlay.

const HINT_OBJECTIVES := 4          ## control hints stay up until this many objectives are done

var world: World
var root: Control
var _money_label: Label
var _money_shown := 0.0
var _money_delta: Label
var _pack_bar: ProgressBar
var _pack_label: Label
var _pack_value: Label
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
var _crosshair: _Crosshair
var _prompt: PanelContainer
var _prompt_label: Label
var _feed: VBoxContainer
var _feed_entries: Dictionary = {}     ## material index -> {row, label, units, time}
var _toasts: VBoxContainer
var _depth_label: Label
var _base_row: HBoxContainer
var _base_arrow: UiIcon
var _base_label: Label
var _jet_bar: ProgressBar
var _scan_label: Label
var _discovery: PanelContainer
var _debug: Label
var _save_label: Label
var _banner: Label
var _banner_sub: Label
var _hints: PanelContainer
var _pack_shake := 0.0
var _interact_target: Object
var _debug_timer := 0.0
var _last_hint := ""
var _last_hint_time := -10.0
var _banner_tween: Tween
var _dim_tween: Tween
var _dimmed := false
var _queued_banner: Array = []   ## banner raised while a menu hid the HUD
var _compass: CompassStrip
var _contract_text: Label
var _contract_progress: Label
var _contract_reward: Label
var _ground_wait := 0.0
var _compass_key := Vector4.INF      ## heading + position the compass was last drawn for
var _compass_age := 0.0


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
	GameState.purchase_made.connect(_on_purchase)
	world.message.connect(_on_message)
	world.discovery_popup.connect(show_discovery)
	if world.contracts != null:
		world.contracts.contract_changed.connect(func(_c: Dictionary) -> void: _refresh_contract())
		_refresh_contract()
	if world.nav != null:
		world.nav.region_changed.connect(func(r: Dictionary) -> void:
			show_banner(str(r.get("name", "")), UiTheme.INFO, 2.4, str((r.get("cfg", {}) as Dictionary).get("desc", ""))))
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


func _chip(alpha := 0.72, pad := 12) -> PanelContainer:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("panel", UiTheme.chip_box(alpha, pad))
	return p


func _hbox(sep := 8) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return h


func _vbox(sep := 6) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return v


func _build() -> void:
	# ---- top-left: credits + backpack in one chip
	var tl := _margin(root, Control.PRESET_TOP_LEFT, Vector2(24, 22))
	tl.grow_horizontal = Control.GROW_DIRECTION_END
	tl.grow_vertical = Control.GROW_DIRECTION_END
	var tl_box := _vbox(8)
	tl.add_child(tl_box)
	_pack_panel = _chip()
	_pack_panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	tl_box.add_child(_pack_panel)
	var pv := _vbox(6)
	_pack_panel.add_child(pv)
	var mh := _hbox(8)
	pv.add_child(mh)
	mh.add_child(UiIcon.make("coin", UiTheme.ACCENT, 22))
	_money_label = UiTheme.label("0", 26, UiTheme.TEXT, true)
	_money_label.custom_minimum_size = Vector2(70, 0)
	mh.add_child(_money_label)
	_money_delta = UiTheme.label("", 17, UiTheme.GOOD)
	_money_delta.modulate.a = 0.0
	_money_delta.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mh.add_child(_money_delta)
	var ph := _hbox(8)
	pv.add_child(ph)
	ph.add_child(UiIcon.make("pack", UiTheme.DIM, 18))
	_pack_bar = UiTheme.bar(150.0, 5.0, UiTheme.INFO)
	ph.add_child(_pack_bar)
	_pack_label = UiTheme.label("0 / 40", 16, UiTheme.TEXT)
	ph.add_child(_pack_label)
	_pack_value = UiTheme.label("", 16, UiTheme.DIM)
	ph.add_child(_pack_value)
	_pack_full_label = UiTheme.caps("Backpack full - sell at the depot", 13, UiTheme.BAD)
	_pack_full_label.visible = false
	pv.add_child(_pack_full_label)

	_debug = UiTheme.hud_label("", 14, UiTheme.TEXT)
	_debug.visible = bool(Settings.get_value("show_debug"))
	tl_box.add_child(_debug)

	# ---- top-right: objective
	var tr := _margin(root, Control.PRESET_TOP_RIGHT, Vector2(24, 22))
	tr.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	tr.grow_vertical = Control.GROW_DIRECTION_END
	_obj_panel = _chip()
	_obj_panel.custom_minimum_size = Vector2(340, 0)
	tr.add_child(_obj_panel)
	var ov := _vbox(5)
	_obj_panel.add_child(ov)
	var oh := _hbox(8)
	ov.add_child(oh)
	oh.add_child(UiTheme.caps("Objective", 13, UiTheme.ACCENT))
	oh.add_child(UiTheme.spacer())
	_obj_reward = UiTheme.label("", 15, UiTheme.GOOD)
	oh.add_child(_obj_reward)
	_obj_text = UiTheme.label("", 18, UiTheme.TEXT)
	_obj_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_obj_text.custom_minimum_size = Vector2(316, 0)
	ov.add_child(_obj_text)
	var obh := _hbox(10)
	ov.add_child(obh)
	_obj_bar = UiTheme.bar(0.0, 4.0, UiTheme.ACCENT)
	_obj_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	obh.add_child(_obj_bar)
	_obj_progress = UiTheme.label("", 14, UiTheme.DIM)
	obh.add_child(_obj_progress)
	# the open survey contract, under the objective
	ov.add_child(UiTheme.spacer(false, Vector2(0, 4)))
	var ch := _hbox(8)
	ov.add_child(ch)
	ch.add_child(UiTheme.caps("Contract", 13, UiTheme.INFO))
	ch.add_child(UiTheme.spacer())
	_contract_reward = UiTheme.label("", 15, UiTheme.GOLD)
	ch.add_child(_contract_reward)
	_contract_text = UiTheme.label("", 16, UiTheme.TEXT)
	_contract_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_contract_text.custom_minimum_size = Vector2(316, 0)
	ov.add_child(_contract_text)
	_contract_progress = UiTheme.label("", 13, UiTheme.DIM)
	ov.add_child(_contract_progress)

	# ---- right: pickup feed
	var rc := _margin(root, Control.PRESET_CENTER_RIGHT, Vector2(24, 0))
	rc.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_feed = _vbox(3)
	_feed.alignment = BoxContainer.ALIGNMENT_END
	rc.add_child(_feed)

	# ---- top: compass strip
	var cmp := _margin(root, Control.PRESET_CENTER_TOP, Vector2(0, 14))
	cmp.grow_vertical = Control.GROW_DIRECTION_END
	cmp.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_compass = CompassStrip.new()
	_compass.world = world
	cmp.add_child(_compass)

	# ---- top-centre: banner + toasts
	var tc := _margin(root, Control.PRESET_CENTER_TOP, Vector2(0, 84))
	tc.grow_vertical = Control.GROW_DIRECTION_END
	var tcv := _vbox(6)
	tc.add_child(tcv)
	_banner = UiTheme.hud_label("", 26, UiTheme.ACCENT)
	_banner.add_theme_font_override("font", UiTheme.font_caps())
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.modulate.a = 0.0
	tcv.add_child(_banner)
	_banner_sub = UiTheme.hud_label("", 18, UiTheme.TEXT)
	_banner_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_sub.modulate.a = 0.0
	tcv.add_child(_banner_sub)
	_toasts = _vbox(6)
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
	pc.position.y += 86
	_prompt = _chip(0.82, 10)
	_prompt.visible = false
	pc.add_child(_prompt)
	var prh := _hbox(10)
	_prompt.add_child(prh)
	var key := PanelContainer.new()
	key.mouse_filter = Control.MOUSE_FILTER_IGNORE
	key.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.ACCENT, 4, 0, UiTheme.LINE, 0, 8))
	key.add_child(UiTheme.label("E", 16, UiTheme.INK, true))
	prh.add_child(key)
	_prompt_label = UiTheme.label("", 18, UiTheme.TEXT)
	_prompt_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	prh.add_child(_prompt_label)

	# ---- bottom-centre: tool bar
	var bc := _margin(root, Control.PRESET_CENTER_BOTTOM, Vector2(0, 22))
	bc.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var bv := _vbox(8)
	bv.alignment = BoxContainer.ALIGNMENT_END
	bc.add_child(bv)
	_tool_name = UiTheme.hud_label("", 17, UiTheme.TEXT)
	_tool_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bv.add_child(_tool_name)
	_hotbar = _hbox(8)
	_hotbar.alignment = BoxContainer.ALIGNMENT_CENTER
	bv.add_child(_hotbar)
	for fam in GameData.tool_families:
		var slot := PanelContainer.new()
		slot.custom_minimum_size = Vector2(62, 62)
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_hotbar.add_child(slot)
		var icon := UiIcon.make(str(fam["id"]), UiTheme.TEXT, 34)
		icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		slot.add_child(icon)
		var num := UiTheme.label(str(int(fam["slot"])), 12, UiTheme.DIM)
		num.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		num.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		slot.add_child(num)
		var pip_holder := MarginContainer.new()
		pip_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pip_holder.size_flags_vertical = Control.SIZE_SHRINK_END
		pip_holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		slot.add_child(pip_holder)
		_slots.append({"id": fam["id"], "panel": slot, "icon": icon, "pips": pip_holder, "tiers": (fam["tiers"] as Array).size()})

	# ---- bottom-right: status column
	var br := _margin(root, Control.PRESET_BOTTOM_RIGHT, Vector2(24, 22))
	br.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	br.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var brv := _vbox(6)
	brv.alignment = BoxContainer.ALIGNMENT_END
	br.add_child(brv)
	_save_label = UiTheme.hud_label("", 14, UiTheme.DIM)
	_save_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_save_label.modulate.a = 0.0
	brv.add_child(_save_label)
	_scan_label = UiTheme.hud_label("", 15, UiTheme.INFO)
	_scan_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	brv.add_child(_scan_label)
	_jet_bar = UiTheme.bar(140.0, 5.0, UiTheme.ORANGE)
	_jet_bar.size_flags_horizontal = Control.SIZE_SHRINK_END
	brv.add_child(_jet_bar)
	_depth_label = UiTheme.hud_label("", 18, UiTheme.TEXT)
	_depth_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	brv.add_child(_depth_label)
	_base_row = _hbox(6)
	_base_row.alignment = BoxContainer.ALIGNMENT_END
	brv.add_child(_base_row)
	_base_arrow = UiIcon.make("arrow", UiTheme.ACCENT, 18)
	_base_row.add_child(_base_arrow)
	_base_label = UiTheme.hud_label("", 15, UiTheme.TEXT)
	_base_row.add_child(_base_label)

	# ---- bottom-left: control hints for the first minutes
	var bl := _margin(root, Control.PRESET_BOTTOM_LEFT, Vector2(24, 22))
	bl.grow_horizontal = Control.GROW_DIRECTION_END
	bl.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_hints = _chip(0.6, 12)
	bl.add_child(_hints)
	var hv := _vbox(4)
	_hints.add_child(hv)
	for row: Array in [["W A S D", "Move"], ["Shift", "Sprint"], ["Space", "Jump"], ["Left mouse", "Dig (hold)"], ["E", "Use shops / lander"], ["Tab", "Journal"]]:
		var h := _hbox(10)
		var k := UiTheme.label(str(row[0]), 14, UiTheme.TEXT, true)
		k.custom_minimum_size = Vector2(92, 0)
		h.add_child(k)
		h.add_child(UiTheme.label(str(row[1]), 14, UiTheme.DIM))
		hv.add_child(h)

	# ---- discovery card
	var dc := _margin(root, Control.PRESET_CENTER_TOP, Vector2(0, 150))
	dc.grow_vertical = Control.GROW_DIRECTION_END
	_discovery = PanelContainer.new()
	_discovery.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_discovery.add_theme_stylebox_override("panel", UiTheme.panel_box(UiTheme.PANEL, 8, 0.94, 22))
	_discovery.custom_minimum_size = Vector2(600, 0)
	_discovery.visible = false
	dc.add_child(_discovery)


## Fades the HUD chips out while a full-screen menu is open (banners stay readable).
func set_dimmed(on: bool) -> void:
	if root == null:
		return
	_dimmed = on
	if _dim_tween != null and _dim_tween.is_valid():
		_dim_tween.kill()
	_dim_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_dim_tween.tween_property(root, "modulate:a", 0.0 if on else 1.0, 0.12)
	if not on and not _queued_banner.is_empty():
		var b := _queued_banner
		_queued_banner = []
		show_banner(b[0], b[1], b[2], b[3])


# ------------------------------------------------------------------ refreshers

func _on_money_changed(_amount: int, delta: int) -> void:
	if delta != 0:
		_money_delta.text = ("+%s" if delta > 0 else "-%s") % GameData.format_money(absi(delta))
		_money_delta.add_theme_color_override("font_color", UiTheme.GOOD if delta > 0 else UiTheme.BAD)
		_money_delta.modulate.a = 1.0
		var tw := create_tween()
		tw.tween_interval(1.2)
		tw.tween_property(_money_delta, "modulate:a", 0.0, 0.5)


func _refresh_pack() -> void:
	var cap := GameState.capacity()
	var n := GameState.inventory_count()
	_pack_bar.max_value = cap
	_pack_bar.step = 1.0
	_pack_bar.value = n
	_pack_label.text = "%d / %d" % [n, cap]
	var value := GameState.inventory_value()
	_pack_value.text = "worth %s" % GameData.format_money(value) if value > 0 else ""
	var full := n >= cap
	_pack_full_label.visible = full
	var ratio := float(n) / float(maxi(cap, 1))
	UiTheme.set_bar_color(_pack_bar, UiTheme.BAD if full else (UiTheme.ORANGE if ratio > 0.8 else UiTheme.INFO))


func _on_full() -> void:
	_pack_shake = 1.0
	Audio.play("ui_error", -12.0, 1.0, 0.0, 2.5)


func _refresh_objective() -> void:
	var o := GameState.current_objective()
	_obj_panel.visible = not o.is_empty()
	if _hints != null:
		_hints.visible = GameState.objective_index < HINT_OBJECTIVES
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
	Audio.play("objective", -5.0)
	var reward := int(o.get("reward", 0))
	show_banner("Objective complete", UiTheme.ACCENT, 1.8, "+%s credits" % GameData.format_money(reward) if reward > 0 else "")


## A purchase is an event: name it on screen (the tool itself is shown off by ToolController).
func _on_purchase(kind: String, id: String) -> void:
	match kind:
		"tier":
			for fam in GameData.tool_families:
				for t: Dictionary in fam["tiers"]:
					if str(t["id"]) == id:
						show_banner("New equipment", UiTheme.ACCENT, 2.4, str(t["name"]))
		"mod":
			var parts := id.split("/")
			for m: Dictionary in GameData.family(parts[0]).get("mods", []):
				if str(m["id"]) == parts[1]:
					show_banner("Attachment fitted", UiTheme.INFO, 2.0, str(m["name"]))
		"gear":
			var g: Dictionary = GameData.gear_by_id.get(id, {})
			if not g.is_empty():
				var names: Array = g.get("level_names", [])
				var lvl := GameState.gear_level(id)
				show_banner("Gear upgraded", UiTheme.INFO, 2.0, str(names[lvl]) if lvl < names.size() else str(g["name"]))


func _refresh_contract() -> void:
	if world == null or world.contracts == null or _contract_text == null:
		return
	var c := world.contracts.current()
	_contract_text.text = str(c.get("text", ""))
	_contract_reward.text = "+%s" % GameData.format_money(int(c.get("reward", 0))) if not c.is_empty() else ""
	var amount := int(c.get("amount", 1))
	var prog := int(c.get("progress", 0))
	var where := str(c.get("region", ""))
	match str(c.get("kind", "")):
		"deliver":
			_contract_progress.text = "%d / %d delivered%s" % [prog, amount, ("  -  rich in %s" % where) if where != "" else ""]
		"depth":
			_contract_progress.text = "deepest so far %d m" % prog
		"relay":
			_contract_progress.text = where
		_:
			_contract_progress.text = ""


func show_banner(text: String, color: Color, hold := 1.8, sub := "") -> void:
	if _dimmed:
		_queued_banner = [text, color, hold, sub]     # shown when the menu closes
		return
	_banner.text = text.to_upper()
	_banner.add_theme_color_override("font_color", color)
	_banner_sub.text = sub
	_banner_sub.visible = sub != ""
	if _banner_tween != null and _banner_tween.is_valid():
		_banner_tween.kill()
	_banner.modulate.a = 0.0
	_banner_sub.modulate.a = 0.0
	_banner_tween = create_tween()
	_banner_tween.set_parallel(true)
	_banner_tween.tween_property(_banner, "modulate:a", 1.0, 0.18)
	_banner_tween.tween_property(_banner_sub, "modulate:a", 1.0, 0.3)
	_banner_tween.chain().tween_interval(hold)
	_banner_tween.chain().tween_property(_banner, "modulate:a", 0.0, 0.6)
	_banner_tween.parallel().tween_property(_banner_sub, "modulate:a", 0.0, 0.6)


func _refresh_hotbar() -> void:
	for s in _slots:
		var owned := GameState.owns_family(s["id"])
		var selected: bool = GameState.equipped == s["id"]
		var panel: PanelContainer = s["panel"]
		var bg := UiTheme.PANEL_LIGHT if selected else UiTheme.PANEL_DARK
		var sb := UiTheme.box(Color(bg.r, bg.g, bg.b, 0.86 if selected else 0.62), UiTheme.RADIUS, 1, Color(1, 1, 1, 0.07), 0, 6)
		if selected:
			sb.border_color = UiTheme.ACCENT
			sb.set_border_width_all(2)
		panel.add_theme_stylebox_override("panel", sb)
		var icon: UiIcon = s["icon"]
		icon.icon = str(s["id"]) if owned else "lock"
		icon.color = (UiTheme.TEXT if selected else UiTheme.DIM) if owned else UiTheme.FAINT
		var holder: MarginContainer = s["pips"]
		for c in holder.get_children():
			c.queue_free()
		if owned:
			holder.add_child(UiTheme.pips(int(s["tiers"]), GameState.tier_of(s["id"]), UiTheme.ACCENT, Vector2(9, 3)))
	var def := GameState.current_tier_def(GameState.equipped)
	_tool_name.text = str(def.get("name", ""))


# ------------------------------------------------------------------ messages

func _on_message(text: String, kind: String) -> void:
	match kind:
		"pickup":
			var parts := text.split("|")
			_feed_add(int(parts[0]), int(parts[1]))
		"hint":
			toast(text, UiTheme.TEXT)
		"notice":
			toast(text, UiTheme.TEXT, 9.0)
		"save":
			_save_label.text = text
			_save_label.modulate.a = 1.0
			var tw := create_tween()
			tw.tween_interval(1.5)
			tw.tween_property(_save_label, "modulate:a", 0.0, 0.8)
		_:
			toast(text, UiTheme.TEXT)


func toast(text: String, color := UiTheme.TEXT, hold := 2.8) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if text == _last_hint and now - _last_hint_time < 2.5:
		return
	_last_hint = text
	_last_hint_time = now
	while _toasts.get_child_count() >= 3:
		var old := _toasts.get_child(0)
		_toasts.remove_child(old)
		old.queue_free()
	var p := _chip(0.8, 12)
	p.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	p.add_child(UiTheme.label(text, 17, color))
	_toasts.add_child(p)
	p.modulate.a = 0.0
	var tw := p.create_tween()
	tw.tween_property(p, "modulate:a", 1.0, 0.15)
	tw.tween_interval(hold)
	tw.tween_property(p, "modulate:a", 0.0, 0.5)
	tw.tween_callback(p.queue_free)


func _feed_add(mat: int, units: int) -> void:
	var def := GameData.materials[mat]
	var now := Time.get_ticks_msec() / 1000.0
	if _feed_entries.has(mat) and is_instance_valid(_feed_entries[mat]["row"]) and now - float(_feed_entries[mat]["time"]) < 2.2:
		var e: Dictionary = _feed_entries[mat]
		e["units"] = int(e["units"]) + units
		e["time"] = now
		(e["label"] as Label).text = "+%d  %s" % [e["units"], def["name"]]
		(e["row"] as Control).modulate.a = 1.0
		return
	if _feed.get_child_count() >= 6:
		var old := _feed.get_child(0)
		_feed.remove_child(old)
		old.queue_free()
	var row := _hbox(8)
	row.alignment = BoxContainer.ALIGNMENT_END
	var valuable := str(def["category"]) not in ["soil", "rock"]
	var l := UiTheme.hud_label("+%d  %s" % [units, def["name"]], 16, UiTheme.TEXT if valuable else UiTheme.DIM)
	row.add_child(l)
	var swatch := Panel.new()
	swatch.custom_minimum_size = Vector2(10, 10)
	swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	swatch.add_theme_stylebox_override("panel", UiTheme.box(def["color_c"], 2, 0, UiTheme.LINE, 0, 0))
	row.add_child(swatch)
	_feed.add_child(row)
	_feed_entries[mat] = {"row": row, "label": l, "units": units, "time": now}


## The card for a discovery: what it is, what it is called, what it gave you.
func show_discovery(id: String) -> void:
	var d := GameData.discovery(id)
	if d.is_empty():
		return
	for c in _discovery.get_children():
		c.queue_free()
	var v := _vbox(6)
	_discovery.add_child(v)
	var kind := str(d.get("kind", "artifact"))
	var head := UiTheme.caps(str({"artifact": "Artifact recovered", "place": "Place discovered", "core": "Planet heart awakened"}.get(kind, "Discovery")), 14, UiTheme.ACCENT)
	v.add_child(head)
	var title := UiTheme.label(str(d["name"]), 30, UiTheme.TEXT, true)
	v.add_child(title)
	var desc := UiTheme.label(str(d["desc"]), 17, UiTheme.DIM)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(556, 0)
	v.add_child(desc)
	if int(d.get("reward", 0)) > 0 or d.has("unlock_text"):
		v.add_child(UiTheme.divider())
	if int(d.get("reward", 0)) > 0:
		v.add_child(UiTheme.label("+%s credits" % GameData.format_money(int(d["reward"])), 18, UiTheme.GOOD, true))
	if d.has("unlock_text"):
		var u := UiTheme.label(str(d["unlock_text"]), 17, UiTheme.INFO)
		u.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		u.custom_minimum_size = Vector2(556, 0)
		v.add_child(u)
	_discovery.visible = true
	_discovery.modulate.a = 0.0
	_discovery.position.y = -24.0
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_discovery, "modulate:a", 1.0, 0.3)
	tw.tween_property(_discovery, "position:y", 0.0, 0.4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
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

	# backpack nudge when full
	if _pack_shake > 0.0:
		_pack_shake = maxf(0.0, _pack_shake - delta * 2.5)
		_pack_panel.position.x = sin(_pack_shake * 40.0) * 4.0 * _pack_shake

	var player := world.player
	var d := player.depth
	_depth_label.text = "Depth %d m" % int(round(d)) if d > 1.0 else ""
	# terrain still streaming in under the player (after a relay jump, or outrunning the loader)
	_ground_wait = _ground_wait + delta if player.waiting_for_ground else 0.0
	if _ground_wait > 0.3:
		_depth_label.text = "Surveying ground..."
	_compass.visible = bool(Settings.get_value("compass"))
	if _compass.visible:
		# Redraw only when the view turned or the player moved noticeably (or every 0.5 s, for
		# markers that come and go); the strip was redrawn every frame before (~0.1 ms).
		var p := player.global_position
		var key := Vector4(world.nav.heading(), p.x, p.y, p.z)
		_compass_age += delta
		if _compass_age > 0.5 or absf(key.x - _compass_key.x) > 0.002 or Vector3(key.y, key.z, key.w).distance_to(Vector3(_compass_key.y, _compass_key.z, _compass_key.w)) > 0.5:
			_compass_key = key
			_compass_age = 0.0
			_compass.queue_redraw()
	var jets := int(GameState.gear_value("jets"))
	_jet_bar.visible = jets >= 2
	_jet_bar.value = player.jet_fuel
	if GameState.gear_level("scanner") > 0 and world.scanner != null:
		var cd: float = world.scanner.get("cooldown")
		_scan_label.text = "Q  Scan ready" if cd <= 0.0 else "Scanner %.1f s" % cd
		_scan_label.modulate.a = 1.0 if cd <= 0.0 else 0.55
	else:
		_scan_label.text = ""
	_update_base_bearing()

	# crosshair: cooldown arc for anything slower than a quick swing
	var tools := world.tools
	_crosshair.cooldown = 1.0 - tools.cooldown_ratio() if (tools != null and tools.cooldown_total > 0.3 and tools.cooldown > 0.0) else 1.0

	# feed fade
	var now := Time.get_ticks_msec() / 1000.0
	for mat: int in _feed_entries.keys():
		var e: Dictionary = _feed_entries[mat]
		if not is_instance_valid(e["row"]):
			_feed_entries.erase(mat)
			continue
		var age := now - float(e["time"])
		if age > 2.2:
			(e["row"] as Control).modulate.a = clampf(1.0 - (age - 2.2) / 0.6, 0.0, 1.0)
			if age > 2.9:
				(e["row"] as Control).queue_free()
				_feed_entries.erase(mat)

	_update_interaction()
	_crosshair.interact = _interact_target != null
	_crosshair.visible = not player.controls_locked

	if _debug.visible:
		_debug_timer -= delta
		if _debug_timer <= 0.0:
			_debug_timer = 0.25
			_update_debug()


## Small arrow and distance back to the outpost, so nobody gets lost on the far side.
func _update_base_bearing() -> void:
	var player := world.player
	var base_pos: Vector3 = world.planet.geology.spawn_position()
	var to := base_pos - player.global_position
	var dist := to.length()
	_base_row.visible = dist > 14.0
	if not _base_row.visible:
		return
	var up := player.up
	var flat := to - up * to.dot(up)
	var fwd := -player.camera.global_basis.z
	fwd = fwd - up * fwd.dot(up)
	if flat.length() > 0.01 and fwd.length() > 0.01:
		_base_arrow.angle = -fwd.normalized().signed_angle_to(flat.normalized(), up)
	_base_label.text = "Base %d m" % int(round(dist))


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
	lines.append("FPS %d   frame %.1f ms   %s" % [Engine.get_frames_per_second(), 1000.0 / maxf(Engine.get_frames_per_second(), 1.0), RenderingServer.get_current_rendering_method()])
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
	## 0..1 progress of the current tool cooldown (1 = ready).
	var cooldown := 1.0:
		set(v):
			if absf(v - cooldown) > 0.004:
				cooldown = v
				queue_redraw()

	func _draw() -> void:
		var c := size * 0.5
		var shadow := Color(0.02, 0.03, 0.04, 0.55)
		if interact:
			draw_arc(c, 11.0, 0, TAU, 32, shadow, 4.0, true)
			draw_arc(c, 11.0, 0, TAU, 32, UiTheme.ACCENT, 2.0, true)
		draw_circle(c, 3.2, shadow)
		draw_circle(c, 2.0, Color(1, 1, 1, 0.92))
		if cooldown < 0.995:
			draw_arc(c, 17.0, -PI * 0.5, -PI * 0.5 + TAU, 40, Color(0, 0, 0, 0.3), 3.0, true)
			draw_arc(c, 17.0, -PI * 0.5, -PI * 0.5 + TAU * cooldown, 40, Color(1, 1, 1, 0.85), 2.0, true)
