class_name LoadingScreen
extends Control
## Full-screen loading card shown while a planet generates.

const TIPS := [
	"Hard ore the shovel can't break is left standing - dig around it and come back with a drill.",
	"Step onto the green-edged pad in front of the Depot to sell your whole backpack at once.",
	"The scanner (Q) lights up ore through solid rock.",
	"Caves have entrances. Look for dark openings on hillsides, marked by stacked-stone cairns.",
	"Crystals don't get dug - they crack, then shatter.",
	"Helper bots carry whatever you leave on the ground to the Depot.",
	"Every planet has a heart at its centre.",
	"Your tunnels are saved. Leave, come back - they'll still be there.",
]

var _bar: ProgressBar
var _title: Label
var _tip: Label
var planet: Planet


func _init() -> void:
	name = "LoadingScreen"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = UiTheme.theme()
	var bg := ColorRect.new()
	bg.color = UiTheme.PANEL_DARK
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	center.add_child(v)
	var head := UiTheme.caps("Descent in progress", 14, UiTheme.ACCENT)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(head)
	_title = UiTheme.label("Landing...", 40, UiTheme.TEXT, true)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_title)
	_bar = UiTheme.bar(520.0, 4.0, UiTheme.ACCENT)
	_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(_bar)
	v.add_child(UiTheme.spacer(false, Vector2(0, 8)))
	_tip = UiTheme.label("", 17, UiTheme.DIM)
	_tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip.custom_minimum_size = Vector2(640, 0)
	v.add_child(_tip)


func begin(planet_name: String, p: Planet) -> void:
	planet = p
	_title.text = "Landing on %s" % planet_name
	_tip.text = TIPS[randi() % TIPS.size()]
	_bar.value = 0.0
	visible = true
	modulate.a = 1.0


func finish() -> void:
	planet = null
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.5)
	tw.tween_callback(func() -> void: visible = false)


func _process(_delta: float) -> void:
	if visible and planet != null and is_instance_valid(planet):
		_bar.value = maxf(_bar.value, planet.load_progress())
