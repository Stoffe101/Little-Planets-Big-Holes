class_name UiTheme
extends RefCounted
## Central look & feel for every menu and HUD element (docs/ART_DIRECTION.md, "UI").
##
## An instrument-panel interface: dark slate surfaces with hairline borders, one amber accent
## for "this is the action", teal for information, green/red only for gain/loss. Flat buttons,
## small corner radii, a DIN-style typeface, generous spacing. No outlines, lips or gradients.

# ---- surfaces
const INK := Color("#0c0f13")           ## darkest: text on amber, deep shadows
const PANEL := Color("#151a20")         ## standard panel
const PANEL_LIGHT := Color("#1e252d")   ## raised card / hover
const PANEL_DARK := Color("#0f1318")    ## recessed well
const LINE := Color(1, 1, 1, 0.09)      ## hairline borders and dividers
# ---- text
const TEXT := Color("#e8ebee")
const DIM := Color("#8c96a3")
const FAINT := Color("#5d6672")
# ---- signal colours (shared with the 3D palette)
const ACCENT := Color("#f0a22e")        ## amber: primary action, selection, "yours"
const INFO := Color("#4cc9bb")          ## teal: information, scanner, energy
const GOOD := Color("#6fcf8e")          ## gain, affordable
const BAD := Color("#e0685a")           ## loss, blocked, full
# ---- legacy names kept so gameplay code keeps compiling; all map onto the palette above
const CREAM := TEXT
const MUTED := DIM
const YELLOW := ACCENT
const ORANGE := Color("#e88a3c")
const PINK := Color("#c9cfd6")
const TEAL := INFO
const SKY := Color("#7fb6d9")
const GREEN := GOOD
const RED := BAD
const PURPLE := Color("#a892d6")

const RADIUS := 6

static var _regular: Font
static var _semibold: Font
static var _bold: Font
static var _caps: Font
static var _theme: Theme

## Typeface: a clean DIN-style grotesque. Resolved from the system (Bahnschrift on Windows, the
## usual sans-serifs elsewhere) with the engine's built-in font as the final fallback, so no
## font file has to be shipped.
const FONT_NAMES: PackedStringArray = ["Bahnschrift", "DIN Alternate", "Inter", "Roboto", "Noto Sans", "DejaVu Sans", "Arial"]


static func _system_font(weight: int) -> Font:
	var f := SystemFont.new()
	f.font_names = FONT_NAMES
	f.font_weight = weight
	f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	f.multichannel_signed_distance_field = false
	f.hinting = TextServer.HINTING_LIGHT
	f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO
	f.oversampling = 0.0
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


## Semi-bold with open tracking, for small upper-case section labels.
static func font_caps() -> Font:
	if _caps == null:
		var v := FontVariation.new()
		v.base_font = _system_font(600)
		v.spacing_glyph = 2
		_caps = v
	return _caps


# ------------------------------------------------------------------ style boxes

## Flat rounded box. `_lip` is accepted for backwards compatibility and ignored.
static func box(color: Color, radius := RADIUS, border := 0, border_color := LINE, _lip := 0, pad := 12) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(radius)
	s.corner_detail = 6
	s.anti_aliasing = true
	if border > 0:
		s.set_border_width_all(border)
		s.border_color = border_color
	s.content_margin_left = pad
	s.content_margin_right = pad
	s.content_margin_top = pad * 0.7
	s.content_margin_bottom = pad * 0.7
	return s


## Standard floating panel: translucent slate, hairline border, soft short shadow.
static func panel_box(color := PANEL, radius := RADIUS + 2, alpha := 0.9, pad := 16) -> StyleBoxFlat:
	var s := box(Color(color.r, color.g, color.b, alpha), radius, 1, LINE, 0, pad)
	s.shadow_color = Color(0, 0, 0, 0.28)
	s.shadow_size = 8
	s.shadow_offset = Vector2(0, 3)
	return s


## Card inside a panel.
static func card_box(color := PANEL_LIGHT, pad := 14) -> StyleBoxFlat:
	return box(color, RADIUS, 1, LINE, 0, pad)


## Small HUD chip: darker, tighter, no shadow.
static func chip_box(alpha := 0.72, pad := 10) -> StyleBoxFlat:
	return box(Color(PANEL_DARK.r, PANEL_DARK.g, PANEL_DARK.b, alpha), RADIUS, 1, Color(1, 1, 1, 0.06), 0, pad)


