class_name UiTheme
extends RefCounted
## Central look & feel for every menu and HUD element: chunky rounded panels, toy-like buttons
## with a bottom "lip", the Fredoka typeface, and one shared colour palette.

const INK := Color("#1b1538")           ## darkest outline / text-on-light
const PANEL := Color("#2a2152")
const PANEL_LIGHT := Color("#3a2f6e")
const PANEL_DARK := Color("#1f183f")
const CREAM := Color("#fff6e6")
const MUTED := Color("#b7addf")
const YELLOW := Color("#ffd34a")
const ORANGE := Color("#ff9d4a")
const PINK := Color("#ff7fb0")
const TEAL := Color("#5fe3c9")
const SKY := Color("#6cc4ff")
const GREEN := Color("#7be36b")
const RED := Color("#ff6b6b")
const PURPLE := Color("#b98cff")

static var _regular: Font
static var _semibold: Font
static var _bold: Font
static var _theme: Theme

## Typeface: a clean DIN-style grotesque. Resolved from the system (Bahnschrift on Windows, the
## usual sans-serifs elsewhere) with the engine's built-in Open Sans as the final fallback, so
## no font file has to be shipped. See docs/ART_DIRECTION.md, "UI".
const FONT_NAMES: PackedStringArray = ["Bahnschrift", "DIN Alternate", "Inter", "Roboto", "Noto Sans", "DejaVu Sans", "Arial"]


static func _system_font(weight: int) -> Font:
	var f := SystemFont.new()
	f.font_names = FONT_NAMES
	f.font_weight = weight
	f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	f.multichannel_signed_distance_field = true
	f.generate_mipmaps = true
	f.allow_system_fallback = true
	return f


static func font_regular() -> Font:
	if _regular == null:
		_regular = _system_font(400)
	return _regular


static func font_semibold() -> Font:
	if _semibold == null:
		_semibold = _system_font(500)
	return _semibold


static func font_bold() -> Font:
	if _bold == null:
		_bold = _system_font(700)
	return _bold


static func box(color: Color, radius := 18, border := 0, border_color := INK, lip := 0, pad := 14) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(radius)
	s.corner_detail = 10
	s.anti_aliasing = true
	if border > 0:
		s.set_border_width_all(border)
		s.border_color = border_color
	if lip > 0:
		s.border_width_bottom = border + lip
		if border == 0:
			s.border_color = border_color
	s.content_margin_left = pad
	s.content_margin_right = pad
	s.content_margin_top = pad * 0.6
	s.content_margin_bottom = pad * 0.6 + lip
	return s


static func panel_box(color := PANEL, radius := 22, alpha := 0.94) -> StyleBoxFlat:
	var s := box(Color(color.r, color.g, color.b, alpha), radius, 4, Color(INK.r, INK.g, INK.b, 0.9), 0, 18)
	s.shadow_color = Color(0, 0, 0, 0.35)
	s.shadow_size = 10
	s.shadow_offset = Vector2(0, 6)
	return s


## A set of button styles (normal / hover / pressed / disabled) in one accent colour.
static func style_button(b: Button, color: Color, font_size := 26, text_color := INK) -> void:
	var dark := color.darkened(0.38)
	b.add_theme_stylebox_override("normal", box(color, 16, 0, dark, 6, 18))
	b.add_theme_stylebox_override("hover", box(color.lightened(0.14), 16, 0, dark, 6, 18))
	var pressed := box(color.darkened(0.08), 16, 0, dark, 2, 18)
	pressed.content_margin_top += 4
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("focus", box(Color(0, 0, 0, 0), 16, 3, CREAM, 0, 18))
	var dis := box(Color(0.42, 0.4, 0.55), 16, 0, Color(0.25, 0.23, 0.36), 6, 18)
	b.add_theme_stylebox_override("disabled", dis)
	b.add_theme_font_override("font", font_bold())
	b.add_theme_font_size_override("font_size", font_size)
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(key, text_color)
	b.add_theme_color_override("font_disabled_color", Color(0.75, 0.73, 0.85))
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


static func button(text: String, color := YELLOW, font_size := 26) -> Button:
	var b := Button.new()
	b.text = text
	style_button(b, color, font_size)
	b.pressed.connect(func() -> void: Audio.play("ui_click", -6.0, 1.0, 0.04))
	b.mouse_entered.connect(func() -> void:
		if not b.disabled:
			Audio.play("ui_hover", -16.0, 1.0, 0.05, 0.03))
	return b


static func label(text: String, size := 24, color := CREAM, bold := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font_bold() if bold else font_semibold())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


