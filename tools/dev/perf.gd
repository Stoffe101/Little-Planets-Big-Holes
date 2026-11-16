class_name DevPerf
extends Node
## Dev tool: frame-time benchmark with the real renderer (run it through tools/perf.sh so it
## uses the off-desktop GPU window). V-sync is disabled; each scenario is warmed up, then
## sampled, and reports average FPS, frame-time percentiles and the renderer's own CPU/GPU
## split for the main viewport. On the streamed planets it also measures what streaming costs:
## a sprint + jetpack traversal, a 300 m relay jump (the frames right after arriving), load time,
## memory, video memory and how long saving terrain edits takes.
##
##   <godot> --path . --resolution 2560x1440 [--rendering-method forward_plus] res://tools/dev/perf.tscn -- [planet] [only=a,b] [off=x,y]
##
## only=  run just these scenarios (surface, base, digging, cannon, cave, bots, traverse, relay,
##        travel)
## off=   A/B attribution: switch systems off for the whole run (props, hud, audio, secrets, nav,
##        contracts, robots, pickups, tools, scanner, base, worldproc, planetproc, shadows, sky,
##        player_physics). Never use these numbers as the game's performance.
## With --remote-debug (tools/profile.sh) every scenario is announced to the profiler host.

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
var _only: PackedStringArray = []
var _off: PackedStringArray = []


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var pid: String = args[0] if args.size() > 0 and not args[0].contains("=") else "pipseed"
	for a in args:
		if a.begins_with("only="):
			_only = a.substr(5).split(",")
		elif a.begins_with("off="):
			_off = a.substr(4).split(",")
	SaveSystem.save_dir = "user://dev_perf"
	SaveSystem.ensure_dir()
	SaveSystem.delete_save()
	exact_window()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	GameState.reset()
	GameState.current_planet = pid
	world = World.new()
	add_child(world)
	var t_start := Time.get_ticks_msec()
	world.start(pid, true)
	await world.ready_to_play
	var ready_ms := Time.get_ticks_msec() - t_start
	var hud := Hud.new()
	add_child(hud)
	hud.setup(world)
	if not _off.is_empty():
		_switch_off(hud)
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	var size := get_viewport().get_visible_rect().size
	print("== perf: %s  renderer=%s  viewport=%dx%d  window=%s  gpu=%s" % [pid, RenderingServer.get_current_rendering_method(),
		int(size.x), int(size.y), str(DisplayServer.window_get_size()), RenderingServer.get_video_adapter_name()])
	print("voxel engine: %d threads, main-thread budget %s ms, threaded graphics resources %s" % [VoxelEngine.get_thread_count(),
		str(ProjectSettings.get_setting("voxel/threads/main/time_budget_ms", "?")), str(VoxelEngine.get_threaded_graphics_resource_building_enabled())])
	print("load: terrain ready (spawn colliders) %d ms, world ready (props, outpost...) %d ms, geology bake %d ms (cache %s)" % [
		world.planet.load_time_ms, ready_ms, world.planet.geology.bake_ms, str(world.planet.geology.bake_from_cache)])
	await _settle()
	_memory("after arrival")
	_rows.append("%-26s %8s %8s %8s %8s %8s %8s %7s %8s" % ["scenario", "avg fps", "avg ms", "p95 ms", "p99 ms", "max ms", "cpu ms", "gpu ms", "draws"])
	for sc in ["surface", "base", "digging", "cannon", "cave", "bots", "traverse", "relay", "travel"]:
		if _only.is_empty() or _only.has(sc):
			await call("_scenario_" + ("relay_jump" if sc == "relay" else sc))
	for r in _rows:
		print(r)
	_memory("end of run")
	var t0 := Time.get_ticks_msec()
	var ok := world.save_all(true)
	var db := ProjectSettings.globalize_path(SaveSystem.terrain_db_path(pid))
	print("save: progress + all terrain edits %d ms (ok %s), terrain database %.1f KB" % [Time.get_ticks_msec() - t0, str(ok), float(FileAccess.get_file_as_bytes(db).size()) / 1024.0])
	SaveSystem.delete_save()
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


## Tells the profiler host (tools/profile.sh) which scenario the following frames belong to.
static func mark(label: String) -> void:
	if EngineDebugger.is_active():
		EngineDebugger.send_message("perf:mark", [label])


func _reset_sample() -> void:
	_frame_usec.clear()
	_cpu_ms = 0.0; _gpu_ms = 0.0; _draws = 0.0; _prims = 0.0


