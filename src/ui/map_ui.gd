class_name MapUi
extends UiScreen
## The survey map (M): the whole planet as an azimuthal equidistant projection centred on the
## outpost - straight lines from the centre are true great-circle routes and true distances,
## the far side of the planet is the rim. Shows relief, regions (dimmed until visited),
## landmarks, relays, discovered places, the player and the waypoint. Click to set a waypoint,
## right-click to clear it; travel between online relays from the list.

signal travel_requested(to: String)

const MAP_PX := 512                        ## generated image resolution (cached per planet)
const ZOOMS := [1.0, 0.6, 0.38]             ## fraction of the planet shown (1 = to the far side)
var _cache: Dictionary = {}                ## planet id + generation -> ImageTexture

var world: World
var _view: _MapView
var _side: VBoxContainer
var _pending_task := -1
var _pending_image: Image
var zoom := 1                               ## index into ZOOMS


func _init() -> void:
	build("Survey map", 120, 60)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 22)
	h.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(h)
	_view = _MapView.new()
	_view.owner_ui = self
	_view.custom_minimum_size = Vector2(620, 620)
	_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	h.add_child(_view)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(380, 0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	h.add_child(scroll)
	_side = VBoxContainer.new()
	_side.add_theme_constant_override("separation", 10)
	_side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_side)


func setup(w: World) -> void:
	if _pending_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_pending_task)
		_pending_task = -1
	world = w
	_view.world = w
	var key := _key()
	if not _cache.has(key) and _pending_task < 0:
		# Build the relief image off the main thread as soon as the world exists.
		var geo := w.planet.geology
		var grass: Array = (w.planet.config.get("palette", {}) as Dictionary).get("grass", ["#7d9a5e", "#6b8f66"])
		_pending_task = WorkerThreadPool.add_task(func() -> void: _pending_image = render_image(geo, grass, MAP_PX))


func _exit_tree() -> void:
	# never leave the relief task running against a world that is being freed
	if _pending_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_pending_task)
		_pending_task = -1


func _key() -> String:
	return "%s_g%d" % [world.planet.geology.id, world.planet.geology.generation] if world != null else ""


func texture() -> Texture2D:
	var key := _key()
	if _cache.has(key):
		return _cache[key]
	if _pending_task >= 0 and WorkerThreadPool.is_task_completed(_pending_task):
		WorkerThreadPool.wait_for_task_completion(_pending_task)
		_pending_task = -1
		if _pending_image != null:
			_cache[key] = ImageTexture.create_from_image(_pending_image)
			return _cache[key]
	return null


## Renders the planet's relief and region colours (thread-safe: reads Geology only).
static func render_image(geo: Geology, grass: Array, px: int) -> Image:
	var img := Image.create(px, px, false, Image.FORMAT_RGBA8)
	var heights := PackedFloat32Array()
	heights.resize(px * px)
	var dirs: Array[Vector3] = []
	dirs.resize(px * px)
	for y in px:
		for x in px:
			var uv := Vector2((float(x) + 0.5) / float(px) * 2.0 - 1.0, (float(y) + 0.5) / float(px) * 2.0 - 1.0)
			var i := y * px + x
			if uv.length() > 1.0:
				heights[i] = 0.0
				continue
			var d := Navigation.from_map_static(uv, geo.landing_dir)
			dirs[i] = d
			heights[i] = geo.height_at(d)
	var g0 := Color(str(grass[0]))
	var g1 := Color(str(grass[min(1, grass.size() - 1)]))
	var lo := 1e9
	var hi := -1e9
	for v in heights:
		lo = minf(lo, v)
		hi = maxf(hi, v)
	for y in px:
		for x in px:
			var i := y * px + x
			var uv := Vector2((float(x) + 0.5) / float(px) * 2.0 - 1.0, (float(y) + 0.5) / float(px) * 2.0 - 1.0)
			if uv.length() > 1.0:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			var h := heights[i]
			# hill shading from a wide stencil, so landforms read and fine roughness does not
			var k := maxi(2, px / 128)
			var hx := heights[y * px + mini(x + k, px - 1)] - heights[y * px + maxi(x - k, 0)]
			var hy := heights[mini(y + k, px - 1) * px + x] - heights[maxi(y - k, 0) * px + x]
			var shade := clampf(0.86 - (hx + hy) * 0.035, 0.55, 1.12)
			var t := clampf((h - lo) / maxf(hi - lo, 0.001), 0.0, 1.0)
			var reg := geo.region_at(dirs[i])
			var col := g0.lerp(g1, smoothstep(0.3, 0.7, t)).darkened(0.18 * (1.0 - t))
			var rg: Array = (reg.get("cfg", {}) as Dictionary).get("grass", [])
			if not rg.is_empty():
				col = col.lerp(Color(str(rg[0])), 0.75)
			var cover := float(reg.get("cover", 1.0)) if not reg.is_empty() else 1.0
			col = col.lerp(Color("#8a7a66"), (1.0 - cover) * 0.45)
			col = col.lightened(smoothstep(0.55, 1.0, t) * 0.35) * shade
			# contour every 10 m
			var band := fmod(h + 1000.0, 10.0)
			if band < 0.5:
				col = col.darkened(0.1)
			# fade towards the rim (the far side of the planet)
			col = col.lerp(Color("#1e1915"), smoothstep(0.82, 1.0, uv.length()) * 0.55)
			col.a = 1.0
			img.set_pixel(x, y, col)
	return img


