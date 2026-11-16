extends Node
## Dev tool: cross-version save check. "write" (run it in a checkout of the OLD version) makes a
## save with progress and a set of holes; "check" (run in the NEW version) loads that save
## and verifies progress and every hole, plus untouched ground nearby. The terrain database is
## per data block (16 voxels), independent of mesh block size and caching, so holes made by
## 0.3.0 must survive in later builds of the same terrain generation.
##
##   <godot> --headless --path <checkout> res://tools/dev/savecompat.tscn -- write|check <absolute dir>

const PLANET := "pipseed"
const SPOTS := [[0.10, 0.0, 0.0], [0.0, 0.0, 0.12], [-0.07, 0.0, 0.08], [0.05, 0.0, -0.11]]   ## offsets from landing dir
const RADIUS := 2.2


func _ready() -> void:
	_run.call_deferred()


func _spots(geo: Geology) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for o: Array in SPOTS:
		var d := (geo.landing_dir + Vector3(o[0], o[1], o[2])).normalized()
		out.append(d)
	return out


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var mode: String = args[0] if args.size() > 0 else "check"
	var dir: String = args[1] if args.size() > 1 else OS.get_user_data_dir() + "/savecompat"
	Audio.enabled = false
	SaveSystem.save_dir = dir
	SaveSystem.ensure_dir()
	var ok := true
	if mode == "write":
		SaveSystem.delete_save()
		GameState.reset()
		GameState.current_planet = PLANET
		GameState.money = 12345
	else:
		ok = SaveSystem.load_game()
		print("savecompat: load_game ", ok, ", money ", GameState.money)
	var w := World.new()
	add_child(w)
	w.start(PLANET, true)
	await w.ready_to_play
	var geo := w.planet.geology
	var fails := 0
	var report: Array[String] = []
	for d in _spots(geo):
		var surface := d * geo.surface_radius(d)
		w.player.teleport(surface + d * 2.0, Vector3.FORWARD)
		var t0 := Time.get_ticks_msec()
		while not w.planet.is_area_ready(surface, 6.0) and Time.get_ticks_msec() - t0 < 20000:
			await get_tree().process_frame
		var c := surface - d * 1.0
		if mode == "write":
			var res := w.dig.dig_sphere(c, RADIUS, 9)
			report.append("dug %s ok=%s" % [str(d), str(res["ok"])])
		else:
			var hole := w.planet.sdf_at(c)
			var beside := w.planet.sdf_at(c + d.cross(Vector3.UP).normalized() * (RADIUS + 3.0) - d * 1.5)
			var good := hole > 0.0 and beside < 0.0
			if not good:
				fails += 1
			report.append("hole %s: sdf %.2f (air expected), ground beside %.2f (solid expected) -> %s" % [str(d), hole, beside, "OK" if good else "FAIL"])
	for line in report:
		print("savecompat: ", line)
	if mode == "write":
		print("savecompat: save ", w.save_all(true), " -> ", dir)
	else:
		if GameState.money != 12345:
			fails += 1
			print("savecompat: FAIL money ", GameState.money)
		print("savecompat: %s (%d failures)" % ["PASS" if fails == 0 and ok else "FAIL", fails])
	w.shutdown()
	get_tree().quit(0 if fails == 0 else 1)
