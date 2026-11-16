extends Node
## Dev tool: frame-time benchmark with the real renderer (run it through tools/perf.sh so it
## uses the off-desktop GPU window). V-sync is disabled; each scenario is warmed up, then
## sampled, and reports average FPS, frame-time percentiles and the renderer's own CPU/GPU
## split for the main viewport.
##
##   <godot> --path . --resolution 2560x1440 [--rendering-method forward_plus] res://tools/dev/perf.tscn -- [planet]

const WARMUP := 90
const SAMPLES := 420

var world: World
var _frame_usec := PackedInt64Array()
var _cpu_ms := 0.0
var _gpu_ms := 0.0
var _draws := 0.0
var _prims := 0.0
var _last := 0
var _sampling := false
var _rows: Array[String] = []


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var pid: String = args[0] if args.size() > 0 else "pipseed"
	SaveSystem.save_dir = "user://dev_perf"
	exact_window()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	GameState.reset()
	GameState.current_planet = pid
	world = World.new()
	add_child(world)
	world.start(pid, false)
	await world.ready_to_play
	var hud := Hud.new()
	add_child(hud)
	hud.setup(world)
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	var size := get_viewport().get_visible_rect().size
	print("== perf: %s  renderer=%s  viewport=%dx%d  window=%s  gpu=%s" % [pid, RenderingServer.get_current_rendering_method(),
		int(size.x), int(size.y), str(DisplayServer.window_get_size()), RenderingServer.get_video_adapter_name()])
	print("%-26s %8s %8s %8s %8s %8s %8s %7s %8s" % ["scenario", "avg fps", "avg ms", "p95 ms", "p99 ms", "max ms", "cpu ms", "gpu ms", "draws"])
	await _scenario_surface()
	await _scenario_base()
	await _scenario_digging()
	await _scenario_cannon()
	await _scenario_cave()
	await _scenario_bots()
	for r in _rows:
		print(r)
	print("done")
	get_tree().quit()


## Dev tools run in a borderless window of exactly the requested --resolution (a decorated
## window is clamped to the work area, which would silently change the pixel count).
static func exact_window() -> void:
	var args := OS.get_cmdline_args()
	var i := args.find("--resolution")
	if i < 0 or i + 1 >= args.size() or DisplayServer.get_name() == "headless":
		return
	var parts := args[i + 1].split("x")
	if parts.size() != 2:
		return
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
	DisplayServer.window_set_size(Vector2i(int(parts[0]), int(parts[1])))
	DisplayServer.window_set_position(Vector2i.ZERO)


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	if _sampling and _last > 0:
		_frame_usec.append(now - _last)
		var vp := get_viewport().get_viewport_rid()
		_cpu_ms += RenderingServer.viewport_get_measured_render_time_cpu(vp) + RenderingServer.get_frame_setup_time_cpu()
		_gpu_ms += RenderingServer.viewport_get_measured_render_time_gpu(vp)
		_draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		_prims += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	_last = now


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _measure(label: String) -> void:
	await _frames(WARMUP)
	_frame_usec.clear()
	_cpu_ms = 0.0; _gpu_ms = 0.0; _draws = 0.0; _prims = 0.0
	_sampling = true
	await _frames(SAMPLES)
	_sampling = false
	var sorted := Array(_frame_usec)
	sorted.sort()
	var n := sorted.size()
	var total := 0
	for v: int in sorted:
		total += v
	var avg_ms := float(total) / float(n) / 1000.0
	var p95 := float(sorted[int(float(n) * 0.95)]) / 1000.0
	var p99 := float(sorted[mini(n - 1, int(float(n) * 0.99))]) / 1000.0
	var mx := float(sorted[n - 1]) / 1000.0
	_rows.append("%-26s %8.0f %8.2f %8.2f %8.2f %8.2f %8.2f %7.2f %8.0f" % [label, 1000.0 / avg_ms, avg_ms, p95, p99, mx, _cpu_ms / float(n), _gpu_ms / float(n), _draws / float(n)])


func _place(dir: Vector3, look := Vector3(1, 0, 0.3), pitch := -8.0) -> void:
	var d := dir.normalized()
	world.player.teleport(world.planet.ground_point(d) + d * 0.1, look)
	world.player.pitch = deg_to_rad(pitch)
	await _frames(20)


func _scenario_surface() -> void:
	await _place(Vector3(0.6, 0.55, 0.55))
	await _measure("surface, looking around")


func _scenario_base() -> void:
	var b: Node3D = world.base
	var o: Vector3 = b.get("origin")
	var f: Basis = b.get("frame")
	world.player.teleport(world.planet.ground_point((o + f.x * 3.0 + f.z * 12.0).normalized()), -f.z)
	await _measure("outpost in view")


func _scenario_digging() -> void:
	GameState.tiers["shovel"] = 3
	GameState.gear_levels["backpack"] = 6
	GameState.tools_changed.emit()
	await _place(Vector3(0.42, 0.85, -0.3), Vector3(1, 0, 0.3), -40.0)
	world.tools.forced_use_enabled = true
	world.tools.forced_use = true
	await _measure("power shovel, held down")
	world.tools.forced_use = false


func _scenario_cannon() -> void:
	await _place(Vector3(-0.3, 0.9, 0.3), Vector3(1, 0, 0.3), -25.0)
	# eight large excavations in a row, one every half second, while measuring
	var up := world.player.up
	var base := world.player.global_position + (-world.player.camera.global_basis.z) * 14.0
	var tw := create_tween()
	for i in 8:
		tw.tween_interval(0.5)
		tw.tween_callback(func() -> void:
			var p := world.planet.ground_point((base + Vector3(i * 2.0, 0, i * 1.3)).normalized())
			var res: Dictionary = world.dig.dig_sphere(p, 6.5, 9)
			world.fx.explosion(p, 6.5, Color("#8a6748"))
			world.pickups.burst(res["yields"], p + up * 2.0, up, 6.5, 16))
	await _measure("8 x 6.5 m blasts + debris")


func _scenario_cave() -> void:
	for c in world.planet.geology.cavities:
		if str(c["cfg"].get("decor", "")) == "crystals":
			var cc: Vector3 = c["center"]
			world.player.teleport(cc - (c["dir"] as Vector3) * (float(c["radius"]) - 2.2), Vector3(1, 0, 0))
			world.player.pitch = 0.2
			break
	await _measure("crystal cavern")


func _scenario_bots() -> void:
	await _place(Vector3(0.2, 0.95, 0.2))
	GameState.discoveries["dormant_bot"] = true
	GameState.gear_levels["robot"] = 3
	GameState.gear_changed.emit("robot")
	world.pickups.magnet_enabled = false
	var up := world.player.up
	for i in 150:
		var off := Vector3(randf_range(-9, 9), 0, randf_range(-9, 9))
		world.pickups.spawn(GameData.mat_index("copper"), 3, world.player.global_position + off + up * 3.0, Vector3.ZERO)
	await _measure("3 bots hauling 150 chunks")
