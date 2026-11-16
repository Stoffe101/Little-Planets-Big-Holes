extends Node
## Dev harness: boots a World without persistence, runs a scripted scenario and saves screenshots.
## Usage: godot --path . res://tools/dev/shots.tscn -- <scenario> <out_prefix> [planet]
var world: World
var out := "/tmp/shot"

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var scenario: String = args[0] if args.size() > 0 else "spawn"
	out = args[1] if args.size() > 1 else out
	var pid: String = args[2] if args.size() > 2 else "pipseed"
	SaveSystem.save_dir = "user://dev_shots"
	exact_window()
	GameState.reset()
	GameState.current_planet = pid
	world = World.new()
	add_child(world)
	world.start(pid, false)
	await world.ready_to_play
	print("ready, planet load ms=", world.planet.load_time_ms)
	await settle()
	await frames(6)
	await call("scenario_" + scenario)
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


func frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func physics(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func shot(label: String) -> void:
	await frames(2)
	if DisplayServer.get_name() == "headless":
		print("(headless: skipped screenshot ", label, ")")
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s_%s.png" % [out, label])
	print("saved ", label)

func look_pitch(deg: float) -> void:
	world.player.pitch = deg_to_rad(deg)

func use_tool(seconds: float) -> void:
	world.tools.forced_use_enabled = true
	world.tools.forced_use = true
	await physics(int(seconds * 60.0))
	world.tools.forced_use = false
	await physics(20)

func scenario_spawn() -> void:
	look_pitch(-8)
	await shot("spawn")
	look_pitch(-38)
	await shot("lookdown")

func place(dir: Vector3, look := Vector3(1, 0, 0.3)) -> void:
	var d := dir.normalized()
	await stream(d * (world.planet.geology.surface_radius(d) + 1.0))
	world.player.teleport(world.planet.ground_point(d) + d * 0.1, look)
	world.props.update_now(world.player.global_position)
	await physics(40)


## Moves the player (and the terrain viewer) to `pos`, waits for full-resolution ground with
## collision there, then for the rest of the LOD pyramid so the horizon is complete in the shot.
func stream(pos: Vector3, radius := 8.0) -> void:
	world.player.teleport(pos, -world.player.global_basis.z)
	var t0 := Time.get_ticks_msec()
	while not world.planet.is_area_ready(pos, radius) and Time.get_ticks_msec() - t0 < 20000:
		await physics(1)
	await settle()


## Waits until the voxel engine has no generation or meshing work left (max 15 s).
func settle() -> void:
	var t0 := Time.get_ticks_msec()
	var quiet := 0
	while Time.get_ticks_msec() - t0 < 15000 and quiet < 10:
		await frames(1)
		var t: Dictionary = VoxelEngine.get_stats()["tasks"]
		quiet = quiet + 1 if int(t["meshing"]) + int(t["generation"]) + int(t["streaming"]) == 0 else 0
	if world.props != null:
		world.props.update_now(world.player.global_position)

func scenario_dig() -> void:
	await place(Vector3(0.25, 1, 0.1))
	look_pitch(-6)
	await shot("view")
	look_pitch(-42)
	await use_tool(3.0)
	await shot("dig1")
	world.player.forced_move = Vector2(0, 1)
	await physics(30)
	world.player.forced_move = Vector2.ZERO
	await use_tool(4.0)
	look_pitch(-55)
	await shot("dig2")
	print("inventory: ", GameState.inventory, " pickups: ", world.pickups.count(), " avg dig ms: ", world.dig.average_dig_ms())

func scenario_debug() -> void:
	var p := world.player
	for i in 5:
		await physics(20)
		print("r=", p.global_position.length(), " floor=", p.is_on_floor(), " vel=", p.velocity, " up=", p.up, " depth=", p.depth, " eye=", p.eye_position(), " aim=", p.aim_direction())
	look_pitch(-42)
	await physics(5)
	print("aim hit: ", world.tools._aim(3.2), " surface r=", world.planet.geology.surface_radius(p.up))
	var hit := p.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(p.global_position + p.up * 20.0, Vector3.ZERO, 1))
	print("down ray: ", hit.get("position", "none"))

