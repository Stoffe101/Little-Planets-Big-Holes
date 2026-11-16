class_name TransitOverlay
extends CanvasLayer
## Relay transit: covers the view while the destination of a relay jump / recall streams in.
##
## A long jump moves the terrain viewer hundreds of metres at once. Voxel Tools then drops the
## old area and meshes the new one; the first frames after the jump are long main-thread frames
## (measured 35-50 ms with 32-voxel mesh blocks, docs/TECHNICAL.md) and the ground has no
## colliders for ~1.5-2.5 s. Instead of showing that, the view cuts to a transit card in the
## same frame as the jump (the half-loaded destination is never drawn), stays covered until the
## ground at the destination is collidable and the bulk of the meshing is done, then fades in.
## The player is held (`Player.transit_hold`) for the whole transit, so nothing can fall
## through unloaded ground.

signal finished()

const FADE_OUT := 0.45               ## seconds to reveal the destination
const MIN_HOLD := 0.35               ## always show the transit card at least this long
const MAX_HOLD := 6.0                ## never hold longer than this (the ground hold still applies)
const QUIET_MESHING := 40            ## meshing tasks still queued that count as "settled"

var world: World
var active := false
var _rect: ColorRect
var _title: Label
var _sub: Label
var _t := 0.0
var _target := Vector3.ZERO
var _phase := 0                      ## 0 idle, 2 holding, 3 revealing
var hold_seconds := 0.0              ## instrumentation: how long the last transit held
var _snap_pending := false           ## timed out before the ground was ready: snap when it is


func setup(w: World) -> void:
	world = w
	layer = 60
	name = "Transit"
	_rect = ColorRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.color = UiTheme.INK
	add_child(_rect)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	_rect.add_child(box)
	_title = UiTheme.caps("RELAY TRANSIT", 16, UiTheme.INFO)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_title)
	_sub = UiTheme.label("", 30, UiTheme.TEXT, true)
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_sub)
	visible = false
	set_process(false)


## Starts a transit to `target` (the player has already been teleported there).
func begin(target: Vector3, destination_name: String) -> void:
	_target = target
	_sub.text = destination_name
	active = true
	visible = true
	_phase = 2
	_t = 0.0
	hold_seconds = 0.0
	_rect.modulate.a = 1.0
	_snap_pending = false
	if world.player != null:
		world.player.transit_hold = true
	set_process(true)


## True while the transit card fully covers the view (the destination is still streaming).
func holding() -> bool:
	return _phase == 2


## Puts the player on the real ground at the destination (the jump target is computed from the
## analytic surface, which can be off by ~0.5 m or dug away) and gives control back.
func _release() -> void:
	var p := world.player
	if p == null:
		return
	_snap_pending = not _snap()
	p.transit_hold = false


## Snaps the player onto the ground under the jump target if it has streamed in. The ground hold
## (Player.waiting_for_ground) keeps the player in place until then, so a late snap is safe.
func _snap() -> bool:
	var p := world.player
	if not world.planet.is_area_ready(_target, 3.0):
		return false
	var dir := _target.normalized()
	var g := world.planet.ground_point(dir)
	if g.length() > world.planet.geology.core_radius + 1.0 and p.global_position.distance_to(_target) < 1.0:
		p.teleport(g + dir * 0.05, -p.global_basis.z)
	return true


func _settled() -> bool:
	if not world.planet.is_area_ready(_target, 4.0):
		return false
	var tk: Dictionary = VoxelEngine.get_stats().get("tasks", {})
	return int(tk.get("meshing", 0)) <= QUIET_MESHING


func _process(delta: float) -> void:
	# Clamp: the frames right after the jump are long, and a fade should not skip ahead.
	var dt := minf(delta, 1.0 / 30.0)
	_t += dt
	match _phase:
		2:
			_rect.modulate.a = 1.0
			hold_seconds += delta
			if (hold_seconds >= MIN_HOLD and _settled()) or hold_seconds >= MAX_HOLD:
				_phase = 3
				_t = 0.0
				_release()
		3:
			_rect.modulate.a = 1.0 - clampf(_t / FADE_OUT, 0.0, 1.0)
			if _t >= FADE_OUT:
				_phase = 0
				active = false
				visible = false
				set_process(_snap_pending)
				finished.emit()
		0:
			# MAX_HOLD expired before the ground was ready: snap as soon as it is
			if not _snap_pending or _snap():
				_snap_pending = false
				set_process(false)
