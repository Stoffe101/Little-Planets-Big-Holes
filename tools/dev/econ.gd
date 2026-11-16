extends Node
## Dev tool: instrumented simulation of the progression loop.
## A scripted "player" digs real terrain through the real DigSystem (so yields, hardness and
## ore distribution are the game's own), sells through the real GameState and buys upgrades by
## a simple policy. Prints when each purchase happens, income per minute, how often the
## backpack has to be emptied and how long each tool tier is in use.
##
##   godot --headless --path . res://tools/dev/econ.tscn -- [minutes] [policy] [planet]
##   policy: "balanced" (default) | "rush" (tools and backpack only)
##
## Assumptions are deliberately simple and listed in docs/BALANCE.md. This is a pacing model,
## not a substitute for a human playtest.

const AIM_OVERHEAD := 1.2          ## seconds per dig = cooldown * this (aiming, repositioning)
const COLLECT_FRACTION := 0.92     ## share of popped chunks the player actually picks up
const BASE_DISTANCE := 20.0        ## metres from the dig site to the Depot
const SHOP_TIME := 6.0             ## seconds spent selling/buying per trip
const WALK := 5.6 * 1.25           ## average ground speed (walk/sprint mix), m/s

## Purchase order for the "balanced" player. Entries: ["tier", family] | ["mod", family, id] | ["gear", id]
const BALANCED := [
	["tier", "shovel"], ["gear", "backpack"], ["gear", "magnet"], ["mod", "shovel", "wide_scoop"], ["mod", "shovel", "quick_hands"],
	["gear", "backpack"], ["gear", "scanner"], ["gear", "boots"], ["mod", "shovel", "wide_scoop"], ["tier", "shovel"],
	["gear", "backpack"], ["tier", "vacuum"], ["mod", "shovel", "quick_hands"], ["mod", "shovel", "ore_tooth"], ["gear", "jets"],
	["mod", "shovel", "trench_blade"], ["gear", "magnet"], ["tier", "drill"], ["gear", "backpack"], ["gear", "lucky"],
	["gear", "refinery"], ["mod", "drill", "turbo"], ["mod", "drill", "wide_bore"], ["gear", "robot"], ["tier", "cannon"],
	["gear", "backpack"], ["tier", "drill"], ["tier", "shovel"], ["gear", "refinery"], ["gear", "backpack"],
]
const RUSH := [
	["tier", "shovel"], ["gear", "backpack"], ["tier", "shovel"], ["gear", "backpack"], ["tier", "drill"], ["gear", "backpack"],
	["tier", "drill"], ["gear", "backpack"], ["tier", "shovel"], ["gear", "backpack"],
]

var world: World
var t := 0.0
var log_lines: Array[String] = []
var _plan: Array = []
var _plan_i := 0
var _site := 0
var _depth := 0.0
var _thin := 0
var _blocked := 0
var _ground: Dictionary = {}       ## loot left on the ground when the pack was full
var _sales: Array[float] = []      ## timestamps
var _income: Array[Array] = []     ## [time, amount]
var _tier_time: Dictionary = {}
var _digs := 0
var _wasted := 0
var _blocked_total := 0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var minutes := float(args[0]) if args.size() > 0 else 45.0
	var policy: String = args[1] if args.size() > 1 else "balanced"
	var pid: String = args[2] if args.size() > 2 else "pipseed"
	_plan = (RUSH if policy == "rush" else BALANCED).duplicate()
	_rng.seed = 12345
	SaveSystem.save_dir = "user://dev_econ"
	GameState.reset()
	GameState.current_planet = pid
	world = World.new()
	add_child(world)
	world.start(pid, false)
	await world.ready_to_play
	world.player.input_enabled = false
	print("== economy simulation: %s, %.0f min, policy %s" % [pid, minutes, policy])
	_run(minutes * 60.0)
	_report(minutes)
	get_tree().quit()


func _dig_tool() -> String:
	return "drill" if GameState.owns_family("drill") else "shovel"


