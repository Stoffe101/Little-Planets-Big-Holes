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
	GameState.reset()
	GameState.current_planet = pid
	world = World.new()
	add_child(world)
	world.start(pid, false)
	await world.ready_to_play
	print("ready, planet load ms=", world.planet.load_time_ms)
	await frames(6)
	await call("scenario_" + scenario)
	print("done")
	get_tree().quit()

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
	world.player.teleport(world.planet.ground_point(d) + d * 0.1, look)
	await physics(10)

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
	await physics(10)
	look_at_point(o + geo.landing_dir * 3.0)
	await shot("base_front")
	world.player.teleport(world.planet.ground_point((o - f.x * 1.5 + f.z * 0.5).normalized()), -f.x)
	await physics(10)
	look_at_point(o - f.x * 4.6 + f.z * 3.4 + geo.landing_dir * 1.8)
	await shot("kiosk")
	world.player.teleport(world.planet.ground_point((o + f.x * 1.5 + f.z * 4.0).normalized()), f.x)
	await physics(10)
	look_at_point(o + f.x * 5.2 + f.z * 1.6 + geo.landing_dir * 1.6)
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
	await frames(3)
	await shot("shop_tools")
	shop.open("gear")
	await frames(3)
	await shot("shop_gear")
	shop.visible = false
	var j := JournalUi.new()
	layer.add_child(j)
	GameState.discover("time_capsule")
	j.open_screen()
	await frames(3)
	await shot("journal")
	j.visible = false
	hud.show_discovery("dormant_bot")
	await frames(30)
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
			await physics(50)
			await frames(3)
			await shot("tool_%s_%d" % [fam["id"], t + 1])
