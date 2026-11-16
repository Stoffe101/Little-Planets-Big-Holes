class_name ShopUi
extends Control
## The Workshop (tools) and Outfitter (gear) screen.
##
## Tools: pick a family on the left, look at any tier on the turntable in the middle, and read
## exactly what the next purchase changes on the right (current -> new, including how much
## ground it moves per second and which materials it starts to break). Attachments are listed
## under the upgrade; hovering one fits it to the preview before you pay for it.
## Gear: a grid of cards with the same "now -> next" language.

signal closed()

## key -> [label, unit, decimals]
const STAT_LABELS := {
	"radius": ["Bite radius", " m", 2], "power": ["Power", "", 0], "cooldown": ["Strikes per second", "", 1],
	"reach": ["Reach", " m", 1], "range": ["Suction range", " m", 0], "cone": ["Suction cone", "°", 0], "pull": ["Pull speed", " m/s", 0],
}
const PANEL_MAX_WIDTH := 1600.0

var tab := "tools"
var _family := "shovel"
var _preview_tier := 1
var _hover_mod := ""
var _planet_id := "pipseed"
var _margin: MarginContainer
var _title: Label
var _money: Label
var _tab_buttons: Dictionary = {}
var _body: Control
var _tools_view: HBoxContainer
var _gear_view: ScrollContainer
var _family_list: VBoxContainer
var _preview: ToolPreview
var _preview_name: Label
var _preview_state: Label
var _preview_desc: Label
var _tier_strip: HBoxContainer
var _detail: VBoxContainer
var _gear_grid: GridContainer
var _notice: Label
var _dirty := false
var _shown_key := ""


func _init() -> void:
	name = "ShopUi"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = UiTheme.theme()
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.04, 0.05, 0.66)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	_margin = MarginContainer.new()
	_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["top", "bottom"]:
		_margin.add_theme_constant_override("margin_" + side, 64)
	add_child(_margin)
	resized.connect(_fit_margins)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.panel_box(UiTheme.PANEL, 10, 0.97, 24))
	_margin.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	panel.add_child(v)

	# ---- header
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	v.add_child(header)
	_title = UiTheme.label("Workshop", 30, UiTheme.TEXT, true)
	_title.custom_minimum_size = Vector2(200, 0)
	header.add_child(_title)
	for t: Array in [["tools", "Tools"], ["gear", "Gear"]]:
		var b := UiTheme.ghost_button(str(t[1]), 18)
		b.custom_minimum_size = Vector2(120, 40)
		b.pressed.connect(func() -> void: open(str(t[0])))
		header.add_child(b)
		_tab_buttons[t[0]] = b
	_notice = UiTheme.label("", 17, UiTheme.GOOD)
	_notice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_notice.modulate.a = 0.0
	header.add_child(_notice)
	header.add_child(UiIcon.make("coin", UiTheme.ACCENT, 24))
	_money = UiTheme.label("0", 26, UiTheme.TEXT, true)
	header.add_child(_money)
	header.add_child(UiTheme.spacer(false, Vector2(12, 0)))
	var close := UiTheme.ghost_button("Close   Esc", 17)
	close.pressed.connect(close_shop)
	header.add_child(close)
	v.add_child(UiTheme.divider())

	_body = Control.new()
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_body)
	_build_tools_view()
	_build_gear_view()

	GameState.money_changed.connect(func(_a: int, _d: int) -> void: _queue_rebuild())
	GameState.tools_changed.connect(_queue_rebuild)
	GameState.gear_changed.connect(func(_id: String) -> void: _queue_rebuild())


func _fit_margins() -> void:
	var side := maxf(48.0, (size.x - PANEL_MAX_WIDTH) * 0.5)
	_margin.add_theme_constant_override("margin_left", int(side))
	_margin.add_theme_constant_override("margin_right", int(side))


