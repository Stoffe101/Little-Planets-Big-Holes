class_name UiIcon
extends Control
## Resolution-independent vector icons drawn in code (no image assets). One flat colour, even
## stroke weight, simple geometry - they should read like pictograms on an instrument panel.
## Set `icon` to one of the names handled in _draw(); `color` is the ink.

var icon := "coin":
	set(v):
		icon = v
		queue_redraw()
var color := UiTheme.TEXT:
	set(v):
		color = v
		queue_redraw()
## Rotation of the glyph in radians (used by the base-direction arrow).
var angle := 0.0:
	set(v):
		angle = v
		queue_redraw()


static func make(icon_name: String, col: Color, size := 48.0) -> UiIcon:
	var i := UiIcon.new()
	i.icon = icon_name
	i.color = col
	i.custom_minimum_size = Vector2(size, size)
	i.mouse_filter = Control.MOUSE_FILTER_IGNORE
	i.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return i


func _line(a: Vector2, b: Vector2, w: float) -> void:
	draw_line(a, b, color, w, true)
	draw_circle(a, w * 0.5, color)
	draw_circle(b, w * 0.5, color)


func _poly(pts: PackedVector2Array) -> void:
	draw_colored_polygon(pts, color)


func _ring(c: Vector2, r: float, w: float, from := 0.0, to := TAU) -> void:
	draw_arc(c, r, from, to, 32, color, w, true)


func _rrect(r: Rect2, radius: float, fill := true, w := 2.0) -> void:
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(int(radius))
	sb.anti_aliasing = true
	if fill:
		sb.bg_color = color
	else:
		sb.bg_color = Color(0, 0, 0, 0)
		sb.set_border_width_all(int(maxf(1.0, round(w))))
		sb.border_color = color
	draw_style_box(sb, r)