func open_screen() -> void:
	super.open_screen()


func refresh() -> void:
	for c in _side.get_children():
		_side.remove_child(c)
		c.queue_free()
	if world == null or world.nav == null:
		return
	var nav := world.nav
	var here := nav.current_region
	_side.add_child(UiTheme.caps("You are in", 13, UiTheme.DIM))
	_side.add_child(UiTheme.label(str(here.get("name", "Open country")), 24, UiTheme.TEXT, true))
	var desc := str((here.get("cfg", {}) as Dictionary).get("desc", ""))
	if desc != "":
		var dl := UiTheme.label(desc, 16, UiTheme.DIM)
		dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		dl.custom_minimum_size = Vector2(340, 0)
		_side.add_child(dl)
	_side.add_child(UiTheme.divider())
	_side.add_child(UiTheme.caps("Regions", 13, UiTheme.ACCENT))
	var surveyed := survey_known()
	for r in world.planet.geology.regions:
		var seen := nav.region_visited(r["id"])
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 0)
		var name_l := UiTheme.label(str(r["name"]) if seen else "Unexplored region", 17, UiTheme.TEXT if seen else UiTheme.FAINT)
		row.add_child(name_l)
		if surveyed or seen:
			var rich := rich_in(str(r["id"]))
			var dist := nav.surface_distance(world.player.global_position, (r["dir"] as Vector3) * world.planet.geology.radius)
			var info := "%d m away" % int(round(dist))
			if surveyed and not rich.is_empty():
				info += "  -  rich in " + ", ".join(rich)
			row.add_child(UiTheme.label(info, 14, UiTheme.DIM))
		_side.add_child(row)
	if not surveyed:
		var hint := UiTheme.label("Find a survey record to learn what each region is rich in.", 14, UiTheme.FAINT)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.custom_minimum_size = Vector2(340, 0)
		_side.add_child(hint)
	_side.add_child(UiTheme.divider())
	_side.add_child(UiTheme.caps("Travel", 13, UiTheme.ACCENT))
	for t: Dictionary in nav.travel_targets():
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 8)
		var lv := VBoxContainer.new()
		lv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lv.add_theme_constant_override("separation", 0)
		lv.add_child(UiTheme.label(str(t["name"]), 17, UiTheme.TEXT if bool(t["ok"]) else UiTheme.DIM))
		var sub := str(t["why"]) if str(t["why"]) != "" else "%d m" % int(round(nav.surface_distance(world.player.global_position, t["pos"])))
		lv.add_child(UiTheme.label(sub, 13, UiTheme.FAINT))
		h.add_child(lv)
		var b := UiTheme.button("Go", UiTheme.ACCENT if bool(t["ok"]) else UiTheme.PANEL_LIGHT, 16)
		b.disabled = not bool(t["ok"])
		var id := str(t["id"])
		b.pressed.connect(func() -> void: travel_requested.emit(id))
		h.add_child(b)
		_side.add_child(h)
	_side.add_child(UiTheme.divider())
	var wl := UiTheme.label("Click the map to set a waypoint; right-click to clear it. Mouse wheel zooms.", 14, UiTheme.DIM)
	wl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	wl.custom_minimum_size = Vector2(340, 0)
	_side.add_child(wl)
	_view.queue_redraw()