func look_at_point(target: Vector3) -> void:
	var p := world.player
	var eye := p.global_position + p.up * Player.EYE_HEIGHT
	var to := (target - eye).normalized()
	var flat := (to - p.up * to.dot(p.up)).normalized()
	var fwd := -p.global_basis.z
	var ang := fwd.signed_angle_to(flat, p.up)
	p.look(Vector2(ang, 0))
	p.pitch = asin(clampf(to.dot(p.up), -1.0, 1.0))

func scenario_base() -> void:
	var geo := world.planet.geology
	var b: Node3D = world.base
	var o: Vector3 = b.get("origin")
	var f: Basis = b.get("frame")
	world.player.teleport(world.planet.ground_point((o + f.x * 3.0 + f.z * 13.0).normalized()) , -f.z)
	await physics(40)
	look_at_point(o + geo.landing_dir * 3.0)
	await shot("base_front")
	world.player.teleport(world.planet.ground_point((o - f.x * 2.2 + f.z * 1.0).normalized()), -f.x)
	await physics(10)
	look_at_point(o - f.x * 4.8 + f.z * 3.5 + geo.landing_dir * 1.6)
	await shot("kiosk")
	world.player.teleport(world.planet.ground_point((o + f.x * 3.4 - f.z * 1.8).normalized()), f.x)
	await physics(10)
	look_at_point(o + f.x * 6.3 + f.z * 1.8 + geo.landing_dir * 1.3)
	await shot("sell")
	print("props=", world.props.get("prop_count"), " formations=", world.props.get("formation_count"), " cave formations=", world.secrets.get("formation_count"))

func scenario_ui() -> void:
	var hud := Hud.new()
	add_child(hud)
	hud.setup(world)
	GameState.add_money(1234)
	GameState.add_to_inventory("copper", 12)
	GameState.add_to_inventory("topsoil", 9)
	world.message.emit("%d|%d" % [GameData.mat_index("copper"), 3], "pickup")
	world.message.emit("%d|%d" % [GameData.mat_index("topsoil"), 5], "pickup")
	world.message.emit("Dense Clay is too hard for this tool (needs power 2)", "hint")
	await place(Vector3(0.3, 1, 0.25))
	look_pitch(-12)
	await shot("hud")
	var shop := ShopUi.new()
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	layer.add_child(shop)
	shop.open("tools")
	await frames(6)
	await shot("shop_tools")
	GameState.buy_next_tier("shovel")
	GameState.buy_mod("shovel", "wide_scoop")
	await frames(20)
	await shot("shop_bought")
	shop._select_family("drill")
	await frames(6)
	await shot("shop_drill")
	shop.open("gear")
	await frames(4)
	await shot("shop_gear")
	shop.visible = false
	var j := JournalUi.new()
	layer.add_child(j)
	GameState.discover("time_capsule")
	j.open_screen()
	await frames(4)
	await shot("journal")
	j.visible = false
	var ps := PlanetSelectUi.new()
	layer.add_child(ps)
	ps.open_screen()
	await frames(4)
	await shot("planets")
	ps.visible = false
	var pm := PauseMenu.new()
	layer.add_child(pm)
	pm.open_screen()
	await frames(4)
	await shot("pause")
	pm.visible = false
	hud.show_discovery("dormant_bot")
	await frames(40)
	await shot("discovery")

func scenario_tools() -> void:
	await place(Vector3(0.3, 1, 0.25))
	look_pitch(-14)
	GameState.money = 9999999
	for d in GameData.discoveries:
		GameState.discoveries[d["id"]] = true
	for fam in GameData.tool_families:
		var n: int = (fam["tiers"] as Array).size()
		for t in n:
			if GameState.tier_of(fam["id"]) < t + 1:
				GameState.buy_next_tier(fam["id"])
			if t == n - 1:
				for m in fam["mods"]:
					for k in int(m["max"]):
						GameState.buy_mod(fam["id"], m["id"])
			GameState.set_equipped(fam["id"])
			await physics(130)
			await frames(3)
			await shot("tool_%s_%d" % [fam["id"], t + 1])

func carve(a: Vector3, b: Vector3, radius: float) -> void:
	var steps := int(a.distance_to(b) / (radius * 0.6)) + 1
	for i in steps + 1:
		world.dig.dig_sphere(a.lerp(b, float(i) / float(steps)), radius, 9)
	await physics(30)