# ------------------------------------------------------------------ widgets

## Filled button in `color`. Amber (ACCENT) is the primary action; pass PANEL_LIGHT for a
## neutral secondary button.
static func style_button(b: Button, color: Color, font_size := 20, text_color := INK) -> void:
	var light := color.get_luminance() > 0.35
	var fg := text_color if light else TEXT
	var border := Color(1, 1, 1, 0.0) if light else Color(1, 1, 1, 0.14)
	var bw := 0 if light else 1
	b.add_theme_stylebox_override("normal", box(color, RADIUS, bw, border, 0, 18))
	b.add_theme_stylebox_override("hover", box(color.lightened(0.1 if light else 0.06), RADIUS, bw, Color(1, 1, 1, 0.25), 0, 18))
	b.add_theme_stylebox_override("pressed", box(color.darkened(0.12), RADIUS, bw, border, 0, 18))
	b.add_theme_stylebox_override("focus", box(Color(0, 0, 0, 0), RADIUS, 2, Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.8), 0, 18))
	b.add_theme_stylebox_override("disabled", box(Color(1, 1, 1, 0.05), RADIUS, 1, Color(1, 1, 1, 0.06), 0, 18))
	b.add_theme_font_override("font", font_semibold())
	b.add_theme_font_size_override("font_size", font_size)
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(key, fg)
	b.add_theme_color_override("font_disabled_color", FAINT)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


static func button(text: String, color := ACCENT, font_size := 20) -> Button:
	var b := Button.new()
	b.text = text
	style_button(b, color, font_size)
	b.pressed.connect(func() -> void: Audio.play("ui_click", -8.0, 1.0, 0.03))
	b.mouse_entered.connect(func() -> void:
		if not b.disabled:
			Audio.play("ui_hover", -20.0, 1.0, 0.04, 0.03))
	return b


## Neutral secondary button (outlined slate).
static func ghost_button(text: String, font_size := 20) -> Button:
	return button(text, PANEL_LIGHT, font_size)


static func label(text: String, size := 20, color := TEXT, bold := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font_bold() if bold else font_regular())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


## Small upper-case, letter-spaced label for section headings and field names.
static func caps(text: String, size := 14, color := DIM) -> Label:
	var l := Label.new()
	l.text = text.to_upper()
	l.add_theme_font_override("font", font_caps())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


## Label for text drawn directly over the 3D world: a thin dark edge and a soft drop shadow
## keep it readable on grass, sky and rock without a heavy outline.
static func hud_label(text: String, size := 22, color := TEXT) -> Label:
	var l := label(text, size, color, false)
	l.add_theme_font_override("font", font_semibold())
	l.add_theme_constant_override("outline_size", 4)
	l.add_theme_color_override("font_outline_color", Color(0.03, 0.04, 0.05, 0.55))
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.45))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.add_theme_constant_override("shadow_outline_size", 3)
	return l


## Thin progress bar (used for backpack, objectives, fuel, cooldowns).
static func bar(width: float, height := 6.0, fill := ACCENT) -> ProgressBar:
	var p := ProgressBar.new()
	p.custom_minimum_size = Vector2(width, height)
	p.show_percentage = false
	p.max_value = 1.0
	p.step = 0.001
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("background", box(Color(1, 1, 1, 0.1), int(height * 0.5), 0, LINE, 0, 0))
	p.add_theme_stylebox_override("fill", box(fill, int(height * 0.5), 0, LINE, 0, 0))
	return p


static func set_bar_color(p: ProgressBar, fill: Color) -> void:
	var h := p.custom_minimum_size.y
	p.add_theme_stylebox_override("fill", box(fill, int(h * 0.5), 0, LINE, 0, 0))


## A row of level pips: `filled` of `total`.
static func pips(total: int, filled: int, color := ACCENT, size := Vector2(18, 4)) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 3)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in total:
		var pip := Panel.new()
		pip.custom_minimum_size = size
		pip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pip.add_theme_stylebox_override("panel", box(color if i < filled else Color(1, 1, 1, 0.12), 2, 0, LINE, 0, 0))
		h.add_child(pip)
	return h


static func divider() -> Control:
	var c := ColorRect.new()
	c.color = LINE
	c.custom_minimum_size = Vector2(0, 1)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


static func spacer(expand := true, min_size := Vector2.ZERO) -> Control:
	var c := Control.new()
	c.custom_minimum_size = min_size
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if expand:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return c


