class_name ShopUi
extends Control
## The Tool Shop / Gear Shop screen. Every card states exactly what you own, what the next
## purchase changes (old value -> new value), what it costs, and - if locked - why.

signal closed()

const STAT_LABELS := {
	"radius": ["Bite size", " m", 2], "power": ["Power", "", 0], "cooldown": ["Digs per second", "", 1],
	"reach": ["Reach", " m", 1], "range": ["Suction range", " m", 0], "cone": ["Suction cone", "°", 0], "pull": ["Pull speed", " m/s", 0],
}

var tab := "tools"
var _body: VBoxContainer
var _scroll: ScrollContainer
var _money: Label
var _tab_buttons: Dictionary = {}
var _title: Label
var _planet_id := "pipseed"


func _init() -> void:
	name = "ShopUi"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = UiTheme.theme()
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0.06, 0.04, 0.14, 0.62)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 150)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 70)
	add_child(margin)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.panel_box(UiTheme.PANEL, 28, 0.98))
	margin.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	panel.add_child(v)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 14)
	v.add_child(header)
	_title = UiTheme.label("SHOP", 44, UiTheme.YELLOW, true)
	header.add_child(_title)
	for t: Array in [["tools", "Tools", UiTheme.ORANGE], ["gear", "Gear", UiTheme.TEAL]]:
		var b := UiTheme.button(str(t[1]), t[2], 26)
		b.custom_minimum_size = Vector2(150, 0)
		b.pressed.connect(func() -> void: open(str(t[0])))
		header.add_child(b)
		_tab_buttons[t[0]] = b
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(sp)
	header.add_child(UiIcon.make("coin", UiTheme.YELLOW, 44))
	_money = UiTheme.label("0", 40, UiTheme.CREAM, true)
	header.add_child(_money)
	var close := UiTheme.button("Close  [Esc]", UiTheme.PINK, 24)
	close.pressed.connect(close_shop)
	header.add_child(close)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(_scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 14)
	_scroll.add_child(_body)

	GameState.money_changed.connect(func(_a: int, _d: int) -> void:
		if visible:
			_rebuild())


func open(which: String) -> void:
	tab = which
	_planet_id = GameState.current_planet
	visible = true
	Audio.play("ui_open", -8.0)
	_rebuild()


func close_shop() -> void:
	if not visible:
		return
	visible = false
	Audio.play("ui_close", -8.0)
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed("pause") or event.is_action_pressed("interact")):
		close_shop()
		get_viewport().set_input_as_handled()


# ------------------------------------------------------------------ content

func _rebuild() -> void:
	var scroll_pos := _scroll.scroll_vertical
	for c in _body.get_children():
		_body.remove_child(c)
		c.queue_free()
	_money.text = GameData.format_money(GameState.money)
	_title.text = "TOOL SHOP" if tab == "tools" else "GEAR SHOP"
	for key: String in _tab_buttons:
		(_tab_buttons[key] as Button).modulate = Color(1, 1, 1, 1.0 if key == tab else 0.55)
	if tab == "tools":
		for fam in GameData.tool_families:
			_body.add_child(_family_section(fam))
	else:
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 14)
		grid.add_theme_constant_override("v_separation", 14)
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_body.add_child(grid)
		for g in GameData.gear:
			grid.add_child(_gear_card(g))
	await get_tree().process_frame
	if is_instance_valid(_scroll):
		_scroll.scroll_vertical = scroll_pos


func _card(color := UiTheme.PANEL_LIGHT) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiTheme.box(color, 18, 3, UiTheme.INK, 0, 16))
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return p