func _measure(label: String) -> void:
	await _frames(WARMUP)
	_reset_sample()
	mark(label)
	_sampling = true
	await _frames(SAMPLES)
	_sampling = false
	mark("(between scenarios)")
	_row(label)
	_voxel_stats(label)


## The terrain's own main-thread timing (Voxel Tools statistics, microseconds of the last update).
func _voxel_stats(label: String) -> void:
	var st: Dictionary = world.planet.terrain.get_statistics()
	var tk: Dictionary = VoxelEngine.get_stats().get("tasks", {})
	print("primitives [%s]: %.0f per frame (all passes, shadows included)" % [label, _prims / float(maxi(1, _frame_usec.size()))])
	print("voxel stats [%s]: %s | tasks %s | threaded_update %s" % [label, str(st), str(tk), str(world.planet.terrain.threaded_update_enabled)])


func _row(label: String) -> void:
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
	_rows.append("%-26s %8.0f %8.2f %8.2f %8.2f %8.2f %8.2f %7.2f %8.0f" % [label, 1000.0 / avg_ms, avg_ms, p95, p99, mx,
		_cpu_ms / float(n), _gpu_ms / float(n), _draws / float(n)])


func _memory(label: String) -> void:
	var st: Dictionary = VoxelEngine.get_stats()
	var pools: Dictionary = st.get("memory_pools", {})
	print("memory (%s): static %.0f MB, video %.0f MB, voxel blocks in use %.0f MB, data blocks %d, mesh blocks %d, props %d" % [label,
		OS.get_static_memory_usage() / 1048576.0, Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
		float(pools.get("voxel_used", 0)) / 1048576.0, world.planet.terrain.debug_get_data_block_count(), world.planet.terrain.debug_get_mesh_block_count(),
		int(world.props.get("prop_count"))])


## Waits for the voxel engine to finish generating and meshing (max 15 s).
func _settle() -> void:
	var t0 := Time.get_ticks_msec()
	var quiet := 0
	while Time.get_ticks_msec() - t0 < 15000 and quiet < 10:
		await get_tree().process_frame
		var tk: Dictionary = VoxelEngine.get_stats()["tasks"]
		quiet = quiet + 1 if int(tk["meshing"]) + int(tk["generation"]) + int(tk["streaming"]) == 0 else 0


func _place(dir: Vector3, look := Vector3(1, 0, 0.3), pitch := -8.0) -> void:
	var d := dir.normalized()
	var p := d * (world.planet.geology.surface_radius(d) + 1.0)
	world.player.teleport(p, look)
	var t0 := Time.get_ticks_msec()
	while not world.planet.is_area_ready(p, 6.0) and Time.get_ticks_msec() - t0 < 20000:
		await get_tree().process_frame
	await _settle()
	world.player.teleport(world.planet.ground_point(d) + d * 0.1, look)
	world.props.call("update_now", world.player.global_position)
	world.player.pitch = deg_to_rad(pitch)
	await _frames(20)


func _scenario_surface() -> void:
	# on the shoulder of the tallest dome, looking out over the planet
	var top := Vector3.ZERO
	var best := -1.0
	for f in world.planet.geology.features:
		if str(f["type"]) == "dome" and float(f["height"]) > best:
			best = float(f["height"])
			top = f["dir"]
	var shoulder := (top + (world.planet.geology.landing_dir - top) * 0.25).normalized()
	await _place(shoulder, world.planet.geology.landing_dir - shoulder, -4.0)
	await _measure("vista from a mountain")


func _scenario_base() -> void:
	var b: Node3D = world.base
	var o: Vector3 = b.get("origin")
	var f: Basis = b.get("frame")
	await _place((o + f.x * 3.0 + f.z * 12.0).normalized(), -f.z)
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
			var stand := cc - (c["dir"] as Vector3) * (float(c["radius"]) - 2.2)
			world.player.teleport(stand, Vector3(1, 0, 0))
			var t0 := Time.get_ticks_msec()
			while not world.planet.is_area_ready(stand, 6.0) and Time.get_ticks_msec() - t0 < 20000:
				await get_tree().process_frame
			await _settle()
			world.player.teleport(stand, Vector3(1, 0, 0))
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


## Sprinting with the best boots and the jetpack straight across country for the whole sample:
## terrain, colliders and props stream in ahead of the player while measuring.
func _scenario_traverse() -> void:
	GameState.gear_levels["boots"] = GameState.gear_max_level("boots")
	GameState.gear_levels["jets"] = GameState.gear_max_level("jets")
	await _place((world.planet.geology.landing_dir + Vector3(0.0, 0.0, -0.1)).normalized(), Vector3(0.2, 0, -1), -6.0)
	world.player.forced_move = Vector2(0, 1)
	world.player.forced_sprint = true
	var hop := create_tween().set_loops()
	hop.tween_interval(0.9)
	hop.tween_callback(func() -> void: world.player.forced_jump = true)
	var start := world.player.global_position
	await _measure("sprint+jets traversal")
	hop.kill()
	world.player.forced_move = Vector2.INF
	world.player.forced_sprint = false
	print("traversal covered %.0f m (warm-up + sample)" % start.distance_to(world.player.global_position))