func _site_dir() -> Vector3:
	# sites ring the base at BASE_DISTANCE; each new site is a fresh patch of ground
	var geo := world.planet.geology
	var up := geo.landing_dir
	var t1 := up.cross(Vector3(0.3, 0.2, 0.9)).normalized()
	var t2 := up.cross(t1).normalized()
	var a := float(_site) * 2.399963          # golden angle
	var dist := BASE_DISTANCE + 4.0 * float(_site / 6)
	return (up + (t1 * cos(a) + t2 * sin(a)) * (dist / geo.radius)).normalized()


func _run(end_time: float) -> void:
	var geo := world.planet.geology
	while t < end_time:
		var fam := _dig_tool()
		var stats := GameState.tool_stats(fam)
		var r := float(stats["radius"])
		var key := "%s T%d" % [fam, GameState.tier_of(fam)]
		var dt := float(stats["cooldown"]) * AIM_OVERHEAD
		_tier_time[key] = float(_tier_time.get(key, 0.0)) + dt
		t += dt
		# a widening pit: random spot in a disc at the current depth
		var dir := _site_dir()
		var t1 := dir.cross(Vector3(0.3, 0.2, 0.9)).normalized()
		var t2 := dir.cross(t1).normalized()
		var pit := maxf(2.2, r * 1.7)
		var off := Vector2.from_angle(_rng.randf() * TAU) * sqrt(_rng.randf()) * pit
		var d2 := (dir + (t1 * off.x + t2 * off.y) / geo.radius).normalized()
		var pos := d2 * (geo.surface_radius(dir) - _depth - r * 0.2)
		var res: Dictionary = world.dig.dig_sphere(pos, r, int(stats["power"]), {"ore_yield": float(stats.get("ore_yield", 0.0))})
		_digs += 1
		if bool(res["blocked"]):
			_blocked += 1
			_blocked_total += 1
			if _blocked >= 4:
				_new_site()
			continue
		_blocked = 0
		var full_volume := 4.0 / 3.0 * PI * r * r * r
		if bool(res["empty"]) or float(res["volume"]) < full_volume * 0.3:
			_thin += 1
			if bool(res["empty"]):
				_wasted += 1
			if _thin >= 3:
				_thin = 0
				_depth += r * 0.8
				if _depth > 26.0:
					_new_site()
		else:
			_thin = 0
		for m: int in res["yields"]:
			var units := int(round(float(res["yields"][m]) * COLLECT_FRACTION))
			var id := GameData.mat_id(m)
			var got := GameState.add_to_inventory(id, units)
			if got < units:
				_ground[id] = int(_ground.get(id, 0)) + units - got
		if GameState.is_full():
			_trip()


func _new_site() -> void:
	_site += 1
	_depth = 0.0
	_blocked = 0
	_thin = 0
	t += 10.0       # walk to a fresh patch


func _trip() -> void:
	var boots := float(GameState.gear_value("boots"))
	var climb := _depth * (1.2 if int(GameState.gear_value("jets")) >= 1 else 2.0)
	t += (BASE_DISTANCE + climb) / (WALK * boots) * 2.0 + SHOP_TIME
	var before := GameState.money
	GameState.sell_all()
	_sales.append(t)
	_income.append([t, GameState.money - before])
	_shop()
	# back at the site: pick up what was left behind (it took no extra walking)
	for id: String in _ground.keys():
		var got := GameState.add_to_inventory(id, int(_ground[id]))
		_ground[id] = int(_ground[id]) - got
		if int(_ground[id]) <= 0:
			_ground.erase(id)


func _shop() -> void:
	var guard := 0
	while _plan_i < _plan.size() and guard < 20:
		guard += 1
		var item: Array = _plan[_plan_i]
		var cost := _cost(item)
		if cost < 0:
			_plan_i += 1        # not available / already maxed: skip
			continue
		if not _requirements_met(item):
			# blocked by a discovery or prerequisite: come back to it later
			_plan.remove_at(_plan_i)
			if _plan.size() - _plan_i > 3:
				_plan.insert(_plan_i + 3, item)
			continue
		if GameState.money >= cost:
			_buy(item)
			_plan_i += 1
		else:
			# saving for a big purchase: only small conveniences in the meantime
			if cost > GameState.money * 3 and _buy_cheap_filler():
				continue
			return


