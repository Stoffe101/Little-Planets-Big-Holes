extends Node
## Application root: title screen <-> gameplay, planet travel, modal screens, pause and quitting.

enum Mode { MENU, LOADING, PLAYING }

var mode := Mode.MENU
var world: World
var hud: Hud
var ui_layer: CanvasLayer
var menu: MainMenu
var backdrop: MenuBackdrop
var loading: LoadingScreen
var shop: ShopUi
var planets_ui: PlanetSelectUi
var journal: JournalUi
var pause_menu: PauseMenu
var _open_screen: Control
var _quitting := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().auto_accept_quit = false
	ui_layer = CanvasLayer.new()
	ui_layer.layer = 10
	ui_layer.name = "UI"
	add_child(ui_layer)

	shop = ShopUi.new()
	ui_layer.add_child(shop)
	shop.closed.connect(_on_screen_closed)
	planets_ui = PlanetSelectUi.new()
	ui_layer.add_child(planets_ui)
	planets_ui.closed.connect(_on_screen_closed)
	planets_ui.travel_requested.connect(travel_to)
	journal = JournalUi.new()
	ui_layer.add_child(journal)
	journal.closed.connect(_on_screen_closed)
	pause_menu = PauseMenu.new()
	ui_layer.add_child(pause_menu)
	pause_menu.resume_requested.connect(_on_pause_closed)
	pause_menu.save_requested.connect(func() -> void:
		if world != null:
			world.save_all(true))
	pause_menu.main_menu_requested.connect(return_to_menu)
	pause_menu.quit_requested.connect(quit_game)

	menu = MainMenu.new()
	ui_layer.add_child(menu)
	menu.continue_requested.connect(func() -> void: start_game(false))
	menu.new_game_requested.connect(func() -> void: start_game(true))
	menu.quit_requested.connect(quit_game)
	loading = LoadingScreen.new()
	loading.visible = false
	ui_layer.add_child(loading)
	show_menu()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		quit_game()


# ------------------------------------------------------------------ menu

func show_menu() -> void:
	mode = Mode.MENU
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if backdrop == null:
		backdrop = MenuBackdrop.new()
		add_child(backdrop)
	menu.visible = true
	menu.refresh()
	Audio.play_music("music_pipseed", -10.0)


func start_game(fresh: bool) -> void:
	if fresh:
		SaveSystem.delete_save()
		GameState.reset()
	else:
		if not SaveSystem.load_game():
			menu.show_notice("Could not read the save (%s). Starting fresh." % SaveSystem.last_error)
			GameState.reset()
		elif SaveSystem.last_load_recovered:
			menu.show_notice("Main save was damaged - restored the backup.")
	_load_world(GameState.current_planet)


func return_to_menu() -> void:
	get_tree().paused = false
	_close_all_screens()
	_unload_world()
	show_menu()


# ------------------------------------------------------------------ world lifecycle

func _unload_world() -> void:
	if hud != null:
		hud.queue_free()
		hud = null
	if world != null:
		world.shutdown()
		world.queue_free()
		world = null


func _load_world(planet_id: String) -> void:
	mode = Mode.LOADING
	menu.visible = false
	_close_all_screens()
	_unload_world()
	if backdrop != null:
		backdrop.queue_free()
		backdrop = null
	# let the old world leave the tree before the new one registers its voxel streams
	await get_tree().process_frame
	await get_tree().process_frame
	world = World.new()
	add_child(world)
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	world.start(planet_id, true)
	loading.begin(str(GameData.planet(planet_id).get("name", planet_id)), world.planet)
	if not world.is_ready:
		await world.ready_to_play
	hud = Hud.new()
	hud.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(hud)
	hud.setup(world)
	if world.base != null:
		world.base.connect("interact_requested", _on_interact)
	loading.finish()
	mode = Mode.PLAYING
	_capture_mouse(true)
	Audio.play_music("music_" + planet_id if Audio.has_sound("music_" + planet_id) else "music_pipseed", -9.0)
	SaveSystem.save_game()


func travel_to(planet_id: String) -> void:
	if world == null or not GameState.can_travel_to(planet_id):
		Audio.play("ui_error", -6.0)
		return
	world.save_all(true)
	if not GameState.travel_to(planet_id):
		return
	Audio.play("cannon_fire", -4.0, 0.7)
	_load_world(planet_id)


# ------------------------------------------------------------------ screens

func _capture_mouse(captured: bool) -> void:
	if DisplayServer.get_name() == "headless":
		return
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED if captured else Input.MOUSE_MODE_VISIBLE)


func _on_interact(what: String) -> void:
	match what:
		"tools", "gear":
			_open(shop)
			shop.open(what)
		"rocket":
			_open(planets_ui)
			planets_ui.open_screen()


func _open(screen: Control) -> void:
	_open_screen = screen
	if world != null and world.player != null:
		world.player.controls_locked = true
	_capture_mouse(false)


func _on_screen_closed() -> void:
	_open_screen = null
	if world != null and world.player != null:
		world.player.controls_locked = false
	if mode == Mode.PLAYING and not get_tree().paused:
		_capture_mouse(true)


func _close_all_screens() -> void:
	for s: Control in [shop, planets_ui, journal, pause_menu]:
		s.visible = false
	_open_screen = null
	if world != null and world.player != null:
		world.player.controls_locked = false


func _on_pause_closed() -> void:
	get_tree().paused = false
	_open_screen = null
	if mode == Mode.PLAYING:
		_capture_mouse(true)


func _unhandled_input(event: InputEvent) -> void:
	if mode != Mode.PLAYING or world == null:
		return
	if event.is_action_pressed("pause") and _open_screen == null:
		_open_screen = pause_menu
		get_tree().paused = true
		_capture_mouse(false)
		pause_menu.open_screen()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("journal") and _open_screen == null:
		_open(journal)
		journal.open_screen()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("quick_save"):
		world.save_all(false)
	elif event.is_action_pressed("screenshot"):
		var dir := "user://screenshots"
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
		var path := "%s/lpbh_%s.png" % [dir, Time.get_datetime_string_from_system().replace(":", "-")]
		get_viewport().get_texture().get_image().save_png(path)
		if hud != null:
			hud.toast("Screenshot saved to " + ProjectSettings.globalize_path(path))
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed and _open_screen == null \
			and Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
		# clicking back into the window re-captures the mouse
		_capture_mouse(true)


func quit_game() -> void:
	if _quitting:
		return
	_quitting = true
	get_tree().paused = false
	if world != null:
		world.shutdown()
	get_tree().quit()