## Label with a dark outline, readable over the 3D world.
static func hud_label(text: String, size := 28, color := CREAM) -> Label:
	var l := label(text, size, color, true)
	l.add_theme_constant_override("outline_size", maxi(6, size / 4))
	l.add_theme_color_override("font_outline_color", Color(INK.r, INK.g, INK.b, 0.95))
	return l


static func theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font = font_semibold()
	t.default_font_size = 24
	t.set_color("font_color", "Label", CREAM)
	t.set_stylebox("panel", "PanelContainer", panel_box())
	t.set_stylebox("panel", "Panel", panel_box())
	# progress bars
	t.set_stylebox("background", "ProgressBar", box(Color(INK.r, INK.g, INK.b, 0.85), 10, 3, INK, 0, 0))
	t.set_stylebox("fill", "ProgressBar", box(TEAL, 8, 3, INK, 0, 0))
	t.set_font_size("font_size", "ProgressBar", 18)
	# sliders
	var groove := box(PANEL_DARK, 8, 3, INK, 0, 0)
	groove.content_margin_top = 7
	groove.content_margin_bottom = 7
	t.set_stylebox("slider", "HSlider", groove)
	var fill := box(YELLOW, 8, 3, INK, 0, 0)
	fill.content_margin_top = 7
	fill.content_margin_bottom = 7
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)
	var knob := _circle_texture(30, CREAM, INK)
	t.set_icon("grabber", "HSlider", knob)
	t.set_icon("grabber_highlight", "HSlider", _circle_texture(30, YELLOW, INK))
	t.set_icon("grabber_disabled", "HSlider", knob)
	# check buttons
	t.set_font_size("font_size", "CheckButton", 24)
	t.set_color("font_color", "CheckButton", CREAM)
	t.set_color("font_hover_color", "CheckButton", YELLOW)
	t.set_color("font_pressed_color", "CheckButton", CREAM)
	t.set_icon("checked", "CheckButton", _toggle_texture(true))
	t.set_icon("unchecked", "CheckButton", _toggle_texture(false))
	t.set_stylebox("focus", "CheckButton", StyleBoxEmpty.new())
	# scroll bars
	var sb := box(Color(1, 1, 1, 0.08), 6, 0, INK, 0, 0)
	sb.content_margin_left = 6; sb.content_margin_right = 6
	t.set_stylebox("scroll", "VScrollBar", sb)
	t.set_stylebox("grabber", "VScrollBar", box(MUTED, 6, 0, INK, 0, 0))
	t.set_stylebox("grabber_highlight", "VScrollBar", box(CREAM, 6, 0, INK, 0, 0))
	t.set_stylebox("grabber_pressed", "VScrollBar", box(YELLOW, 6, 0, INK, 0, 0))
	# tooltips
	t.set_stylebox("panel", "TooltipPanel", box(INK, 10, 2, MUTED, 0, 10))
	t.set_color("font_color", "TooltipLabel", CREAM)
	t.set_font_size("font_size", "TooltipLabel", 20)
	# rich text
	t.set_font("normal_font", "RichTextLabel", font_semibold())
	t.set_font("bold_font", "RichTextLabel", font_bold())
	t.set_font_size("normal_font_size", "RichTextLabel", 22)
	t.set_font_size("bold_font_size", "RichTextLabel", 22)
	t.set_color("default_color", "RichTextLabel", CREAM)
	_theme = t
	return t


static func _circle_texture(size: int, fill: Color, outline: Color) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := Vector2(size, size) * 0.5
	var r := size * 0.5 - 1.0
	for y in size:
		for x in size:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(c)
			var a := clampf(r - d + 0.5, 0.0, 1.0)
			var col := fill if d < r - 3.5 else outline
			img.set_pixel(x, y, Color(col.r, col.g, col.b, a))
	return ImageTexture.create_from_image(img)


static func _toggle_texture(on: bool) -> ImageTexture:
	var w := 64
	var h := 34
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var track := GREEN if on else Color(0.35, 0.32, 0.5)
	var knob_x := float(w - h * 0.5) if on else h * 0.5
	for y in h:
		for x in w:
			var p := Vector2(x + 0.5, y + 0.5)
			# rounded track (capsule)
			var cx := clampf(p.x, h * 0.5, w - h * 0.5)
			var d := p.distance_to(Vector2(cx, h * 0.5))
			var r := h * 0.5 - 1.0
			var a := clampf(r - d + 0.5, 0.0, 1.0)
			var col := track if d < r - 3.0 else INK
			var kd := p.distance_to(Vector2(knob_x, h * 0.5))
			if kd < r - 5.0:
				col = CREAM
			img.set_pixel(x, y, Color(col.r, col.g, col.b, a))
	return ImageTexture.create_from_image(img)