## Region survey data: unlocked on Pipseed by the Survey Penetrator; on other planets by
## visiting (the outpost's own scanner logs it).
func survey_known() -> bool:
	return GameState.has_discovery("survey_core")


## Materials a region is rich in (ores whose regional boost targets it).
func rich_in(region_id: String) -> Array[String]:
	var out: Array[String] = []
	for o: Dictionary in world.planet.config.get("ores", []):
		if str(o.get("region", "")) == region_id:
			out.append(str(GameData.material(str(o["material"])).get("name", o["material"])))
	return out


func set_waypoint_at(uv: Vector2) -> void:
	if world == null:
		return
	world.nav.set_waypoint(world.nav.from_map(uv))
	Audio.play("ui_click", -6.0)
	_view.queue_redraw()


func clear_waypoint() -> void:
	if world == null:
		return
	world.nav.set_waypoint(null)
	Audio.play("ui_click", -8.0)
	_view.queue_redraw()


func _process(_dt: float) -> void:
	if visible:
		_view.queue_redraw()


class _MapView:
	extends Control
	var owner_ui: MapUi
	var world: World

	func _rect() -> Rect2:
		var s := minf(size.x, size.y)
		return Rect2((size - Vector2(s, s)) * 0.5, Vector2(s, s))

	func _span() -> float:
		return float(MapUi.ZOOMS[owner_ui.zoom])

	func _to_px(uv: Vector2) -> Vector2:
		var r := _rect()
		return r.position + (uv / _span() * 0.5 + Vector2(0.5, 0.5)) * r.size

	func _inside(px: Vector2) -> bool:
		var r := _rect()
		return px.distance_to(r.get_center()) <= r.size.x * 0.5 + 1.0

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
			var mb := event as InputEventMouseButton
			var r := _rect()
			var uv := ((mb.position - r.position) / r.size * 2.0 - Vector2.ONE) * _span()
			if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
				owner_ui.zoom = mini(owner_ui.zoom + 1, MapUi.ZOOMS.size() - 1)
				accept_event()
				return
			if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				owner_ui.zoom = maxi(owner_ui.zoom - 1, 0)
				accept_event()
				return
			if uv.length() > 1.0 or not _inside(mb.position):
				return
			if mb.button_index == MOUSE_BUTTON_LEFT:
				owner_ui.set_waypoint_at(uv)
			elif mb.button_index == MOUSE_BUTTON_RIGHT:
				owner_ui.clear_waypoint()
			accept_event()

	func _draw() -> void:
		var r := _rect()
		draw_circle(r.get_center(), r.size.x * 0.5 + 3.0, UiTheme.LINE)
		var tex := owner_ui.texture()
		if tex != null:
			# the visible part of the projection, clipped to a disc by drawing a textured polygon
			var span := _span()
			var pts := PackedVector2Array()
			var uvs := PackedVector2Array()
			for k in 72:
				var a := TAU * float(k) / 72.0
				var u := Vector2(cos(a), sin(a))
				pts.append(r.get_center() + u * r.size.x * 0.5)
				uvs.append(u * span * 0.5 + Vector2(0.5, 0.5))
			draw_colored_polygon(pts, Color.WHITE, uvs, tex)
		else:
			draw_circle(r.get_center(), r.size.x * 0.5, UiTheme.PANEL_DARK)
			draw_string(UiTheme.font_regular(), r.get_center() - Vector2(70, 0), "Surveying...", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, UiTheme.DIM)
		if world == null or world.nav == null:
			return
		var nav := world.nav
		var geo := world.planet.geology
		var font := UiTheme.font_regular()
		var bold := UiTheme.font_bold()
		# distance rings every 250 m from the outpost
		var ring := 250.0
		while ring < PI * geo.radius * _span():
			draw_arc(r.get_center(), r.size.x * 0.5 * ring / (PI * geo.radius * _span()), 0.0, TAU, 96, Color(1, 1, 1, 0.08), 1.0)
			ring += 250.0
		# region names (visited ones only) and landmark names in visited regions
		for reg in geo.regions:
			if not nav.region_visited(reg["id"]):
				continue
			var p := _to_px(nav.to_map(reg["dir"]))
			if not _inside(p):
				continue
			var t := str(reg["name"]).to_upper()
			var w := bold.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
			draw_string(bold, p - Vector2(w * 0.5, -4), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(UiTheme.TEXT, 0.85))
		for f in geo.features:
			var src: Dictionary = f.get("src", {})
			if not src.has("name") or not nav.region_visited(str(nav.region_at(f["dir"]).get("id", "-"))):
				continue
			var p2 := _to_px(nav.to_map(f["dir"]))
			if not _inside(p2):
				continue
			draw_circle(p2, 2.5, Color(UiTheme.TEXT, 0.6))
			draw_string(font, p2 + Vector2(5, 4), str(src["name"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(UiTheme.TEXT, 0.6))
		# markers
		for m: Dictionary in nav.markers():
			var pm := _to_px(nav.to_map(m["pos"]))
			if not _inside(pm):
				continue
			match str(m["kind"]):
				"outpost":
					draw_circle(pm, 7.0, UiTheme.ACCENT)
					draw_circle(pm, 3.0, UiTheme.INK)
				"relay":
					_diamond(pm, 7.0, UiTheme.INFO)
					draw_string(font, pm + Vector2(9, 4), str(m["label"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UiTheme.INFO)
				"relay_off":
					_diamond(pm, 6.0, Color(UiTheme.DIM, 0.8), false)
				"place":
					draw_circle(pm, 4.0, UiTheme.GOLD)
					draw_string(font, pm + Vector2(7, 4), str(m["label"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UiTheme.GOLD)
				"bots", "borer":
					var c2 := UiTheme.GOOD if str(m["kind"]) == "bots" else UiTheme.ORANGE
					draw_rect(Rect2(pm - Vector2(4, 4), Vector2(8, 8)), c2)
					draw_string(font, pm + Vector2(7, 4), str(m["label"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, c2)
				"waypoint":
					draw_line(pm + Vector2(-8, -8), pm + Vector2(8, 8), UiTheme.TEXT, 2.0)
					draw_line(pm + Vector2(-8, 8), pm + Vector2(8, -8), UiTheme.TEXT, 2.0)
					draw_arc(pm, 10.0, 0.0, TAU, 24, UiTheme.TEXT, 1.5)
		# the player, with a heading arrow
		var pp := _to_px(nav.to_map(world.player.global_position))
		var fwd := -world.player.camera.global_basis.z
		var ahead := _to_px(nav.to_map(world.player.global_position + fwd * 12.0))
		var dir2 := (ahead - pp).normalized() if (ahead - pp).length() > 0.01 else Vector2.UP
		var side := Vector2(-dir2.y, dir2.x)
		draw_colored_polygon(PackedVector2Array([pp + dir2 * 11.0, pp - dir2 * 6.0 + side * 6.0, pp - dir2 * 3.0, pp - dir2 * 6.0 - side * 6.0]), UiTheme.TEXT)
		# scale bar
		var bar := r.size.x * 0.5 * 250.0 / (PI * geo.radius * _span())
		var b0 := r.position + Vector2(10, r.size.y - 14)
		draw_line(b0, b0 + Vector2(bar, 0), UiTheme.DIM, 2.0)
		draw_string(font, b0 + Vector2(0, -6), "250 m", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UiTheme.DIM)

	func _diamond(p: Vector2, s: float, c: Color, filled := true) -> void:
		var pts := PackedVector2Array([p + Vector2(0, -s), p + Vector2(s, 0), p + Vector2(0, s), p + Vector2(-s, 0)])
		if filled:
			draw_colored_polygon(pts, c)
		else:
			pts.append(pts[0])
			draw_polyline(pts, c, 1.5)
