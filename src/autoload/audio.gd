extends Node
## Sound playback: pooled one-shots with pitch/volume variation, named loops, and music.
## Sounds are original procedurally-synthesised WAVs in res://assets/audio (see tools/gen_audio.py).
## Variations are files named <name>_1.wav, <name>_2.wav ...; a random one (never the same twice
## in a row) is chosen per play.
## Autoload name: Audio

const DIR := "res://assets/audio/"
const POOL_SIZE := 20
const POOL_3D_SIZE := 10

## Loudness trim per sound (dB), measured by tools/audio_report.py --gains: it brings every
## sound's active level to the same -16 dBFS, so the volume a call site asks for means the same
## thing for every sound. Re-run the report and paste the table after regenerating audio.
const LEVEL := {
	"blip": 3.0, "boom": -7.9, "cannon_fire": -0.7, "clang": 2.8, "collect": -0.5, "collect_gem": -2.1,
	"dig_crystal": 0.6, "dig_hard": 0.1, "dig_ore": 1.1, "dig_soft": -1.5, "dig_stone": 2.6, "discovery": -2.0,
	"drill_loop": -6.9, "equip": 2.5, "heart": -6.2, "hopper": 0.3, "jet_puff": 3.5, "jetpack": 0.9,
	"jump": -0.4, "land": 0.0, "objective": -2.7, "rare": -2.9, "scan": -0.6, "sell": 0.1, "shatter": -0.3,
	"step": 1.7, "swish": -0.5, "thumper_loop": -1.7, "ui_buy": -1.7, "ui_click": 4.9, "ui_close": -0.4,
	"ui_error": -3.2, "ui_hover": 4.2, "ui_open": -0.5, "vacuum_loop": -0.9,
}
## Pitch trim for the brightest effects (measured dominant frequency above ~2.3 kHz). Playing
## them a little lower takes the edge off without regenerating the files.
const SOFTEN := {"shatter": 0.86, "dig_crystal": 0.88, "jet_puff": 0.84, "jetpack": 0.84, "swish": 0.9, "rare": 0.92, "dig_ore": 0.92, "collect_gem": 0.94}
const AMBIENCE_RATE := 22050

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
var _lowpass: AudioEffectLowPassFilter
var _reverb: AudioEffectReverb
var _underground := 0.0
var _ambience: Dictionary = {}        ## name -> AudioStreamPlayer
var _ambience_target: Dictionary = {}  ## name -> volume dB (or -80 = off)


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
	_setup_bus_effects()
	_setup_ambience()
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


## A gentle low-pass keeps the synthesised effects from sounding brittle; underground it closes
## further and a short reverb comes in, so caves sound like enclosed spaces.
func _setup_bus_effects() -> void:
	var idx := AudioServer.get_bus_index("SFX")
	if idx < 0 or AudioServer.get_bus_effect_count(idx) > 0:
		return
	_lowpass = AudioEffectLowPassFilter.new()
	_lowpass.cutoff_hz = 11000.0
	_lowpass.resonance = 0.4
	AudioServer.add_bus_effect(idx, _lowpass)
	_reverb = AudioEffectReverb.new()
	_reverb.room_size = 0.55
	_reverb.damping = 0.65
	_reverb.spread = 0.8
	_reverb.hipass = 0.2
	_reverb.dry = 1.0
	_reverb.wet = 0.0
	AudioServer.add_bus_effect(idx, _reverb)


## 0 on the surface .. 1 deep underground. Called by the World every frame.
func set_underground(amount: float) -> void:
	_underground = clampf(amount, 0.0, 1.0)
	if _lowpass != null:
		_lowpass.cutoff_hz = lerpf(11000.0, 5200.0, _underground)
	if _reverb != null:
		_reverb.wet = lerpf(0.0, 0.2, _underground)


## Ambience is synthesised once at start-up (a few seconds of filtered noise per bed) instead
## of shipping audio files: a soft wind for open ground and a low room tone for caves.
func _setup_ambience() -> void:
	if DisplayServer.get_name() == "headless":
		return
	for bed: Array in [["wind", 420.0, 0.16, 9.0, 911], ["cave", 130.0, 0.05, 7.0, 912]]:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		p.stream = _noise_bed(float(bed[1]), float(bed[2]), float(bed[3]), int(bed[4]))
		p.volume_db = -80.0
		add_child(p)
		_ambience[bed[0]] = p
		_ambience_target[bed[0]] = -80.0


## Loopable filtered noise: white noise through two one-pole low-passes at `cutoff`, with a slow
## swell of depth `swell`, cross-faded over its last half second so the loop joins cleanly.
static func _noise_bed(cutoff: float, swell: float, seconds: float, seed_value: int) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var n := int(seconds * AMBIENCE_RATE)
	var fade := AMBIENCE_RATE / 2
	var a := 1.0 - exp(-TAU * cutoff / float(AMBIENCE_RATE))
	var y1 := 0.0
	var y2 := 0.0
	var buf := PackedFloat32Array()
	buf.resize(n + fade)
	var peak := 0.0001
	for i in n + fade:
		y1 += a * (rng.randf_range(-1.0, 1.0) - y1)
		y2 += a * (y1 - y2)
		var t := float(i) / float(AMBIENCE_RATE)
		var v := y2 * (1.0 - swell + swell * sin(t * TAU / seconds * 2.0) * sin(t * TAU / seconds * 3.0 + 1.0))
		buf[i] = v
		peak = maxf(peak, absf(v))
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var v2 := buf[i]
		if i < fade:
			var k := float(i) / float(fade)
			v2 = buf[i] * k + buf[n + i] * (1.0 - k)
		data.encode_s16(i * 2, int(clampf(v2 / peak, -1.0, 1.0) * 14000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = AMBIENCE_RATE
	wav.stereo = false
	wav.data = data
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = n
	return wav


## Sets the ambience mix: `wind` 0..1 (open air), `cave` 0..1 (enclosed).
func set_ambience(wind: float, cave: float) -> void:
	_ambience_target["wind"] = lerpf(-80.0, -24.0, clampf(wind, 0.0, 1.0)) if wind > 0.01 else -80.0
	_ambience_target["cave"] = lerpf(-80.0, -20.0, clampf(cave, 0.0, 1.0)) if cave > 0.01 else -80.0


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
	p.volume_db = volume_db + float(LEVEL.get(sound, 0.0))
	p.pitch_scale = maxf(0.05, (pitch + randf_range(-pitch_var, pitch_var)) * float(SOFTEN.get(sound, 1.0)))
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
	p.volume_db = volume_db + float(LEVEL.get(sound, 0.0))
	p.pitch_scale = maxf(0.05, (pitch + randf_range(-pitch_var, pitch_var)) * float(SOFTEN.get(sound, 1.0)))
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
	_loop_target[sound] = {"on": on, "pitch": pitch * float(SOFTEN.get(sound, 1.0)), "volume": volume_db + float(LEVEL.get(sound, 0.0))}


func stop_all_loops() -> void:
	for sound: String in _loop_target:
		_loop_target[sound]["on"] = false
	set_ambience(0.0, 0.0)
	set_underground(0.0)


func _process(delta: float) -> void:
	for bed: String in _ambience:
		var ap: AudioStreamPlayer = _ambience[bed]
		var want: float = _ambience_target.get(bed, -80.0) if enabled else -80.0
		ap.volume_db = move_toward(ap.volume_db, want, delta * 30.0)
		if want > -79.0 and not ap.playing:
			ap.play()
		elif want <= -79.0 and ap.playing and ap.volume_db <= -78.0:
			ap.stop()
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
