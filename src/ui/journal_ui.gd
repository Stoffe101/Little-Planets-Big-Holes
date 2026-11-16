class_name JournalUi
extends UiScreen
## Discovery journal (Tab): everything found so far, silhouettes for what is still buried,
## plus lifetime statistics.


func _init() -> void:
	name = "JournalUi"
	build("EXPLORER'S JOURNAL", 220, 80, UiTheme.TEAL)


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("journal"):
		close_screen()
		get_viewport().set_input_as_handled()
		return
	super(event)


func refresh() -> void:
	clear_content()
	var split := HBoxContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_theme_constant_override("separation", 18)
	content.add_child(split)

	# --- stats column
	var stats_card := PanelContainer.new()
	stats_card.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.PANEL_DARK, 18, 3, UiTheme.INK, 0, 18))
	stats_card.custom_minimum_size = Vector2(400, 0)
	split.add_child(stats_card)
	var sv := VBoxContainer.new()
	sv.add_theme_constant_override("separation", 6)
	stats_card.add_child(sv)
	sv.add_child(UiTheme.label("YOUR DIG SO FAR", 24, UiTheme.YELLOW, true))
	var s := GameState.stats
	var mins := int(GameState.playtime / 60.0)
	var rows := [
		["Time played", "%dh %02dm" % [mins / 60, mins % 60]],
		["Credits earned", GameData.format_money(int(s.get("total_earned", 0)))],
		["Scoops dug", GameData.format_money(int(s.get("digs", 0)))],
		["Ground moved", "%s m³" % GameData.format_money(int(s.get("volume_dug", 0.0)))],
		["Deepest point", "%d m" % int(s.get("max_depth", 0.0))],
		["Chunks collected", GameData.format_money(int(s.get("chunks_collected", 0)))],
		["Crystals shattered", str(int(s.get("formations", 0)))],
		["Lucky gems", str(int(s.get("bonus_gems", 0)))],
		["Earned by bots", GameData.format_money(int(s.get("robot_earned", 0)))],
		["Discoveries", "%d / %d" % [GameState.discoveries.size(), GameData.discoveries.size()]],
	]
	for r: Array in rows:
		var h := HBoxContainer.new()
		var a := UiTheme.label(str(r[0]), 21, UiTheme.MUTED)
		a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(a)
		h.add_child(UiTheme.label(str(r[1]), 21, UiTheme.CREAM, true))
		sv.add_child(h)
	sv.add_child(UiTheme.label("BACKPACK", 24, UiTheme.YELLOW, true))
	if GameState.inventory.is_empty():
		sv.add_child(UiTheme.label("Empty. Go dig!", 20, UiTheme.MUTED))
	for mat_id: String in GameState.inventory:
		var def := GameData.material(mat_id)
		var h2 := HBoxContainer.new()
		var dot := Panel.new()
		dot.custom_minimum_size = Vector2(22, 22)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		dot.add_theme_stylebox_override("panel", UiTheme.box(def["color_c"], 11, 3, UiTheme.INK, 0, 0))
		h2.add_child(dot)
		var n := UiTheme.label("  %s  x%d" % [def["name"], int(GameState.inventory[mat_id])], 20, UiTheme.CREAM)
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h2.add_child(n)
		h2.add_child(UiTheme.label(GameData.format_money(int(round(float(GameState.inventory[mat_id]) * GameState.unit_value(mat_id)))), 20, UiTheme.GREEN, true))
		sv.add_child(h2)

	# --- discoveries column
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	split.add_child(scroll)
	var dv := VBoxContainer.new()
	dv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dv.add_theme_constant_override("separation", 8)
	scroll.add_child(dv)
	for pid in GameData.planet_order:
		var cfg := GameData.planet(pid)
		var known := GameState.visited.has(pid)
		dv.add_child(UiTheme.label((str(cfg["name"]) if known else "Unknown planet").to_upper(), 26, UiTheme.SKY, true))
		for d in GameData.discoveries:
			if d.get("planet", "") != pid:
				continue
			var found := GameState.has_discovery(d["id"])
			var card := PanelContainer.new()
			card.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.PANEL_LIGHT if found else UiTheme.PANEL_DARK, 14, 3, UiTheme.INK, 0, 14))
			var h3 := HBoxContainer.new()
			h3.add_theme_constant_override("separation", 12)
			card.add_child(h3)
			var kind := str(d.get("kind", "artifact"))
			var icon_name: String = str({"artifact": "star", "place": "planet", "core": "luck"}.get(kind, "star")) if found else "lock"
			h3.add_child(UiIcon.make(icon_name, UiTheme.YELLOW if found else Color(0.4, 0.38, 0.55), 42))
			var tv := VBoxContainer.new()
			tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			tv.add_theme_constant_override("separation", 0)
			h3.add_child(tv)
			tv.add_child(UiTheme.label(str(d["name"]) if found else "? ? ?", 23, UiTheme.CREAM if found else UiTheme.MUTED, true))
			var hint: String = str(d["desc"]) if found else str({"artifact": "Something is buried out there...", "place": "A hidden place, not yet found.", "core": "They say every planet has a heart."}.get(kind, ""))
			var dl := UiTheme.label(hint, 18, UiTheme.MUTED)
			dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			tv.add_child(dl)
			dv.add_child(card)