func _build_tools_view() -> void:
	_tools_view = HBoxContainer.new()
	_tools_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tools_view.add_theme_constant_override("separation", 18)
	_body.add_child(_tools_view)
	# left: families
	_family_list = VBoxContainer.new()
	_family_list.custom_minimum_size = Vector2(290, 0)
	_family_list.add_theme_constant_override("separation", 8)
	_tools_view.add_child(_family_list)
	# centre: preview
	var centre := PanelContainer.new()
	centre.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	centre.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.PANEL_DARK, UiTheme.RADIUS, 1, UiTheme.LINE, 0, 18))
	_tools_view.add_child(centre)
	_preview = ToolPreview.new()
	centre.add_child(_preview)
	var overlay := VBoxContainer.new()
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_theme_constant_override("separation", 2)
	centre.add_child(overlay)
	_preview_state = UiTheme.caps("", 13, UiTheme.ACCENT)
	overlay.add_child(_preview_state)
	_preview_name = UiTheme.label("", 32, UiTheme.TEXT, true)
	overlay.add_child(_preview_name)
	_preview_desc = UiTheme.label("", 17, UiTheme.DIM)
	_preview_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_preview_desc.custom_minimum_size = Vector2(420, 0)
	_preview_desc.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	overlay.add_child(_preview_desc)
	overlay.add_child(UiTheme.spacer())
	_tier_strip = HBoxContainer.new()
	_tier_strip.add_theme_constant_override("separation", 8)
	_tier_strip.alignment = BoxContainer.ALIGNMENT_CENTER
	overlay.add_child(_tier_strip)
	# right: details
	var right := ScrollContainer.new()
	right.custom_minimum_size = Vector2(470, 0)
	right.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tools_view.add_child(right)
	_detail = VBoxContainer.new()
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail.add_theme_constant_override("separation", 12)
	right.add_child(_detail)


func _build_gear_view() -> void:
	_gear_view = ScrollContainer.new()
	_gear_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_gear_view.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_body.add_child(_gear_view)
	_gear_grid = GridContainer.new()
	_gear_grid.columns = 2
	_gear_grid.add_theme_constant_override("h_separation", 12)
	_gear_grid.add_theme_constant_override("v_separation", 12)
	_gear_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_gear_view.add_child(_gear_grid)


# ------------------------------------------------------------------ open / close

func open(which: String) -> void:
	var was_visible := visible
	tab = which
	_planet_id = GameState.current_planet
	visible = true
	_fit_margins()
	if not was_visible:
		Audio.play("ui_open", -10.0)
		# open on the most interesting family: the equipped one
		_family = GameState.equipped if GameState.owns_family(GameState.equipped) else "shovel"
		_preview_tier = _default_tier(_family)
	_rebuild()


func close_shop() -> void:
	if not visible:
		return
	visible = false
	Audio.play("ui_close", -10.0)
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed("pause") or event.is_action_pressed("interact")):
		close_shop()
		get_viewport().set_input_as_handled()


func _queue_rebuild() -> void:
	if not visible or _dirty:
		return
	_dirty = true
	_rebuild.call_deferred()


## The tier the preview should show by default: what you can work towards next.
func _default_tier(fid: String) -> int:
	var count := (GameData.family(fid)["tiers"] as Array).size()
	return clampi(GameState.tier_of(fid) + 1, 1, count)


func _select_family(fid: String) -> void:
	_family = fid
	_preview_tier = _default_tier(fid)
	_hover_mod = ""
	Audio.play("ui_click", -10.0, 1.1, 0.03)
	_rebuild()


# ------------------------------------------------------------------ rebuild

