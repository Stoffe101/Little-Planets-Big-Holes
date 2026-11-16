class_name UiIcon
extends Control
## Resolution-independent vector icons drawn in code (no image assets). Set `icon` to one of the
## names handled in _draw(); `color` is the main fill and everything gets a chunky ink outline.

var icon := "coin":
	set(v):
		icon = v
		queue_redraw()
var color := UiTheme.YELLOW:
	set(v):
		color = v
		queue_redraw()
var outline := true


static func make(icon_name: String, col: Color, size := 48.0) -> UiIcon:
	var i := UiIcon.new()
	i.icon = icon_name
	i.color = col
	i.custom_minimum_size = Vector2(size, size)
	i.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return i


func _draw() -> void:
	var s := minf(size.x, size.y)
	var c := size * 0.5
	var ink := UiTheme.INK
	var w := maxf(2.0, s * 0.07)
	match icon:
		"coin":
			_disc(c, s * 0.42, color, ink, w)
			draw_arc(c, s * 0.27, 0, TAU, 24, color.darkened(0.25), w * 0.8, true)
			draw_line(c + Vector2(0, -s * 0.14), c + Vector2(0, s * 0.14), ink, w, true)
		"pack":
			_rrect(Rect2(c + Vector2(-s * 0.3, -s * 0.28), Vector2(s * 0.6, s * 0.66)), color, ink, w, s * 0.14)
			_rrect(Rect2(c + Vector2(-s * 0.2, s * 0.02), Vector2(s * 0.4, s * 0.22)), color.lightened(0.35), ink, w * 0.8, s * 0.06)
			draw_arc(c + Vector2(0, -s * 0.28), s * 0.13, PI, TAU, 12, ink, w, true)
		"magnet":
			draw_arc(c + Vector2(0, -s * 0.02), s * 0.27, PI, TAU, 20, ink, s * 0.26, true)
			draw_arc(c + Vector2(0, -s * 0.02), s * 0.27, PI, TAU, 20, color, s * 0.16, true)
			for sx: float in [-1.0, 1.0]:
				_rrect(Rect2(c + Vector2(sx * s * 0.27 - s * 0.11, -s * 0.04), Vector2(s * 0.22, s * 0.36)), color, ink, w, s * 0.03)
				_rrect(Rect2(c + Vector2(sx * s * 0.27 - s * 0.11, s * 0.2), Vector2(s * 0.22, s * 0.14)), UiTheme.CREAM, ink, w, s * 0.03)
		"boots":
			var pts := PackedVector2Array([c + Vector2(-s * 0.2, -s * 0.34), c + Vector2(s * 0.04, -s * 0.34), c + Vector2(s * 0.06, s * 0.04), c + Vector2(s * 0.34, s * 0.14), c + Vector2(s * 0.34, s * 0.3), c + Vector2(-s * 0.22, s * 0.3)])
			_poly(pts, color, ink, w)
			draw_line(c + Vector2(-s * 0.22, s * 0.2), c + Vector2(s * 0.34, s * 0.2), ink, w * 0.8, true)
		"jets":
			_rrect(Rect2(c + Vector2(-s * 0.16, -s * 0.36), Vector2(s * 0.32, s * 0.46)), color, ink, w, s * 0.14)
			_poly(PackedVector2Array([c + Vector2(-s * 0.12, s * 0.12), c + Vector2(s * 0.12, s * 0.12), c + Vector2(0, s * 0.42)]), UiTheme.ORANGE, ink, w)
			_disc(c + Vector2(0, -s * 0.16), s * 0.08, UiTheme.SKY, ink, w * 0.7)
		"scan":
			for i in 3:
				draw_arc(c + Vector2(0, s * 0.22), s * (0.16 + 0.14 * i), PI * 1.15, PI * 1.85, 16, ink, w * 1.9, true)
				draw_arc(c + Vector2(0, s * 0.22), s * (0.16 + 0.14 * i), PI * 1.15, PI * 1.85, 16, color, w, true)
			_disc(c + Vector2(0, s * 0.24), s * 0.08, color, ink, w * 0.8)
		"luck":
			for i in 4:
				var a := TAU * float(i) / 4.0 + PI * 0.25
				_disc(c + Vector2(cos(a), sin(a)) * s * 0.17, s * 0.17, color, ink, w)
			_disc(c, s * 0.08, color.darkened(0.2), ink, 0.0)
		"robot":
			_rrect(Rect2(c + Vector2(-s * 0.3, -s * 0.2), Vector2(s * 0.6, s * 0.46)), color, ink, w, s * 0.16)
			_disc(c + Vector2(0, 0.02 * s), s * 0.12, UiTheme.SKY, ink, w * 0.8)
			draw_line(c + Vector2(0, -s * 0.2), c + Vector2(0, -s * 0.36), ink, w, true)
			_disc(c + Vector2(0, -s * 0.38), s * 0.06, UiTheme.PINK, ink, w * 0.6)
		"speed":
			for i in 2:
				var o := Vector2(-s * 0.16 + s * 0.26 * i, 0)
				_poly(PackedVector2Array([c + o + Vector2(-s * 0.14, -s * 0.28), c + o + Vector2(s * 0.16, 0), c + o + Vector2(-s * 0.14, s * 0.28)]), color, ink, w)
		"radius":
			draw_arc(c, s * 0.34, 0, TAU, 28, ink, w * 1.8, true)
			draw_arc(c, s * 0.34, 0, TAU, 28, color, w * 0.9, true)
			_disc(c, s * 0.12, color, ink, w * 0.8)
		"shape":
			_rrect(Rect2(c + Vector2(-s * 0.38, -s * 0.12), Vector2(s * 0.76, s * 0.24)), color, ink, w, s * 0.12)
		"ore":
			_poly(PackedVector2Array([c + Vector2(0, -s * 0.38), c + Vector2(s * 0.3, -s * 0.08), c + Vector2(s * 0.18, s * 0.34), c + Vector2(-s * 0.18, s * 0.34), c + Vector2(-s * 0.3, -s * 0.08)]), color, ink, w)
			draw_line(c + Vector2(-s * 0.3, -s * 0.08), c + Vector2(s * 0.3, -s * 0.08), ink, w * 0.7, true)
			draw_line(c + Vector2(0, -s * 0.38), c + Vector2(0, s * 0.34), ink, w * 0.5, true)
		"reach":
			draw_line(c + Vector2(-s * 0.34, 0), c + Vector2(s * 0.3, 0), ink, w * 2.2, true)
			draw_line(c + Vector2(-s * 0.34, 0), c + Vector2(s * 0.3, 0), color, w * 1.1, true)
			_poly(PackedVector2Array([c + Vector2(s * 0.14, -s * 0.2), c + Vector2(s * 0.4, 0), c + Vector2(s * 0.14, s * 0.2)]), color, ink, w)
		"shovel":
			draw_line(c + Vector2(s * 0.3, -s * 0.34), c + Vector2(-s * 0.06, s * 0.02), ink, w * 2.4, true)
			draw_line(c + Vector2(s * 0.3, -s * 0.34), c + Vector2(-s * 0.06, s * 0.02), UiTheme.ORANGE.lightened(0.3), w * 1.2, true)
			_poly(PackedVector2Array([c + Vector2(-s * 0.02, -s * 0.12), c + Vector2(s * 0.12, s * 0.02), c + Vector2(-s * 0.14, s * 0.34), c + Vector2(-s * 0.36, s * 0.38), c + Vector2(-s * 0.32, s * 0.14)]), color, ink, w)
		"drill":
			_rrect(Rect2(c + Vector2(-s * 0.02, -s * 0.36), Vector2(s * 0.36, s * 0.34)), color, ink, w, s * 0.08)
			_poly(PackedVector2Array([c + Vector2(-s * 0.02, -s * 0.06), c + Vector2(s * 0.22, -s * 0.06), c + Vector2(-s * 0.3, s * 0.4)]), UiTheme.CREAM, ink, w)
			draw_line(c + Vector2(s * 0.04, s * 0.04), c + Vector2(-s * 0.08, s * 0.1), ink, w * 0.6, true)
			draw_line(c + Vector2(-s * 0.06, s * 0.16), c + Vector2(-s * 0.16, s * 0.22), ink, w * 0.6, true)
		"vacuum":
			_rrect(Rect2(c + Vector2(-s * 0.06, -s * 0.34), Vector2(s * 0.4, s * 0.36)), color, ink, w, s * 0.12)
			_poly(PackedVector2Array([c + Vector2(-s * 0.02, -s * 0.06), c + Vector2(s * 0.14, s * 0.02), c + Vector2(-s * 0.12, s * 0.4), c + Vector2(-s * 0.4, s * 0.26)]), UiTheme.CREAM, ink, w)
		"cannon":
			_rrect(Rect2(c + Vector2(-s * 0.36, -s * 0.16), Vector2(s * 0.62, s * 0.32)), color, ink, w, s * 0.1)
			_disc(c + Vector2(s * 0.28, 0), s * 0.2, UiTheme.YELLOW, ink, w)
			_rrect(Rect2(c + Vector2(-s * 0.18, s * 0.14), Vector2(s * 0.14, s * 0.24)), ink, ink, 0.0, s * 0.03)
		"lock":
			draw_arc(c + Vector2(0, -s * 0.08), s * 0.17, PI, TAU, 14, ink, w * 2.0, true)
			draw_arc(c + Vector2(0, -s * 0.08), s * 0.17, PI, TAU, 14, UiTheme.MUTED, w, true)
			_rrect(Rect2(c + Vector2(-s * 0.26, -s * 0.08), Vector2(s * 0.52, s * 0.42)), color, ink, w, s * 0.08)
		"check":
			draw_polyline(PackedVector2Array([c + Vector2(-s * 0.28, 0), c + Vector2(-s * 0.08, s * 0.22), c + Vector2(s * 0.3, -s * 0.24)]), ink, w * 2.6, true)
			draw_polyline(PackedVector2Array([c + Vector2(-s * 0.28, 0), c + Vector2(-s * 0.08, s * 0.22), c + Vector2(s * 0.3, -s * 0.24)]), color, w * 1.4, true)
		"star":
			var pts2 := PackedVector2Array()
			for i in 10:
				var a := TAU * float(i) / 10.0 - PI * 0.5
				pts2.append(c + Vector2(cos(a), sin(a)) * s * (0.42 if i % 2 == 0 else 0.19))
			_poly(pts2, color, ink, w)
		"planet":
			_disc(c, s * 0.3, color, ink, w)
			draw_arc(c, s * 0.42, PI * 0.08, PI * 0.92, 16, ink, w * 1.6, true)
			draw_arc(c, s * 0.42, PI * 0.08, PI * 0.92, 16, UiTheme.CREAM, w * 0.8, true)
		_:
			_disc(c, s * 0.36, color, ink, w)


func _disc(center: Vector2, r: float, fill: Color, ink: Color, w: float) -> void:
	if outline and w > 0.0:
		draw_circle(center, r + w * 0.5, ink, true, -1.0, true)
	draw_circle(center, r - w * 0.3, fill, true, -1.0, true)


func _poly(pts: PackedVector2Array, fill: Color, ink: Color, w: float) -> void:
	draw_colored_polygon(pts, fill)
	if outline and w > 0.0:
		var closed := pts.duplicate()
		closed.append(pts[0])
		draw_polyline(closed, ink, w, true)


func _rrect(r: Rect2, fill: Color, ink: Color, w: float, radius: float) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.set_corner_radius_all(int(radius))
	sb.anti_aliasing = true
	if outline and w > 0.0:
		sb.set_border_width_all(int(ceil(w)))
		sb.border_color = ink
	draw_style_box(sb, r)