func _buy_cheap_filler() -> bool:
	for j in range(_plan_i + 1, mini(_plan_i + 5, _plan.size())):
		var item: Array = _plan[j]
		var cost := _cost(item)
		if cost > 0 and cost <= GameState.money * 0.4 and _requirements_met(item):
			_buy(item)
			_plan.remove_at(j)
			return true
	return false


func _cost(item: Array) -> int:
	match str(item[0]):
		"tier":
			var def := GameState.next_tier_def(str(item[1]))
			return int(def["cost"]) if not def.is_empty() else -1
		"mod":
			return GameState.mod_cost(str(item[1]), str(item[2])) if GameState.owns_family(str(item[1])) else -1
		"gear":
			return GameState.gear_cost(str(item[1]))
	return -1


func _requirements_met(item: Array) -> bool:
	match str(item[0]):
		"tier":
			return GameState.requirement_met(GameState.next_tier_def(str(item[1])).get("requires"))
		"mod":
			for m: Dictionary in GameData.family(str(item[1])).get("mods", []):
				if str(m["id"]) == str(item[2]):
					return GameState.requirement_met(m.get("requires"))
		"gear":
			return GameState.requirement_met((GameData.gear_by_id[str(item[1])] as Dictionary).get("requires"))
	return false


func _buy(item: Array) -> void:
	var cost := _cost(item)
	var ok := false
	var name := ""
	match str(item[0]):
		"tier":
			name = str(GameState.next_tier_def(str(item[1]))["name"])
			ok = GameState.buy_next_tier(str(item[1]))
		"mod":
			name = "%s/%s L%d" % [item[1], item[2], GameState.mod_level(str(item[1]), str(item[2])) + 1]
			ok = GameState.buy_mod(str(item[1]), str(item[2]))
		"gear":
			name = "%s L%d" % [item[1], GameState.gear_level(str(item[1])) + 1]
			ok = GameState.buy_gear(str(item[1]))
	if ok:
		log_lines.append("%5.1f min  buy %-28s %7d cr   (earned so far %d)" % [t / 60.0, name, cost, int(GameState.stats.get("total_earned", 0))])


func _report(minutes: float) -> void:
	print("-- purchases")
	for l in log_lines:
		print(l)
	print("-- income and selling, per 5 minutes")
	var window := 300.0
	var w := 0
	while float(w) * window < minutes * 60.0:
		var a := float(w) * window
		var b := a + window
		var inc := 0
		var n := 0
		for e in _income:
			if float(e[0]) >= a and float(e[0]) < b:
				inc += int(e[1])
				n += 1
		print("%3d-%3d min: %7d cr  (%6.0f cr/min)  %2d sales  avg %.0f s between sales" % [int(a / 60.0), int(b / 60.0), inc, float(inc) / 5.0, n, window / maxf(float(n), 1.0)])
		w += 1
	print("-- time digging with each tool (minutes)")
	for k: String in _tier_time:
		print("  %-12s %.1f" % [k, float(_tier_time[k]) / 60.0])
	var first_sale := _sales[0] if not _sales.is_empty() else -1.0
	print("-- first sale at %.1f min; digs %d (%d empty, %d blocked); objectives done %d; money %d; total earned %d" % [
		first_sale / 60.0, _digs, _wasted, _blocked_total, GameState.objective_index, GameState.money, int(GameState.stats.get("total_earned", 0))])
	var sold: Dictionary = {}
	for k: String in GameState.stats:
		if k.begins_with("collected_"):
			sold[k.trim_prefix("collected_")] = int(GameState.stats[k])
	print("-- collected units and their share of value")
	var total_value := 0.0
	for id: String in sold:
		total_value += float(sold[id]) * float(GameData.material(id)["value"])
	for id: String in sold:
		var v := float(sold[id]) * float(GameData.material(id)["value"])
		print("  %-12s %7d units  %5.1f%% of value" % [id, int(sold[id]), 100.0 * v / maxf(total_value, 1.0)])
