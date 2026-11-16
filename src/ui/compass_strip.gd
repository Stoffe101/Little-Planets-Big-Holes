class_name CompassStrip
extends Control
## Heading strip at the top of the HUD: N/E/S/W ticks around the player's view direction (north
## is the planet's -Z pole) and markers for the outpost, the waypoint, online relays and found
## places, each with its distance. The outpost and waypoint stay pinned to the edge when behind.

const HALF_FOV := deg_to_rad(80.0)
const WIDTH := 600.0

var world: World


func _init() -> void:
	custom_minimum_size = Vector2(WIDTH, 46)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _x(angle: float) -> float:
	return WIDTH * 0.5 + angle / HALF_FOV * WIDTH * 0.5


func _draw() -> void:
	if world == null or world.nav == null or world.player == null or not world.is_ready:
		return
	var nav := world.nav
	var font := UiTheme.font_bold()
	var small := UiTheme.font_regular()
	var mid := WIDTH * 0.5
	# soft backing line
	draw_rect(Rect2(0, 12, WIDTH, 1), Color(UiTheme.TEXT, 0.18))
	draw_rect(Rect2(mid - 1, 4, 2, 9), Color(UiTheme.TEXT, 0.8))
	var heading := nav.heading()
	for k in 24:
		var a := TAU * float(k) / 24.0
		var rel := wrapf(a - heading, -PI, PI)
		if absf(rel) > HALF_FOV:
			continue
		var x := _x(rel)
		var fade := 1.0 - smoothstep(HALF_FOV * 0.7, HALF_FOV, absf(rel))
		if k % 6 == 0:
			var letter: String = ["N", "E", "S", "W"][k / 6]
			var w := font.get_string_size(letter, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
			draw_string(font, Vector2(x - w * 0.5, 30), letter, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(UiTheme.ACCENT if k == 0 else UiTheme.TEXT, fade))
		else:
			draw_rect(Rect2(x - 0.5, 8, 1, 6 if k % 3 == 0 else 3), Color(UiTheme.TEXT, 0.5 * fade))
	var labels: Array[Vector2] = []    # x-extents of distance labels already drawn (no overlaps)
	for m: Dictionary in nav.markers():
		var kind := str(m["kind"])
		if kind == "relay_off":
			continue
		var rel2 := nav.bearing_to(m["pos"])
		var pinned := kind in ["outpost", "waypoint", "borer"]
		if absf(rel2) > HALF_FOV and not pinned:
			continue
		var x2 := _x(clampf(rel2, -HALF_FOV, HALF_FOV))
		var col: Color = {"outpost": UiTheme.ACCENT, "waypoint": UiTheme.TEXT, "relay": UiTheme.INFO, "place": UiTheme.GOLD,
			"bots": UiTheme.GOOD, "borer": UiTheme.ORANGE}.get(kind, UiTheme.TEXT)
		var dist := nav.surface_distance(world.player.global_position, m["pos"])
		if dist < 6.0:
			continue
		match kind:
			"outpost":
				draw_circle(Vector2(x2, 12), 5.0, col)
				draw_circle(Vector2(x2, 12), 2.0, UiTheme.INK)
			"waypoint":
				draw_line(Vector2(x2 - 5, 7), Vector2(x2 + 5, 17), col, 2.0)
				draw_line(Vector2(x2 - 5, 17), Vector2(x2 + 5, 7), col, 2.0)
			"relay":
				draw_colored_polygon(PackedVector2Array([Vector2(x2, 6), Vector2(x2 + 5, 12), Vector2(x2, 18), Vector2(x2 - 5, 12)]), col)
			_:
				draw_circle(Vector2(x2, 12), 3.5, col)
		if pinned or absf(rel2) < HALF_FOV * 0.5:
			var label := "%d m" % int(round(dist)) if dist < 1000.0 else "%.1f km" % (dist / 1000.0)
			var w2 := small.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
			var span := Vector2(x2 - w2 * 0.5 - 4.0, x2 + w2 * 0.5 + 4.0)
			var free := true
			for o in labels:
				if span.x < o.y and span.y > o.x:
					free = false
			if free:
				labels.append(span)
				draw_string(small, Vector2(x2 - w2 * 0.5, 44), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(col, 0.9))