# ------------------------------------------------------------------ theme

static func theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font = font_regular()
	t.default_font_size = 20
	t.set_color("font_color", "Label", TEXT)
	t.set_stylebox("panel", "PanelContainer", panel_box())
	t.set_stylebox("panel", "Panel", panel_box())
	# progress bars
	t.set_stylebox("background", "ProgressBar", box(Color(1, 1, 1, 0.1), 3, 0, LINE, 0, 0))
	t.set_stylebox("fill", "ProgressBar", box(ACCENT, 3, 0, LINE, 0, 0))
	t.set_font_size("font_size", "ProgressBar", 14)
	# sliders
	var groove := box(Color(1, 1, 1, 0.12), 2, 0, LINE, 0, 0)
	groove.content_margin_top = 2
	groove.content_margin_bottom = 2
	t.set_stylebox("slider", "HSlider", groove)
	var fill := box(ACCENT, 2, 0, LINE, 0, 0)
	fill.content_margin_top = 2
	fill.content_margin_bottom = 2
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)
	var knob := _circle_texture(18, TEXT)
	t.set_icon("grabber", "HSlider", knob)
	t.set_icon("grabber_highlight", "HSlider", _circle_texture(18, ACCENT))
	t.set_icon("grabber_disabled", "HSlider", knob)
	# check buttons
	t.set_font_size("font_size", "CheckButton", 20)
	t.set_color("font_color", "CheckButton", TEXT)
	t.set_color("font_hover_color", "CheckButton", TEXT)
	t.set_color("font_pressed_color", "CheckButton", TEXT)
	t.set_icon("checked", "CheckButton", _toggle_texture(true))
	t.set_icon("unchecked", "CheckButton", _toggle_texture(false))
	t.set_stylebox("focus", "CheckButton", StyleBoxEmpty.new())
	# scroll bars
	var sb := box(Color(1, 1, 1, 0.04), 3, 0, LINE, 0, 0)
	sb.content_margin_left = 3; sb.content_margin_right = 3
	t.set_stylebox("scroll", "VScrollBar", sb)
	t.set_stylebox("grabber", "VScrollBar", box(Color(1, 1, 1, 0.22), 3, 0, LINE, 0, 0))
	t.set_stylebox("grabber_highlight", "VScrollBar", box(Color(1, 1, 1, 0.38), 3, 0, LINE, 0, 0))
	t.set_stylebox("grabber_pressed", "VScrollBar", box(ACCENT, 3, 0, LINE, 0, 0))
	# tooltips
	t.set_stylebox("panel", "TooltipPanel", box(PANEL_DARK, 4, 1, LINE, 0, 8))
	t.set_color("font_color", "TooltipLabel", TEXT)
	t.set_font_size("font_size", "TooltipLabel", 16)
	# rich text
	t.set_font("normal_font", "RichTextLabel", font_regular())
	t.set_font("bold_font", "RichTextLabel", font_bold())
	t.set_font_size("normal_font_size", "RichTextLabel", 18)
	t.set_font_size("bold_font_size", "RichTextLabel", 18)
	t.set_color("default_color", "RichTextLabel", TEXT)
	_theme = t
	return t


static func _circle_texture(size: int, fill: Color) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := Vector2(size, size) * 0.5
	var r := size * 0.5 - 1.0
	for y in size:
		for x in size:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(c)
			img.set_pixel(x, y, Color(fill.r, fill.g, fill.b, clampf(r - d + 0.5, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)


static func _toggle_texture(on: bool) -> ImageTexture:
	var w := 44
	var h := 24
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var track := ACCENT if on else Color(0.3, 0.33, 0.38)
	var knob_x := float(w - h * 0.5) if on else h * 0.5
	for y in h:
		for x in w:
			var p := Vector2(x + 0.5, y + 0.5)
			var cx := clampf(p.x, h * 0.5, w - h * 0.5)
			var d := p.distance_to(Vector2(cx, h * 0.5))
			var r := h * 0.5 - 1.0
			var a := clampf(r - d + 0.5, 0.0, 1.0)
			var col := track
			var kd := p.distance_to(Vector2(knob_x, h * 0.5))
			if kd < r - 3.0:
				col = TEXT if not on else INK
			img.set_pixel(x, y, Color(col.r, col.g, col.b, a))
	return ImageTexture.create_from_image(img)