func _buy_button(cost: int, locked_reason: String, maxed: bool, on_buy: Callable) -> Control:
	if maxed:
		var l := UiTheme.label("MAXED", 24, UiTheme.TEAL, true)
		l.custom_minimum_size = Vector2(190, 0)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		return l
	if locked_reason != "":
		var box := VBoxContainer.new()
		box.custom_minimum_size = Vector2(230, 0)
		var h := HBoxContainer.new()
		h.alignment = BoxContainer.ALIGNMENT_CENTER
		h.add_child(UiIcon.make("lock", UiTheme.YELLOW, 34))
		h.add_child(UiTheme.label("LOCKED", 22, UiTheme.MUTED, true))
		box.add_child(h)
		var why := UiTheme.label(locked_reason, 18, UiTheme.YELLOW)
		why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		why.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		why.custom_minimum_size = Vector2(230, 0)
		box.add_child(why)
		return box
	var affordable := GameState.can_afford(cost)
	var box2 := VBoxContainer.new()
	box2.custom_minimum_size = Vector2(190, 0)
	box2.alignment = BoxContainer.ALIGNMENT_CENTER
	var b := UiTheme.button("%s" % GameData.format_money(cost), UiTheme.GREEN if affordable else Color(0.5, 0.48, 0.64), 28)
	b.icon = null
	b.text = "BUY  %s" % GameData.format_money(cost) if affordable else GameData.format_money(cost)
	b.disabled = not affordable
	b.pressed.connect(func() -> void:
		if on_buy.call():
			Audio.play("ui_buy", -2.0)
		else:
			Audio.play("ui_error", -6.0))
	box2.add_child(b)
	if not affordable:
		var need := UiTheme.label("Need %s more" % GameData.format_money(cost - GameState.money), 18, UiTheme.MUTED)
		need.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box2.add_child(need)
	return box2


func _family_section(fam: Dictionary) -> Control:
	var fid: String = fam["id"]
	var color := Color(str(fam["color"]))
	var card := _card(UiTheme.PANEL_DARK)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	card.add_child(v)
	var tier := GameState.tier_of(fid)
	var tiers: Array = fam["tiers"]

	# header: icon, family name, tier pips
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	v.add_child(head)
	head.add_child(UiIcon.make(fid, color, 54))
	var hv := VBoxContainer.new()
	hv.add_theme_constant_override("separation", 0)
	head.add_child(hv)
	hv.add_child(UiTheme.label(str(fam["name"]).to_upper() + "   [%d]" % int(fam["slot"]), 22, color, true))
	hv.add_child(UiTheme.label("You own: %s" % (tiers[tier - 1]["name"] if tier > 0 else "nothing yet"), 26, UiTheme.CREAM, true))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	var pips := HBoxContainer.new()
	pips.add_theme_constant_override("separation", 6)
	for i in tiers.size():
		var pip := Panel.new()
		pip.custom_minimum_size = Vector2(34, 16)
		pip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		pip.add_theme_stylebox_override("panel", UiTheme.box(color if i < tier else Color(0.2, 0.17, 0.36), 7, 3, UiTheme.INK, 0, 0))
		pips.add_child(pip)
	head.add_child(pips)

	# next tier
	var next := GameState.next_tier_def(fid)
	if not next.is_empty():
		var nc := _card(UiTheme.PANEL_LIGHT)
		v.add_child(nc)
		var nh := HBoxContainer.new()
		nh.add_theme_constant_override("separation", 16)
		nc.add_child(nh)
		var nv := VBoxContainer.new()
		nv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nv.add_theme_constant_override("separation", 4)
		nh.add_child(nv)
		nv.add_child(UiTheme.label(("NEW TOOL:  " if tier == 0 else "NEXT:  ") + str(next["name"]), 30, UiTheme.YELLOW, true))
		var desc := UiTheme.label(str(next["desc"]), 21, UiTheme.MUTED)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		nv.add_child(desc)
		var cur_stats := GameState.tool_stats(fid)
		var next_stats := GameState.tool_stats_for(fid, tier + 1)
		var stats_box := HFlowContainer.new()
		stats_box.add_theme_constant_override("h_separation", 22)
		nv.add_child(stats_box)
		for line in _stat_lines(cur_stats, next_stats):
			stats_box.add_child(line)
		var reason := "" if GameState.requirement_met(next.get("requires")) else GameState.requirement_text(next.get("requires"))
		nh.add_child(_buy_button(int(next["cost"]), reason, false, func() -> bool: return GameState.buy_next_tier(fid)))
	else:
		v.add_child(UiTheme.label("Top tier reached. Magnificent.", 22, UiTheme.TEAL, true))

	# mods
	if tier > 0:
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 10)
		grid.add_theme_constant_override("v_separation", 10)
		v.add_child(grid)
		for m: Dictionary in fam.get("mods", []):
			grid.add_child(_mod_card(fid, m))
	return card


