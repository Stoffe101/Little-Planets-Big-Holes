extends Node
## Headless test runner.
##   godot --headless --path . res://tests/run_tests.tscn            (all suites)
##   godot --headless --path . res://tests/run_tests.tscn -- world   (suites whose file name contains "world")
## Exit code 0 = all passed, 1 = failures.

func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var filters := OS.get_cmdline_user_args()
	var files: Array[String] = []
	var dir := DirAccess.open("res://tests")
	for f in dir.get_files():
		if f.begins_with("test_") and f.ends_with(".gd") and f != "test_suite.gd":
			var wanted := filters.is_empty()
			for flt in filters:
				if f.contains(flt):
					wanted = true
			if wanted:
				files.append(f)
	files.sort()
	Audio.enabled = false
	var total := 0
	var failed := 0
	var checks := 0
	var t_start := Time.get_ticks_msec()
	var all_failures: Array[String] = []
	for f in files:
		var script: GDScript = load("res://tests/" + f)
		if script == null or not script.can_instantiate():
			# a suite that does not compile is a failure, not a hang
			print("\n== %s\n  [FAIL] does not compile" % f)
			total += 1
			failed += 1
			all_failures.append("%s: script failed to load or compile" % f)
			continue
		var suite: TestSuite = script.new()
		suite.name = f.get_basename()
		add_child(suite)
		print("\n== %s" % f)
		await suite.before_all()
		var methods: Array[String] = []
		for m in script.get_script_method_list():
			if str(m["name"]).begins_with("test_"):
				methods.append(str(m["name"]))
		for m in methods:
			suite.current_test = "%s.%s" % [f.get_basename(), m]
			var before := suite.failures.size()
			var t0 := Time.get_ticks_msec()
			await suite.call(m)
			var ok := suite.failures.size() == before
			total += 1
			if not ok:
				failed += 1
			print("  [%s] %s  (%d ms)" % ["PASS" if ok else "FAIL", m, Time.get_ticks_msec() - t0])
			for i in range(before, suite.failures.size()):
				print("         - " + suite.failures[i])
		await suite.after_all()
		checks += suite.checks
		all_failures.append_array(suite.failures)
		suite.queue_free()
		await get_tree().process_frame
	print("\n==================================================")
	print("%d tests, %d failed, %d assertions, %.1f s" % [total, failed, checks, (Time.get_ticks_msec() - t_start) / 1000.0])
	for msg in all_failures:
		print("FAILED: " + msg)
	print("RESULT: %s" % ("OK" if failed == 0 else "FAILURES"))
	get_tree().quit(1 if failed > 0 else 0)
