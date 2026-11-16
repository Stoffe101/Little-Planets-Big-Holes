class_name PlanetSelectUi
extends UiScreen
## The rocket's navigation console: lists every planet, what it takes to unlock it, and lets
## the player fly there.

signal travel_requested(planet_id: String)


func _init() -> void:
	name = "PlanetSelectUi"
	build("ROCKET - WHERE TO?", 330, 130, UiTheme.SKY)


func refresh() -> void:
	clear_content()
	for pid in GameData.planet_order:
		content.add_child(_planet_card(pid))
	var note := UiTheme.label("Your holes stay exactly as you left them on every planet.", 20, UiTheme.MUTED)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(note)


func _planet_card(pid: String) -> Control:
	var cfg := GameData.planet(pid)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.PANEL_LIGHT, 18, 3, UiTheme.INK, 0, 18))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 18)
	card.add_child(h)
	var grass: Array = (cfg.get("palette", {}) as Dictionary).get("grass", ["#7fdc5a"])
	h.add_child(UiIcon.make("planet", Color(str(grass[0])), 96))
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 2)
	h.add_child(v)
	var unlocked := GameState.planet_unlocked_now(pid)
	var visited := GameState.visited.has(pid)
	v.add_child(UiTheme.label(str(cfg["name"]) if (unlocked or visited) else "? ? ?", 34, UiTheme.CREAM, true))
	var tag := UiTheme.label(str(cfg.get("tagline", "")) if unlocked else str(cfg.get("unlock_hint", "Locked")), 21, UiTheme.MUTED if unlocked else UiTheme.YELLOW)
	tag.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(tag)
	var total := 0
	for d in GameData.discoveries:
		if d.get("planet", "") == pid:
			total += 1
	v.add_child(UiTheme.label("Gravity %s   |   Discoveries %d / %d" % ["low" if float(cfg.get("gravity", 17)) < 12.0 else "normal", GameState.discovery_count(pid), total], 20, UiTheme.TEAL, true))
	var right := VBoxContainer.new()
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	right.custom_minimum_size = Vector2(240, 0)
	h.add_child(right)
	if pid == GameState.current_planet:
		var here := UiTheme.label("YOU ARE HERE", 24, UiTheme.GREEN, true)
		here.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		right.add_child(here)
	elif not unlocked:
		var lh := HBoxContainer.new()
		lh.alignment = BoxContainer.ALIGNMENT_CENTER
		lh.add_child(UiIcon.make("lock", UiTheme.YELLOW, 40))
		lh.add_child(UiTheme.label("LOCKED", 24, UiTheme.MUTED, true))
		right.add_child(lh)
	else:
		var cost := 0 if visited else int(cfg.get("travel_cost", 0))
		var ok := GameState.money >= cost
		var b := UiTheme.button("FLY!" if cost == 0 else "FLY  %s" % GameData.format_money(cost), UiTheme.GREEN if ok else Color(0.5, 0.48, 0.64), 30)
		b.disabled = not ok
		b.pressed.connect(func() -> void: travel_requested.emit(pid))
		right.add_child(b)
		if cost > 0:
			var l := UiTheme.label("First trip fuel" if ok else "Need %s more" % GameData.format_money(cost - GameState.money), 18, UiTheme.MUTED)
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			right.add_child(l)
	return card