func _stat_lines(cur: Dictionary, next: Dictionary) -> Array[Control]:
	var out: Array[Control] = []
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
		if is_equal_approx(a, b) and not cur.is_empty():
			continue
		var fmt := "%." + str(int(info[2])) + "f"
		var text := ""
		if cur.is_empty() or a == 0.0:
			text = "%s  %s%s" % [info[0], fmt % b, info[1]]
		else:
			text = "%s  %s%s → %s%s" % [info[0], fmt % a, info[1], fmt % b, info[1]]
		var l := UiTheme.label(text, 21, UiTheme.GREEN if b > a else UiTheme.CREAM, true)
		out.append(l)
		if key == "power":
			var names := _breakable_names(int(b), int(a))
			if names != "":
				out.append(UiTheme.label("Breaks: " + names, 21, UiTheme.SKY, true))
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


func _mod_card(fid: String, m: Dictionary) -> Control:
	var card := _card(UiTheme.PANEL)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	card.add_child(h)
	var lvl := GameState.mod_level(fid, m["id"])
	var max_lvl := int(m["max"])
	h.add_child(UiIcon.make(str(m.get("icon", "star")), UiTheme.SKY, 40))
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 0)
	h.add_child(v)
	var title := "%s" % m["name"]
	if max_lvl > 1:
		title += "   %d / %d" % [lvl, max_lvl]
	elif lvl >= 1:
		title += "   (installed)"
	v.add_child(UiTheme.label(title, 23, UiTheme.CREAM, true))
	var labels: Array = m.get("labels", [])
	var effect := str(labels[mini(lvl, labels.size() - 1)]) if not labels.is_empty() else str(m["desc"])
	var d := UiTheme.label(str(m["desc"]) if lvl >= max_lvl else "%s  Next: %s" % [m["desc"], effect], 18, UiTheme.MUTED)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(d)
	var reason := "" if GameState.requirement_met(m.get("requires")) else GameState.requirement_text(m.get("requires"))
	h.add_child(_buy_button(GameState.mod_cost(fid, m["id"]), reason, lvl >= max_lvl, func() -> bool: return GameState.buy_mod(fid, m["id"])))
	return card


func _gear_card(g: Dictionary) -> Control:
	var gid: String = g["id"]
	var card := _card(UiTheme.PANEL_LIGHT)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	card.add_child(h)
	h.add_child(UiIcon.make(str(g.get("icon", "star")), UiTheme.PINK, 58))
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 2)
	h.add_child(v)
	var lvl := GameState.gear_level(gid)
	var max_lvl := GameState.gear_max_level(gid)
	var names: Array = g.get("level_names", [])
	v.add_child(UiTheme.label(str(g["name"]), 26, UiTheme.CREAM, true))
	var cur_name := str(names[lvl]) if lvl < names.size() else ""
	var line := "Now: %s" % cur_name
	if lvl < max_lvl:
		line += "   →   %s" % str(names[lvl + 1])
	v.add_child(UiTheme.label(line, 20, UiTheme.YELLOW, true))
	var values: Array = g["values"]
	var unit := str(g.get("unit", ""))
	if lvl < max_lvl and unit != "":
		var a: Variant = values[lvl]
		var b: Variant = values[lvl + 1]
		v.add_child(UiTheme.label("%s%s  →  %s%s" % [str(a), unit, str(b), unit], 21, UiTheme.GREEN, true))
	var d := UiTheme.label(str(g["desc"]), 18, UiTheme.MUTED)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(d)
	var pips := HBoxContainer.new()
	pips.add_theme_constant_override("separation", 5)
	for i in max_lvl:
		var pip := Panel.new()
		pip.custom_minimum_size = Vector2(26, 12)
		pip.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.PINK if i < lvl else Color(0.2, 0.17, 0.36), 5, 2, UiTheme.INK, 0, 0))
		pips.add_child(pip)
	v.add_child(pips)
	var reason := "" if GameState.requirement_met(g.get("requires")) else GameState.requirement_text(g.get("requires"))
	h.add_child(_buy_button(GameState.gear_cost(gid), reason, lvl >= max_lvl, func() -> bool: return GameState.buy_gear(gid)))
	return card