func _draw() -> void:
	var s := minf(size.x, size.y)
	var c := size * 0.5
	var w := maxf(1.5, s * 0.085)
	if angle != 0.0:
		draw_set_transform(c, angle, Vector2.ONE)
		c = Vector2.ZERO
	var dark := Color(UiTheme.INK.r, UiTheme.INK.g, UiTheme.INK.b, 0.85)
	match icon:
		"coin":
			_ring(c, s * 0.34, w)
			_line(c + Vector2(0, -s * 0.14), c + Vector2(0, s * 0.14), w)
		"pack":
			_rrect(Rect2(c + Vector2(-s * 0.28, -s * 0.2), Vector2(s * 0.56, s * 0.56)), s * 0.1)
			_ring(c + Vector2(0, -s * 0.2), s * 0.13, w, PI, TAU)
			draw_rect(Rect2(c + Vector2(-s * 0.16, s * 0.04), Vector2(s * 0.32, w * 0.8)), dark)
		"magnet":
			_ring(c + Vector2(0, -s * 0.02), s * 0.24, w * 1.9, PI, TAU)
			for sx: float in [-1.0, 1.0]:
				draw_rect(Rect2(c + Vector2(sx * s * 0.24 - w * 0.95, -s * 0.03), Vector2(w * 1.9, s * 0.2)), color)
				draw_rect(Rect2(c + Vector2(sx * s * 0.24 - w * 0.95, s * 0.22), Vector2(w * 1.9, s * 0.1)), color)
		"boots":
			_poly(PackedVector2Array([c + Vector2(-s * 0.2, -s * 0.32), c + Vector2(s * 0.02, -s * 0.32), c + Vector2(s * 0.04, s * 0.04), c + Vector2(s * 0.32, s * 0.14), c + Vector2(s * 0.32, s * 0.22), c + Vector2(-s * 0.2, s * 0.22)]))
			draw_rect(Rect2(c + Vector2(-s * 0.22, s * 0.27), Vector2(s * 0.56, w * 0.8)), color)
		"jets":
			_rrect(Rect2(c + Vector2(-s * 0.14, -s * 0.34), Vector2(s * 0.28, s * 0.4)), s * 0.12)
			_poly(PackedVector2Array([c + Vector2(-s * 0.1, s * 0.12), c + Vector2(s * 0.1, s * 0.12), c + Vector2(0, s * 0.38)]))
		"scan":
			for i in 3:
				_ring(c + Vector2(0, s * 0.22), s * (0.16 + 0.14 * i), w * 0.9, PI * 1.18, PI * 1.82)
			draw_circle(c + Vector2(0, s * 0.24), s * 0.07, color)
		"luck":
			for i in 4:
				var a := TAU * float(i) / 4.0 + PI * 0.25
				draw_circle(c + Vector2(cos(a), sin(a)) * s * 0.16, s * 0.15, color)
		"robot":
			_rrect(Rect2(c + Vector2(-s * 0.3, -s * 0.16), Vector2(s * 0.6, s * 0.42)), s * 0.12)
			draw_rect(Rect2(c + Vector2(-s * 0.18, -s * 0.02), Vector2(s * 0.36, s * 0.09)), dark)
			_line(c + Vector2(0, -s * 0.16), c + Vector2(0, -s * 0.32), w * 0.8)
		"speed":
			for i in 2:
				var o := Vector2(-s * 0.16 + s * 0.26 * i, 0)
				_poly(PackedVector2Array([c + o + Vector2(-s * 0.14, -s * 0.26), c + o + Vector2(s * 0.14, 0), c + o + Vector2(-s * 0.14, s * 0.26)]))
		"radius":
			_ring(c, s * 0.32, w)
			draw_circle(c, s * 0.1, color)
		"shape":
			_rrect(Rect2(c + Vector2(-s * 0.36, -s * 0.1), Vector2(s * 0.72, s * 0.2)), s * 0.1)
		"ore":
			_poly(PackedVector2Array([c + Vector2(0, -s * 0.36), c + Vector2(s * 0.3, -s * 0.08), c + Vector2(s * 0.18, s * 0.32), c + Vector2(-s * 0.18, s * 0.32), c + Vector2(-s * 0.3, -s * 0.08)]))
			draw_line(c + Vector2(-s * 0.3, -s * 0.08), c + Vector2(s * 0.3, -s * 0.08), dark, w * 0.6, true)
		"reach":
			_line(c + Vector2(-s * 0.32, 0), c + Vector2(s * 0.2, 0), w)
			_poly(PackedVector2Array([c + Vector2(s * 0.12, -s * 0.2), c + Vector2(s * 0.38, 0), c + Vector2(s * 0.12, s * 0.2)]))
		"shovel":
			_line(c + Vector2(s * 0.3, -s * 0.32), c + Vector2(-s * 0.04, s * 0.02), w)
			_poly(PackedVector2Array([c + Vector2(-s * 0.0, -s * 0.14), c + Vector2(s * 0.14, s * 0.0), c + Vector2(-s * 0.12, s * 0.32), c + Vector2(-s * 0.34, s * 0.36), c + Vector2(-s * 0.3, s * 0.14)]))
		"drill":
			_rrect(Rect2(c + Vector2(-s * 0.02, -s * 0.34), Vector2(s * 0.34, s * 0.3)), s * 0.07)
			_poly(PackedVector2Array([c + Vector2(-s * 0.0, -s * 0.0), c + Vector2(s * 0.2, -s * 0.0), c + Vector2(-s * 0.28, s * 0.38)]))
		"vacuum":
			_rrect(Rect2(c + Vector2(-s * 0.04, -s * 0.32), Vector2(s * 0.38, s * 0.32)), s * 0.1)
			_poly(PackedVector2Array([c + Vector2(-s * 0.0, -s * 0.02), c + Vector2(s * 0.14, s * 0.04), c + Vector2(-s * 0.1, s * 0.38), c + Vector2(-s * 0.38, s * 0.24)]))
		"cannon":
			_rrect(Rect2(c + Vector2(-s * 0.36, -s * 0.14), Vector2(s * 0.66, s * 0.28)), s * 0.08)
			draw_rect(Rect2(c + Vector2(-s * 0.16, s * 0.14), Vector2(s * 0.12, s * 0.2)), color)
			draw_rect(Rect2(c + Vector2(s * 0.2, -s * 0.2), Vector2(s * 0.1, s * 0.4)), color)
		"lock":
			_ring(c + Vector2(0, -s * 0.08), s * 0.15, w, PI, TAU)
			_rrect(Rect2(c + Vector2(-s * 0.24, -s * 0.08), Vector2(s * 0.48, s * 0.38)), s * 0.06)
		"check":
			draw_polyline(PackedVector2Array([c + Vector2(-s * 0.28, 0), c + Vector2(-s * 0.08, s * 0.2), c + Vector2(s * 0.3, -s * 0.22)]), color, w * 1.2, true)
		"star":
			var pts2 := PackedVector2Array()
			for i in 10:
				var a2 := TAU * float(i) / 10.0 - PI * 0.5
				pts2.append(c + Vector2(cos(a2), sin(a2)) * s * (0.4 if i % 2 == 0 else 0.18))
			_poly(pts2)
		"planet":
			draw_circle(c, s * 0.26, color)
			_ring(c, s * 0.4, w * 0.8, PI * 0.1, PI * 0.9)
		"home":
			_poly(PackedVector2Array([c + Vector2(0, -s * 0.36), c + Vector2(s * 0.36, -s * 0.02), c + Vector2(s * 0.24, -s * 0.02), c + Vector2(s * 0.24, s * 0.32), c + Vector2(-s * 0.24, s * 0.32), c + Vector2(-s * 0.24, -s * 0.02), c + Vector2(-s * 0.36, -s * 0.02)]))
		"arrow":
			_poly(PackedVector2Array([c + Vector2(0, -s * 0.38), c + Vector2(s * 0.26, s * 0.3), c + Vector2(0, s * 0.14), c + Vector2(-s * 0.26, s * 0.3)]))
		"depth":
			_line(c + Vector2(0, -s * 0.34), c + Vector2(0, s * 0.2), w)
			_poly(PackedVector2Array([c + Vector2(-s * 0.2, s * 0.1), c + Vector2(s * 0.2, s * 0.1), c + Vector2(0, s * 0.38)]))
		"dot":
			draw_circle(c, s * 0.3, color)
		_:
			_ring(c, s * 0.3, w)
	if angle != 0.0:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