## A 300 m relay jump: the frames right after arriving (no warm-up), while the new area streams.
func _scenario_relay_jump() -> void:
	var p := world.player
	var d := (p.global_position.normalized() + p.global_basis.x * (300.0 / world.planet.geology.radius)).normalized()
	_reset_sample()
	mark("300 m relay jump (240 f)")
	p.teleport(d * (world.planet.geology.surface_radius(d) + 1.2), Vector3.FORWARD)
	var t0 := Time.get_ticks_msec()
	_sampling = true
	var ready_ms := -1
	for i in 240:
		await get_tree().process_frame
		if ready_ms < 0 and world.planet.is_area_ready(p.global_position, 3.0):
			ready_ms = Time.get_ticks_msec() - t0
	_sampling = false
	mark("(between scenarios)")
	_row("300 m relay jump (240 f)")
	print("relay jump: ground with colliders ready after %d ms" % ready_ms)


## Relay travel as the player gets it: the same kind of 300 m jump, but through the transit card
## (TransitOverlay). Reports how long the card covered the view and the frames the player
## actually sees after it fades (the fade itself included).
func _scenario_travel() -> void:
	var transit: Variant = world.get("transit")    # absent before pass 3.1 (perf runs on old commits too)
	if transit == null:
		return
	var p := world.player
	var d := (p.global_position.normalized() - p.global_basis.x * (300.0 / world.planet.geology.radius)).normalized()
	var target := d * (world.planet.geology.surface_radius(d) + 1.2)
	p.teleport(target, Vector3.FORWARD)
	transit.call("begin", target, "perf")
	var t0 := Time.get_ticks_msec()
	_reset_sample()
	mark("relay travel: behind the transit card")
	_sampling = true
	while transit.call("holding"):
		await get_tree().process_frame
	_sampling = false
	var hidden := _frame_usec.size()
	var hidden_max := 0.0
	for v: int in _frame_usec:
		hidden_max = maxf(hidden_max, float(v) / 1000.0)
	var hold_ms := Time.get_ticks_msec() - t0
	_reset_sample()
	mark("relay travel: visible (240 f)")
	_sampling = true
	await _frames(240)
	_sampling = false
	mark("(between scenarios)")
	_row("travel, visible (240 f)")
	print("relay travel: transit card held %d ms (%d frames, longest %.1f ms, all hidden); player can move after it" % [hold_ms, hidden, hidden_max])


## A/B attribution only: switches whole systems off so their share of the frame shows up as the
## difference to a normal run. The game is not meant to work like this.
func _switch_off(hud: Node) -> void:
	print("A/B: switched off ", _off)
	var nodes := {"props": world.props, "secrets": world.secrets, "nav": world.nav, "contracts": world.contracts,
		"robots": world.robots, "pickups": world.pickups, "tools": world.tools, "scanner": world.scanner,
		"base": world.base, "hud": hud, "borer": world.borer}
	for k: String in _off:
		if nodes.has(k) and nodes[k] != null:
			var n: Node = nodes[k]
			n.process_mode = Node.PROCESS_MODE_DISABLED
			if n is Node3D:
				(n as Node3D).visible = false
			elif n is CanvasLayer:
				(n as CanvasLayer).visible = false
	if _off.has("audio"):
		Audio.process_mode = Node.PROCESS_MODE_DISABLED
	if _off.has("worldproc"):
		world.set_process(false)
	if _off.has("planetproc"):
		world.planet.set_process(false)
	if _off.has("shadows"):
		world.sun.shadow_enabled = false
	if _off.has("sky_realtime"):
		world.environment.sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	if _off.has("sky_radiance"):
		world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		world.environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	if _off.has("glow"):
		world.environment.glow_enabled = false
	if _off.has("msaa"):
		get_viewport().msaa_3d = Viewport.MSAA_DISABLED
	if _off.has("sky_update"):
		world.set_process(false)
	if _off.has("render"):
		RenderingServer.render_loop_enabled = false
	if _off.has("draw3d"):
		get_viewport().disable_3d = true
	if _off.has("terrain_draw"):
		world.planet.terrain.visible = false
	if _off.has("player_physics"):
		world.player.set_physics_process(false)
