class_name LoadingScreen
extends Control
## Full-screen loading card shown while a planet generates.

const TIPS := [
	"Hard ore the shovel can't break is left standing - dig around it and come back with a drill.",
	"Step onto the green Sell-o-Matic pad to sell your whole backpack at once.",
	"The scanner (Q) lights up ore through solid rock.",
	"Caves have entrances. Look for dark openings on hillsides.",
	"Crystals don't get dug - they crack, then shatter.",
	"Helper bots carry whatever you leave on the ground to the Sell-o-Matic.",
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
	bg.color = Color("#1b1538")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 18)
	center.add_child(v)
	var icon := UiIcon.make("planet", UiTheme.GREEN, 150)
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(icon)
	_title = UiTheme.label("Landing...", 56, UiTheme.YELLOW, true)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_title)
	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(620, 30)
	_bar.show_percentage = false
	_bar.max_value = 1.0
	_bar.step = 0.001
	v.add_child(_bar)
	_tip = UiTheme.label("", 24, UiTheme.MUTED)
	_tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip.custom_minimum_size = Vector2(760, 0)
	v.add_child(_tip)


func begin(planet_name: String, p: Planet) -> void:
	planet = p
	_title.text = "Landing on %s..." % planet_name
	_tip.text = "Tip: " + TIPS[randi() % TIPS.size()]
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
