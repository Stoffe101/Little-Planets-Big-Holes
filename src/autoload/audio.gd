extends Node
## Sound playback: pooled one-shots with pitch/volume variation, named loops, and music.
## Sounds are original procedurally-synthesised WAVs in res://assets/audio (see tools/gen_audio.py).
## Variations are files named <name>_1.wav, <name>_2.wav ...; a random one (never the same twice
## in a row) is chosen per play.
## Autoload name: Audio

const DIR := "res://assets/audio/"
const POOL_SIZE := 20
const POOL_3D_SIZE := 10

var _sounds: Dictionary = {}          ## name -> Array[AudioStream]
var _last_variant: Dictionary = {}
var _pool: Array[AudioStreamPlayer] = []
var _pool_3d: Array[AudioStreamPlayer3D] = []
var _next := 0
var _next_3d := 0
var _loops: Dictionary = {}           ## name -> AudioStreamPlayer
var _loop_target: Dictionary = {}     ## name -> {on: bool, pitch: float, volume: float}
var _music: AudioStreamPlayer
var _last_play_ms: Dictionary = {}
var enabled := true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_bus("SFX")
	_ensure_bus("Music")
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_pool.append(p)
	for i in POOL_3D_SIZE:
		var p3 := AudioStreamPlayer3D.new()
		p3.bus = "SFX"
		p3.unit_size = 6.0
		p3.max_distance = 60.0
		p3.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(p3)
		_pool_3d.append(p3)
	_music = AudioStreamPlayer.new()
	_music.bus = "Music"
	add_child(_music)
	_scan()
	Settings.apply_all()


func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) < 0:
		AudioServer.add_bus()
		var idx := AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, bus_name)
		AudioServer.set_bus_send(idx, "Master")


func _scan() -> void:
	_sounds.clear()
	var dir := DirAccess.open(DIR)
	if dir == null:
		return
	var files := dir.get_files()
	files.sort()
	for file in files:
		var f := file
		# Exported builds list "<name>.wav.import"; map back to the resource path.
		if f.ends_with(".import"):
			f = f.trim_suffix(".import")
		if not (f.ends_with(".wav") or f.ends_with(".ogg")):
			continue
		var base := f.get_basename()
		var key := base
		var us := base.rfind("_")
		if us > 0 and base.substr(us + 1).is_valid_int():
			key = base.substr(0, us)
		var stream: AudioStream = load(DIR + f)
		if stream == null:
			continue
		# Loop points are set here rather than through import settings so the repo needs no .import tweaks.
		if stream is AudioStreamWAV and (key.ends_with("_loop") or key == "jetpack"):
			var wav := stream as AudioStreamWAV
			wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
			wav.loop_begin = 0
			wav.loop_end = int(wav.get_length() * float(wav.mix_rate))
		elif stream is AudioStreamOggVorbis:
			(stream as AudioStreamOggVorbis).loop = true
		if not _sounds.has(key):
			_sounds[key] = []
		if not (_sounds[key] as Array).has(stream):
			(_sounds[key] as Array).append(stream)


func has_sound(sound: String) -> bool:
	return _sounds.has(sound)


func _pick(sound: String) -> AudioStream:
	var list: Array = _sounds.get(sound, [])
	if list.is_empty():
		return null
	var i := randi() % list.size()
	if list.size() > 1 and i == int(_last_variant.get(sound, -1)):
		i = (i + 1) % list.size()
	_last_variant[sound] = i
	return list[i]


## Plays a one-shot. `pitch_var` is a +/- random range; `min_interval` (seconds) drops repeats
## that would otherwise stack into a harsh buzz.
func play(sound: String, volume_db := 0.0, pitch := 1.0, pitch_var := 0.06, min_interval := 0.0) -> void:
	if not enabled:
		return
	if min_interval > 0.0:
		var now := Time.get_ticks_msec()
		if now - int(_last_play_ms.get(sound, -100000)) < int(min_interval * 1000.0):
			return
		_last_play_ms[sound] = now
	var stream := _pick(sound)
	if stream == null:
		return
	var p := _pool[_next]
	_next = (_next + 1) % POOL_SIZE
	p.stream = stream
	p.volume_db = volume_db
	p.pitch_scale = maxf(0.05, pitch + randf_range(-pitch_var, pitch_var))
	p.play()


func play_at(sound: String, pos: Vector3, volume_db := 0.0, pitch := 1.0, pitch_var := 0.06) -> void:
	if not enabled:
		return
	var stream := _pick(sound)
	if stream == null:
		return
	var p := _pool_3d[_next_3d]
	_next_3d = (_next_3d + 1) % POOL_3D_SIZE
	p.stream = stream
	p.volume_db = volume_db
	p.pitch_scale = maxf(0.05, pitch + randf_range(-pitch_var, pitch_var))
	p.global_position = pos
	p.play()


## Turns a named looping sound on/off with smooth fades (drill, vacuum, jetpack ...).
func set_loop(sound: String, on: bool, pitch := 1.0, volume_db := 0.0) -> void:
	if not _sounds.has(sound):
		return
	if not _loops.has(sound):
		if not on:
			return
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		p.stream = (_sounds[sound] as Array)[0]
		p.volume_db = -60.0
		add_child(p)
		_loops[sound] = p
	_loop_target[sound] = {"on": on, "pitch": pitch, "volume": volume_db}


func stop_all_loops() -> void:
	for sound: String in _loop_target:
		_loop_target[sound]["on"] = false


func _process(delta: float) -> void:
	for sound: String in _loops:
		var p: AudioStreamPlayer = _loops[sound]
		var t: Dictionary = _loop_target.get(sound, {"on": false, "pitch": 1.0, "volume": 0.0})
		var target_db: float = float(t["volume"]) if (t["on"] and enabled) else -60.0
		p.volume_db = move_toward(p.volume_db, target_db, delta * (240.0 if t["on"] else 160.0))
		p.pitch_scale = lerpf(p.pitch_scale, float(t["pitch"]), minf(1.0, delta * 8.0))
		if t["on"] and not p.playing and enabled:
			p.play()
		elif not t["on"] and p.playing and p.volume_db <= -59.0:
			p.stop()


func play_music(track: String, volume_db := -8.0) -> void:
	var stream := _pick(track)
	if stream == null:
		return
	if _music.stream == stream and _music.playing:
		return
	_music.stream = stream
	_music.volume_db = volume_db
	if enabled:
		_music.play()


func stop_music() -> void:
	_music.stop()
