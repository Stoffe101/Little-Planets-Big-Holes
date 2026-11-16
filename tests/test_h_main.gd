extends TestSuite
## Application flow through the real main scene: menu -> new game -> play -> shop -> menu -> continue.


func test_main_scene_boots_plays_and_returns_to_menu() -> void:
	use_sandbox("main")
	GameState.reset()
	var scene: PackedScene = load("res://scenes/main.tscn")
	assert_true(scene != null, "main scene loads")
	var main: Node = scene.instantiate()
	add_child(main)
	await frames(5)
	assert_eq(int(main.get("mode")), 0, "starts in the menu")
	assert_true((main.get("menu") as Control).visible, "menu visible")

	main.call("start_game", true)
	var playing := await wait_until(func() -> bool: return int(main.get("mode")) == 2, 3600)
	assert_true(playing, "reaches gameplay")
	var world: World = main.get("world")
	assert_true(world != null and world.is_ready, "world ready")
	assert_true(main.get("hud") != null, "hud created")
	assert_true(SaveSystem.has_save(), "a save exists as soon as the game starts")
	await physics(30)
	assert_true(world.player.is_on_floor(), "player standing")

	# shop opens from the kiosk interaction and locks the controls
	main.call("_on_interact", "tools")
	await frames(3)
	var shop: ShopUi = main.get("shop")
	assert_true(shop.visible, "shop visible")
	assert_true(world.player.controls_locked, "controls locked while shopping")
	GameState.add_money(500)
	await frames(3)
	assert_true(GameState.buy_next_tier("shovel"), "buy through game state while the shop is open")
	await frames(3)
	shop.close_shop()
	await frames(2)
	assert_false(world.player.controls_locked, "controls released")
	assert_eq(world.tools.family_id, "shovel", "still holding the shovel")

	# travel is refused while the second planet is locked
	main.call("travel_to", "glimmerock")
	await frames(3)
	assert_eq(GameState.current_planet, "pipseed", "cannot fly to a locked planet")

	main.call("return_to_menu")
	await frames(6)
	assert_eq(int(main.get("mode")), 0, "back in the menu")
	assert_true(main.get("world") == null, "world unloaded")

	# continue restores the purchase
	GameState.reset()
	main.call("start_game", false)
	playing = await wait_until(func() -> bool: return int(main.get("mode")) == 2, 3600)
	assert_true(playing, "continue reaches gameplay")
	assert_eq(GameState.tier_of("shovel"), 2, "purchase persisted across sessions")
	main.call("return_to_menu")
	await frames(6)
	main.queue_free()
	await frames(3)