## Underground tour: a quarry cut through the strata, a tunnel, the crystal grotto and the heart.
func scenario_tour() -> void:
	var geo := world.planet.geology
	var dir := Vector3(0.45, 0.8, -0.4).normalized()
	var top := dir * geo.surface_radius(dir)
	var side := dir.cross(Vector3.UP).normalized()
	await stream(top + dir * 2.0, 24.0)
	# open quarry: a big stepped pit so the layers are visible in daylight
	for i in 9:
		world.dig.dig_sphere(top - dir * (1.5 + 2.2 * i) + side * (i * 1.6), 5.5 - i * 0.3, 9)
	await physics(40)
	world.player.teleport(world.planet.ground_point((top + side * 11.0).normalized()) , -side)
	await physics(20)
	look_at_point(top - dir * 5.0 + side * 2.0)
	await shot("quarry")
	# tunnel into stone with the headlamp
	var t0 := top - dir * 16.0 + side * 12.0
	var t1 := t0 - dir * 6.0 + side * 12.0
	await carve(t0, t1, 2.0)
	world.player.teleport(t0 - dir * 1.2, t1 - t0)
	await physics(30)
	look_at_point(t1)
	await shot("tunnel")
	# crystal grotto
	for c in geo.cavities:
		if c["id"] == "crystal_grotto":
			var cc: Vector3 = c["center"]
			var cd: Vector3 = c["dir"]
			var cside := cd.cross(Vector3(0.2, 0.9, 0.3)).normalized()
			var stand := cc + cside * float(c["radius"]) * 0.55 - cd * float(c["radius"]) * 0.2
			await stream(cc, float(c["radius"]) + 2.0)
			world.player.teleport(world.planet.ground_point(stand.normalized(), stand.length()), cc - stand)
			await physics(40)
			look_at_point(cc - cd * 1.0)
			await physics(10)
			await shot("grotto")
	# the heart
	world.tools.visible = false
	await stream(Vector3(3.6, -1.2, 2.3), geo.core_radius + 2.0)
	world.player.teleport(Vector3(3.6, -1.2, 2.3), Vector3(-1, 0, -0.6))
	await physics(20)
	look_at_point(Vector3.ZERO)
	await shot("heart")
	world.tools.visible = true

func scenario_surface() -> void:
	var dirs := [Vector3(0.6, 0.55, 0.55), Vector3(-0.5, 0.6, 0.6), Vector3(0.2, -0.8, 0.5)]
	var i := 0
	for d: Vector3 in dirs:
		await place(d, Vector3(0.3, 0.2, 1))
		look_pitch(-4)
		await shot("surface_%d" % i)
		i += 1

func scenario_menu() -> void:
	world.queue_free()
	await frames(3)
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	await frames(8)
	await shot("menu")

## Mid-dig action shot with HUD (time slowed so one-shot particles are caught on a slow renderer).
func scenario_action() -> void:
	var hud := Hud.new()
	add_child(hud)
	hud.setup(world)
	GameState.tiers["shovel"] = 2
	GameState.gear_levels["scanner"] = 1
	GameState.tools_changed.emit()
	await place(Vector3(0.42, 0.85, -0.3))
	look_pitch(-38)
	world.pickups.magnet_enabled = false
	await use_tool(2.2)
	world.player.forced_move = Vector2(0.4, 0.3)
	await physics(20)
	world.player.forced_move = Vector2.ZERO
	look_pitch(-44)
	world.tools.forced_use = true
	await physics(26)
	Engine.time_scale = 0.03
	await shot("action")
	Engine.time_scale = 1.0
	world.tools.forced_use = false
	world.pickups.magnet_enabled = true
	world.scanner.call("try_scan")
	await physics(40)
	Engine.time_scale = 0.03
	look_pitch(-30)
	await shot("scan")
	Engine.time_scale = 1.0