func _clear(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()


func _rebuild() -> void:
	_dirty = false
	_money.text = GameData.format_money(GameState.money)
	_title.text = "Workshop" if tab == "tools" else "Outfitter"
	for key: String in _tab_buttons:
		var b: Button = _tab_buttons[key]
		UiTheme.style_button(b, UiTheme.PANEL_LIGHT if key != tab else Color("#2b3540"), 18)
		b.modulate = Color(1, 1, 1, 1.0 if key == tab else 0.7)
	_tools_view.visible = tab == "tools"
	_gear_view.visible = tab == "gear"
	if tab == "tools":
		_rebuild_families()
		_rebuild_preview()
		_rebuild_detail()
	else:
		_clear(_gear_grid)
		for g in GameData.gear:
			_gear_grid.add_child(_gear_card(g))


func _rebuild_families() -> void:
	_clear(_family_list)
	_family_list.add_child(UiTheme.caps("Equipment", 13, UiTheme.DIM))
	for fam in GameData.tool_families:
		var fid: String = fam["id"]
		var tier := GameState.tier_of(fid)
		var tiers: Array = fam["tiers"]
		var selected := fid == _family
		var b := Button.new()
		b.custom_minimum_size = Vector2(0, 78)
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var bg := Color("#27313b") if selected else UiTheme.PANEL_LIGHT
		var normal := UiTheme.box(bg, UiTheme.RADIUS, 1, UiTheme.ACCENT if selected else UiTheme.LINE, 0, 12)
		if selected:
			normal.border_width_left = 3
		b.add_theme_stylebox_override("normal", normal)
		b.add_theme_stylebox_override("hover", UiTheme.box(bg.lightened(0.05), UiTheme.RADIUS, 1, UiTheme.ACCENT if selected else Color(1, 1, 1, 0.2), 0, 12))
		b.add_theme_stylebox_override("pressed", normal)
		b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		b.pressed.connect(func() -> void: _select_family(fid))
		var h := HBoxContainer.new()
		h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 12)
		h.add_theme_constant_override("separation", 12)
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(h)
		h.add_child(UiIcon.make(fid, UiTheme.TEXT if tier > 0 else UiTheme.FAINT, 36))
		var tv := VBoxContainer.new()
		tv.add_theme_constant_override("separation", 2)
		tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tv.alignment = BoxContainer.ALIGNMENT_CENTER
		tv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(tv)
		tv.add_child(UiTheme.label(str(fam["name"]), 19, UiTheme.TEXT, true))
		tv.add_child(UiTheme.label(str(tiers[tier - 1]["name"]) if tier > 0 else "Not owned", 15, UiTheme.DIM if tier > 0 else UiTheme.FAINT))
		tv.add_child(UiTheme.pips(tiers.size(), tier, UiTheme.ACCENT, Vector2(22, 4)))
		var key := UiTheme.label(str(int(fam["slot"])), 14, UiTheme.FAINT)
		key.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		h.add_child(key)
		_family_list.add_child(b)
	_family_list.add_child(UiTheme.spacer())
	var tip := UiTheme.label("Tip: click a tier under the preview to inspect any model before you buy it.", 14, UiTheme.FAINT)
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_family_list.add_child(tip)


func _mods_for_preview(fid: String) -> Dictionary:
	var mods := {}
	for m: Dictionary in GameData.family(fid).get("mods", []):
		var lvl := GameState.mod_level(fid, m["id"])
		if str(m["id"]) == _hover_mod:
			lvl = mini(lvl + 1, int(m["max"]))
		mods[m["id"]] = lvl
	return mods


func _rebuild_preview() -> void:
	var fam := GameData.family(_family)
	var tiers: Array = fam["tiers"]
	var owned := GameState.tier_of(_family)
	_preview_tier = clampi(_preview_tier, 1, tiers.size())
	var def: Dictionary = tiers[_preview_tier - 1]
	var key := "%s/%d" % [_family, _preview_tier]
	_preview.show_tool(_family, _preview_tier, _mods_for_preview(_family), key != _shown_key)
	_shown_key = key
	_preview_name.text = str(def["name"])
	_preview_desc.text = str(def["desc"])
	var state := "Tier %d of %d" % [_preview_tier, tiers.size()]
	if _preview_tier == owned:
		state += "   ·   Equipped model" if GameState.equipped == _family else "   ·   Owned"
		_preview_state.add_theme_color_override("font_color", UiTheme.GOOD)
	elif _preview_tier < owned:
		state += "   ·   Replaced"
		_preview_state.add_theme_color_override("font_color", UiTheme.DIM)
	elif _preview_tier == owned + 1:
		state += "   ·   Next upgrade"
		_preview_state.add_theme_color_override("font_color", UiTheme.ACCENT)
	else:
		state += "   ·   Future upgrade"
		_preview_state.add_theme_color_override("font_color", UiTheme.DIM)
	_preview_state.text = state.to_upper()
	_clear(_tier_strip)
	for i in tiers.size():
		var t := i + 1
		var b := UiTheme.button(str(tiers[i]["name"]), UiTheme.PANEL_LIGHT, 15)
		b.custom_minimum_size = Vector2(0, 34)
		if t == _preview_tier:
			UiTheme.style_button(b, Color("#2b3540"), 15)
			(b.get_theme_stylebox("normal") as StyleBoxFlat).border_color = UiTheme.ACCENT
		b.modulate = Color(1, 1, 1, 1.0 if t <= owned + 1 else 0.6)
		b.pressed.connect(func() -> void:
			_preview_tier = t
			_rebuild_preview())
		_tier_strip.add_child(b)


