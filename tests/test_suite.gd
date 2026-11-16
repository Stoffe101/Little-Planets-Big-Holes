class_name TestSuite
extends Node
## Minimal test-suite base: assertion helpers plus utilities for booting a World headlessly.
## Methods named test_* are discovered and awaited by tests/run_tests.gd.

var failures: Array[String] = []
var checks := 0
var current_test := ""


func before_all() -> void:
	pass


func after_all() -> void:
	pass


func _fail(msg: String) -> void:
	failures.append("%s: %s" % [current_test, msg])


func assert_true(cond: bool, msg := "expected true") -> bool:
	checks += 1
	if not cond:
		_fail(msg)
	return cond


func assert_false(cond: bool, msg := "expected false") -> bool:
	return assert_true(not cond, msg)


func assert_eq(a: Variant, b: Variant, msg := "") -> bool:
	checks += 1
	if a != b:
		_fail("%s (got %s, expected %s)" % [msg, str(a), str(b)])
		return false
	return true


func assert_near(a: float, b: float, eps: float, msg := "") -> bool:
	checks += 1
	if absf(a - b) > eps:
		_fail("%s (got %.4f, expected %.4f +/- %.4f)" % [msg, a, b, eps])
		return false
	return true


func assert_gt(a: float, b: float, msg := "") -> bool:
	checks += 1
	if not (a > b):
		_fail("%s (got %s, expected > %s)" % [msg, str(a), str(b)])
		return false
	return true


func assert_lt(a: float, b: float, msg := "") -> bool:
	checks += 1
	if not (a < b):
		_fail("%s (got %s, expected < %s)" % [msg, str(a), str(b)])
		return false
	return true


# ------------------------------------------------------------------ helpers

func physics(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


## Points every save/terrain file at a throw-away directory so tests never touch real saves.
func use_sandbox(dir_name: String, wipe := true) -> void:
	SaveSystem.save_dir = "user://test_sandbox/" + dir_name
	SaveSystem.ensure_dir()
	if wipe:
		SaveSystem.delete_save()


func make_world(planet_id := "pipseed", persist := false) -> World:
	GameState.current_planet = planet_id
	var w := World.new()
	add_child(w)
	w.start(planet_id, persist)
	var guard := 0
	while not w.is_ready and guard < 3600:
		await get_tree().process_frame
		guard += 1
	assert_true(w.is_ready, "world became ready")
	await physics(5)
	return w


func free_world(w: World) -> void:
	if w == null or not is_instance_valid(w):
		return
	w.shutdown()
	w.queue_free()
	await frames(4)


## Stands the player on the ground in a given direction from the planet centre.
func place_player(w: World, dir: Vector3, look := Vector3(0.3, 0.2, 1.0)) -> void:
	var d := dir.normalized()
	w.player.teleport(w.planet.ground_point(d) + d * 0.1, look)
	await physics(20)


func ray(w: World, from: Vector3, to: Vector3, mask := 1) -> Dictionary:
	return w.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, mask))


## Waits until physics collision reflects a terrain edit (meshing is asynchronous).
func wait_until(cond: Callable, max_physics_frames := 240) -> bool:
	for i in max_physics_frames:
		if cond.call():
			return true
		await get_tree().physics_frame
	return false
