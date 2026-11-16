class_name PlanetSelectUi
extends UiScreen
## The lander's navigation console: lists every planet, what it takes to unlock it, and lets
## the player fly there.

signal travel_requested(planet_id: String)


func _init() -> void:
	name = "PlanetSelectUi"
	build("Lander  ·  Destinations", 330, 150)


func refresh() -> void:
	clear_content()
	for pid in GameData.planet_order:
		content.add_child(_planet_card(pid))
	content.add_child(UiTheme.spacer())
	var note := UiTheme.label("Every hole you dig stays exactly as you left it, on every planet.", 15, UiTheme.FAINT)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(note)


func _planet_card(pid: String) -> Control:
	var cfg := GameData.planet(pid)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UiTheme.card_box(UiTheme.PANEL_LIGHT, 18))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 18)
	card.add_child(h)
	var from_space: Array = (cfg.get("palette", {}) as Dictionary).get("from_space", ["#8c96a3"])
	var unlocked := GameState.planet_unlocked_now(pid)
	var visited := GameState.visited.has(pid)
	h.add_child(UiIcon.make("planet", Color(str(from_space[0])) if (unlocked or visited) else UiTheme.FAINT, 64))
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 3)
	h.add_child(v)
	v.add_child(UiTheme.label(str(cfg["name"]) if (unlocked or visited) else "Uncharted", 26, UiTheme.TEXT, true))
	var tag := UiTheme.label(str(cfg.get("tagline", "")) if unlocked else str(cfg.get("unlock_hint", "Locked")), 16, UiTheme.DIM if unlocked else UiTheme.ACCENT)
	tag.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(tag)
	var total := 0
	for d in GameData.discoveries:
		if d.get("planet", "") == pid:
			total += 1
	v.add_child(UiTheme.caps("Gravity %s     Discoveries %d / %d" % ["low" if float(cfg.get("gravity", 17)) < 12.0 else "normal", GameState.discovery_count(pid), total], 13, UiTheme.INFO))
	var right := VBoxContainer.new()
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	right.custom_minimum_size = Vector2(220, 0)
	h.add_child(right)
	if pid == GameState.current_planet:
		var here := UiTheme.caps("You are here", 14, UiTheme.GOOD)
		here.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		right.add_child(here)
	elif not unlocked:
		var lh := HBoxContainer.new()
		lh.alignment = BoxContainer.ALIGNMENT_CENTER
		lh.add_theme_constant_override("separation", 8)
		lh.add_child(UiIcon.make("lock", UiTheme.FAINT, 22))
		lh.add_child(UiTheme.caps("Locked", 14, UiTheme.DIM))
		right.add_child(lh)
	else:
		var cost := 0 if visited else int(cfg.get("travel_cost", 0))
		var ok := GameState.money >= cost
		var b := UiTheme.button("Launch" if cost == 0 else "Launch   %s" % GameData.format_money(cost), UiTheme.ACCENT if ok else UiTheme.PANEL_LIGHT, 19)
		b.custom_minimum_size = Vector2(0, 46)
		b.disabled = not ok
		b.pressed.connect(func() -> void: travel_requested.emit(pid))
		right.add_child(b)
		if cost > 0:
			var l := UiTheme.label("First trip fuel" if ok else "%s short" % GameData.format_money(cost - GameState.money), 14, UiTheme.DIM if ok else UiTheme.BAD)
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			right.add_child(l)
	return card