## Volume of ground removed per second: the one number that says how strong a digger is.
static func dig_rate(stats: Dictionary, behavior: String) -> float:
	var r := float(stats.get("radius", 0.0))
	var cd := float(stats.get("cooldown", 0.0))
	if r <= 0.0 or cd <= 0.0 or behavior == "vacuum":
		return 0.0
	var volume := 4.0 / 3.0 * PI * r * r * r
	if behavior == "swing" and int(stats.get("trench", 0)) == 1:
		volume = PI * r * r * 0.81 * (r * 2.3) + volume * 0.73
	return volume / cd


func _rebuild_detail() -> void:
	_clear(_detail)
	var fam := GameData.family(_family)
	var fid := _family
	var tier := GameState.tier_of(fid)
	var behavior := str(fam.get("behavior", "swing"))
	var next := GameState.next_tier_def(fid)

	# ---- upgrade card
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UiTheme.card_box(UiTheme.PANEL_LIGHT, 16))
	_detail.add_child(card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	card.add_child(v)
	if next.is_empty():
		v.add_child(UiTheme.caps("Fully upgraded", 13, UiTheme.GOOD))
		v.add_child(UiTheme.label(str(GameState.current_tier_def(fid).get("name", "")), 24, UiTheme.TEXT, true))
		for line in _stat_rows(GameState.tool_stats(fid), GameState.tool_stats(fid), behavior, true):
			v.add_child(line)
	else:
		v.add_child(UiTheme.caps("New tool" if tier == 0 else "Next upgrade", 13, UiTheme.ACCENT))
		v.add_child(UiTheme.label(str(next["name"]), 24, UiTheme.TEXT, true))
		var cur_stats := GameState.tool_stats(fid)
		var next_stats := GameState.tool_stats_for(fid, tier + 1)
		for line in _stat_rows(cur_stats, next_stats, behavior, tier == 0):
			v.add_child(line)
		var breaks := _breakable_names(int(next_stats.get("power", 0)), int(cur_stats.get("power", 0)))
		if breaks != "":
			var bl := UiTheme.label("Now breaks: " + breaks, 16, UiTheme.INFO)
			bl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			v.add_child(bl)
		if int(next_stats.get("auto", 0)) == 1 and int(cur_stats.get("auto", 0)) == 0 and tier > 0:
			v.add_child(UiTheme.label("Powered: hold the trigger and it keeps digging.", 16, UiTheme.INFO))
		v.add_child(UiTheme.divider())
		var reason := "" if GameState.requirement_met(next.get("requires")) else GameState.requirement_text(next.get("requires"))
		var buy_tier := func() -> bool:
			var ok := GameState.buy_next_tier(fid)
			if ok:
				_preview_tier = GameState.tier_of(fid)
				_celebrate("%s acquired" % str(next["name"]))
			return ok
		v.add_child(_buy_row(int(next["cost"]), reason, false, buy_tier, true))

	# ---- attachments
	if tier > 0 and not (fam.get("mods", []) as Array).is_empty():
		_detail.add_child(UiTheme.caps("Attachments  ·  fit every %s" % str(fam["name"]).to_lower(), 13, UiTheme.DIM))
		for m: Dictionary in fam.get("mods", []):
			_detail.add_child(_mod_row(fid, m))
	elif tier == 0:
		var l := UiTheme.label("Attachments become available once you own this tool.", 15, UiTheme.FAINT)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_detail.add_child(l)


func _celebrate(text: String) -> void:
	_preview.celebrate()
	_notice.text = text
	_notice.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_interval(1.6)
	tw.tween_property(_notice, "modulate:a", 0.0, 0.6)


func _stat_row(label: String, a_text: String, b_text: String, better: bool, changed: bool) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	var l := UiTheme.label(label, 17, UiTheme.DIM)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	if a_text != "" and changed:
		h.add_child(UiTheme.label(a_text, 17, UiTheme.DIM))
		h.add_child(UiTheme.label("→", 17, UiTheme.FAINT))
	h.add_child(UiTheme.label(b_text, 17, (UiTheme.GOOD if better else UiTheme.TEXT) if changed else UiTheme.TEXT, changed))
	return h


func _stat_rows(cur: Dictionary, next: Dictionary, behavior: String, absolute: bool) -> Array[Control]:
	var out: Array[Control] = []
	var rate_a := dig_rate(cur, behavior)
	var rate_b := dig_rate(next, behavior)
	if rate_b > 0.0:
		var label := "Crater volume" if behavior == "cannon" else "Ground moved per second"
		var unit := " m³" if behavior == "cannon" else " m³/s"
		var va := rate_a * (float(cur.get("cooldown", 1.0)) if behavior == "cannon" else 1.0)
		var vb := rate_b * (float(next.get("cooldown", 1.0)) if behavior == "cannon" else 1.0)
		out.append(_stat_row(label, "" if absolute else "%.1f%s" % [va, unit], "%.1f%s" % [vb, unit], vb > va, not absolute and not is_equal_approx(va, vb) or absolute))
	for key: String in STAT_LABELS:
		if not next.has(key) or float(next[key]) == 0.0:
			continue
		var info: Array = STAT_LABELS[key]
		var a := float(cur.get(key, 0.0))
		var b := float(next[key])
		if key == "cooldown":
			a = 1.0 / a if a > 0.0 else 0.0
			b = 1.0 / b
			if b > 20.0:
				continue
		var same := is_equal_approx(a, b)
		if same and not absolute:
			continue
		var fmt := "%." + str(int(info[2])) + "f"
		out.append(_stat_row(str(info[0]), "" if (absolute or a == 0.0) else (fmt % a) + str(info[1]), (fmt % b) + str(info[1]), b > a, not same or absolute))
	return out


## Names of materials on the current planet that the new power level unlocks.
func _breakable_names(new_power: int, old_power: int) -> String:
	var cfg := GameData.planet(_planet_id)
	var ids: Array[String] = []
	for l: Dictionary in cfg.get("layers", []):
		ids.append(str(l["material"]))
	for o: Dictionary in cfg.get("ores", []):
		ids.append(str(o["material"]))
	var names: Array[String] = []
	for id in ids:
		var h := int(GameData.material(id)["hardness"])
		if h <= new_power and h > old_power:
			names.append(str(GameData.material(id)["name"]))
	return ", ".join(names)


## Price + action. `wide` makes the button fill the row (used for the main tier purchase).
func _buy_row(cost: int, locked_reason: String, maxed: bool, on_buy: Callable, wide := false) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	h.alignment = BoxContainer.ALIGNMENT_END
	if maxed:
		h.add_child(UiIcon.make("check", UiTheme.GOOD, 20))
		h.add_child(UiTheme.caps("Complete", 13, UiTheme.GOOD))
		return h
	if locked_reason != "":
		h.add_child(UiIcon.make("lock", UiTheme.FAINT, 20))
		var why := UiTheme.label(locked_reason, 15, UiTheme.DIM)
		why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		why.custom_minimum_size = Vector2(180, 0)
		why.size_flags_horizontal = Control.SIZE_EXPAND_FILL if wide else Control.SIZE_FILL
		h.add_child(why)
		return h
	var affordable := GameState.can_afford(cost)
	if not affordable:
		var need := UiTheme.label("%s short" % GameData.format_money(cost - GameState.money), 15, UiTheme.BAD)
		need.size_flags_horizontal = Control.SIZE_EXPAND_FILL if wide else Control.SIZE_FILL
		need.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		h.add_child(need)
	var b := UiTheme.button("Buy   %s" % GameData.format_money(cost), UiTheme.ACCENT if affordable else UiTheme.PANEL_LIGHT, 18 if wide else 16)
	b.custom_minimum_size = Vector2(150 if not wide else 220, 44 if wide else 36)
	if wide and affordable:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.disabled = not affordable
	b.pressed.connect(func() -> void:
		if on_buy.call():
			Audio.play("ui_buy", -4.0)
		else:
			Audio.play("ui_error", -8.0))
	h.add_child(b)
	return h


func _mod_row(fid: String, m: Dictionary) -> Control:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UiTheme.card_box(UiTheme.PANEL_LIGHT, 12))
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	var mid: String = m["id"]
	card.mouse_entered.connect(func() -> void:
		if _hover_mod != mid:
			_hover_mod = mid
			_rebuild_preview())
	card.mouse_exited.connect(func() -> void:
		if _hover_mod == mid:
			_hover_mod = ""
			_rebuild_preview())
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	card.add_child(h)
	var lvl := GameState.mod_level(fid, mid)
	var max_lvl := int(m["max"])
	h.add_child(UiIcon.make(str(m.get("icon", "star")), UiTheme.INFO if lvl > 0 else UiTheme.DIM, 26))
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 2)
	h.add_child(v)
	var th := HBoxContainer.new()
	th.add_theme_constant_override("separation", 8)
	v.add_child(th)
	th.add_child(UiTheme.label(str(m["name"]), 17, UiTheme.TEXT, true))
	th.add_child(UiTheme.pips(max_lvl, lvl, UiTheme.INFO, Vector2(14, 4)))
	var labels: Array = m.get("labels", [])
	var effect := str(labels[mini(lvl, labels.size() - 1)]) if not labels.is_empty() else str(m["desc"])
	var d := UiTheme.label(str(m["desc"]) if lvl >= max_lvl else effect, 15, UiTheme.DIM)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.tooltip_text = str(m["desc"])
	v.add_child(d)
	var reason := "" if GameState.requirement_met(m.get("requires")) else GameState.requirement_text(m.get("requires"))
	h.add_child(_buy_row(GameState.mod_cost(fid, mid), reason, lvl >= max_lvl, func() -> bool:
		var ok := GameState.buy_mod(fid, mid)
		if ok:
			_preview_tier = GameState.tier_of(fid)
			_celebrate("%s fitted" % str(m["name"]))
		return ok))
	return card