## Studio line-up: every tool tier (bare, then fully modded) against a plain backdrop, seen
## from the three-quarter angle used by the shop previews. For judging the models themselves.
func scenario_lineup() -> void:
	await place(Vector3(0.3, 1, 0.25))
	look_pitch(-5)
	world.tools.visible = false
	var cam := world.player.camera
	var stage := Node3D.new()
	cam.add_child(stage)
	stage.position = Vector3(0, 0.02, -0.78)
	var back := MeshKit.new().matte()
	back.block(Vector3(0, 0, -1.6), Vector3(9, 6, 0.05), Color("#3a3f46"), 0.01)
	back.block(Vector3(0, -0.42, 0), Vector3(9, 0.05, 4), Color("#444a52"), 0.01)
	stage.add_child(back.instance(MeshKit.material(), false))
	for d in GameData.discoveries:
		GameState.discoveries[d["id"]] = true
	for fam in GameData.tool_families:
		var n: int = (fam["tiers"] as Array).size()
		for t in n:
			for modded in 2:
				var mods := {}
				if modded == 1:
					for m in fam["mods"]:
						mods[m["id"]] = int(m["max"])
				var model := ToolModels.build(str(fam["id"]), t + 1, mods, false)
				var root: Node3D = model["root"]
				stage.add_child(root)
				root.rotation = Vector3(deg_to_rad(20.0), deg_to_rad(128.0), 0.0)
				root.position = -(root.basis * Vector3(0, 0, -0.26))
				await frames(3)
				await shot("lineup_%s_%d%s" % [fam["id"], t + 1, "_mods" if modded == 1 else ""])
				root.queue_free()
				await frames(1)


## The moment after buying a tool: the HUD names it and the new model is held up for a look.
func scenario_purchase() -> void:
	var hud := Hud.new()
	add_child(hud)
	hud.setup(world)
	GameState.tiers["shovel"] = 2
	GameState.tools_changed.emit()
	await place(Vector3(0.3, 1, 0.25))
	look_pitch(-10)
	await physics(120)
	GameState.money = 5000
	GameState.buy_next_tier("shovel")
	await physics(42)
	await shot("purchase")


## Waits until `seconds` of game time have passed (independent of the frame rate).
func game_time(seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		await get_tree().process_frame
		t += get_process_delta_time()


## Captures `n` frames spread over `seconds` of game time: a film strip of one action.
func strip(label: String, seconds: float, n: int) -> void:
	for i in n:
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s_motion_%s_%02d.png" % [out, label, i])
		await game_time(seconds / float(n))
	print("saved strip ", label)


## Film strips of the first-person animations (time is slowed so frames land where intended):
## hand swing, power-shovel punch, drill spin-up into rock, cannon shot, tool switch and the
## new-purchase presentation. Tile each strip with sheet.tscn to review motion without playing.
func scenario_motion() -> void:
	if DisplayServer.get_name() == "headless":
		return
	await place(Vector3(0.3, 1, 0.25))
	look_pitch(-32)
	world.pickups.magnet_enabled = false
	GameState.money = 9999999
	for d in GameData.discoveries:
		GameState.discoveries[d["id"]] = true
	world.tools.forced_use_enabled = true
	await physics(60)
	Engine.time_scale = 0.2
	# 1. hand swing (one full swing of the starter scoop is 0.46 s)
	world.tools.forced_use = true
	await strip("swing", 0.5, 8)
	world.tools.forced_use = false
	await game_time(0.5)
	# 2. power shovel: two punches
	GameState.buy_next_tier("shovel")
	GameState.buy_next_tier("shovel")
	world.tools._pending_inspect = ""
	await game_time(0.3)
	world.tools.forced_use = true
	await strip("thumper", 0.5, 8)
	world.tools.forced_use = false
	await game_time(0.4)
	# 3. tool switch: shovel down, drill up
	GameState.buy_next_tier("drill")
	world.tools._pending_inspect = ""
	await strip("switch", 0.55, 8)
	await game_time(0.4)
	# 4. drill: spin-up and contact, on fresh ground
	world.player.look(Vector2(1.1, 0.0))
	await game_time(0.3)
	world.tools.forced_use = true
	await strip("drill", 1.0, 8)
	world.tools.forced_use = false
	await game_time(0.4)
	# 5. cannon: shot and recoil
	GameState.buy_next_tier("cannon")
	world.tools._pending_inspect = ""
	await game_time(0.8)
	look_pitch(-12)
	world.tools.forced_use = true
	await strip("cannon", 0.45, 8)
	world.tools.forced_use = false
	await game_time(0.6)
	# 6. the new-purchase presentation (1.5 s)
	GameState.buy_next_tier("cannon")
	await strip("inspect", 1.5, 8)
	Engine.time_scale = 1.0