func _gear_card(g: Dictionary) -> Control:
	var gid: String = g["id"]
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UiTheme.card_box(UiTheme.PANEL_LIGHT, 16))
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	card.add_child(h)
	var lvl := GameState.gear_level(gid)
	var max_lvl := GameState.gear_max_level(gid)
	h.add_child(UiIcon.make(str(g.get("icon", "star")), UiTheme.TEXT if lvl > 0 else UiTheme.DIM, 40))
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 3)
	h.add_child(v)
	var names: Array = g.get("level_names", [])
	var th := HBoxContainer.new()
	th.add_theme_constant_override("separation", 10)
	v.add_child(th)
	th.add_child(UiTheme.label(str(g["name"]), 20, UiTheme.TEXT, true))
	th.add_child(UiTheme.pips(max_lvl, lvl, UiTheme.INFO, Vector2(16, 4)))
	var cur_name := str(names[lvl]) if lvl < names.size() else ""
	var line := cur_name
	if lvl < max_lvl:
		line += "   →   %s" % str(names[lvl + 1])
	v.add_child(UiTheme.label(line, 16, UiTheme.ACCENT))
	var values: Array = g["values"]
	var unit := str(g.get("unit", ""))
	if lvl < max_lvl and unit != "":
		var a: Variant = values[lvl]
		var b: Variant = values[lvl + 1]
		var vh := HBoxContainer.new()
		vh.add_theme_constant_override("separation", 8)
		vh.add_child(UiTheme.label("%s%s" % [str(a), unit], 16, UiTheme.DIM))
		vh.add_child(UiTheme.label("→", 16, UiTheme.FAINT))
		vh.add_child(UiTheme.label("%s%s" % [str(b), unit], 16, UiTheme.GOOD, true))
		v.add_child(vh)
	var d := UiTheme.label(str(g["desc"]), 15, UiTheme.DIM)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(d)
	var reason := "" if GameState.requirement_met(g.get("requires")) else GameState.requirement_text(g.get("requires"))
	var buy := _buy_row(GameState.gear_cost(gid), reason, lvl >= max_lvl, func() -> bool:
		var ok := GameState.buy_gear(gid)
		if ok:
			_celebrate("%s upgraded" % str(g["name"]))
		return ok)
	buy.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(buy)
	return card
