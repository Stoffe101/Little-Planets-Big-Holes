class_name Contracts
extends Node
## Survey contracts: one open contract per planet, always something concrete to do that pulls
## the player out into the regions. Three kinds, generated in sequence from data/contracts.json
## and deterministic per save slot:
##   * relay   - bring a region's survey relay online (go there),
##   * deliver - sell N units of an ore at the Depot (bots and the Auto-Borer count too),
##   * depth   - excavate down to D metres inside a named region (precision digging).
## Credits only; completing one opens the next, slightly larger one.

signal contract_changed(c: Dictionary)
signal contract_completed(c: Dictionary)

var world: World
var cfg: Dictionary = {}
var _check := 0.0


func setup(w: World) -> void:
	world = w
	var f := FileAccess.open("res://data/contracts.json", FileAccess.READ)
	if f != null:
		var d: Variant = JSON.parse_string(f.get_as_text())
		if d is Dictionary:
			cfg = d
	GameState.units_delivered.connect(_on_delivered)
	if current().is_empty():
		_open_next(0)


func _key() -> String:
	return "contract/%s" % world.planet_id


func current() -> Dictionary:
	var c: Variant = GameState.flags.get(_key(), {})
	return c if c is Dictionary else {}


## Builds contract number `k` for this planet (pure: same slot seed -> same contract).
func make(k: int) -> Dictionary:
	var cycle: Array = cfg.get("cycle", ["relay", "deliver", "depth"])
	var kind := str(cycle[k % cycle.size()])
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s/%d/%d" % [world.planet_id, GameState.slot_seed, k])
	var c := {"k": k, "kind": kind, "progress": 0}
	var nav := world.nav
	match kind:
		"relay":
			var offline: Array[Dictionary] = []
			for r in nav.relays:
				if not nav.relay_active(r["id"]):
					offline.append(r)
			if offline.is_empty():
				kind = "depth"
				c["kind"] = kind
			else:
				# nearest offline relay first, so the planet opens up outwards
				offline.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
					return nav.surface_distance(a["pos"], world.planet.geology.spawn_position()) < nav.surface_distance(b["pos"], world.planet.geology.spawn_position()))
				var rel: Dictionary = offline[0]
				var rc: Dictionary = cfg.get("relay", {})
				c["target"] = rel["id"]
				c["amount"] = 1
				c["reward"] = int(rc.get("reward", 200)) + int(rc.get("reward_step", 100)) * (k / 3)
				c["text"] = "Bring %s online" % rel["name"]
				c["region"] = str(nav.region_at(rel["pos"]).get("name", ""))
	match kind:
		"deliver":
			var ores: Array = world.planet.config.get("ores", [])
			# shallow ores first, deeper ores as the sequence advances
			var sorted := ores.duplicate()
			sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["min_depth"]) < float(b["min_depth"]))
			var o: Dictionary = sorted[mini(k / 3 + rng.randi() % 2, sorted.size() - 1)]
			var dc: Dictionary = cfg.get("deliver", {})
			var units_tab: Array = dc.get("units", [15])
			var units := int(units_tab[mini(k / 2, units_tab.size() - 1)])
			var mid := str(o["material"])
			c["target"] = mid
			c["amount"] = units
			c["reward"] = maxi(int(dc.get("min_reward", 100)), int(round(float(units) * GameState.unit_value(mid) * float(dc.get("bonus_mult", 0.5)))))
			c["text"] = "Deliver %d %s to the Depot" % [units, str(GameData.material(mid).get("name", mid))]
			c["region"] = _region_name(str(o.get("region", "")))
		"depth":
			var regs := world.planet.geology.regions
			var reg: Dictionary = regs[(k + rng.randi() % maxi(regs.size(), 1)) % regs.size()]
			var tab: Array = (cfg.get("depth", {}) as Dictionary).get("depth", [8])
			var depth := int(tab[mini(k / 2, tab.size() - 1)])
			var pc: Dictionary = cfg.get("depth", {})
			c["target"] = str(reg["id"])
			c["amount"] = depth
			c["reward"] = depth * int(pc.get("reward_per_m", 15)) + int(pc.get("reward_step", 50)) * (k / 3)
			c["text"] = "Excavate down to %d m in %s" % [depth, str(reg["name"])]
			c["region"] = str(reg["name"])
	return c


func _region_name(id: String) -> String:
	for r in world.planet.geology.regions:
		if r["id"] == id:
			return str(r["name"])
	return ""


func _open_next(k: int) -> void:
	var c := make(k)
	GameState.flags[_key()] = c
	contract_changed.emit(c)


func _complete() -> void:
	var c := current()
	if c.is_empty():
		return
	var reward := int(c.get("reward", 0))
	GameState.add_money(reward)
	GameState.add_stat("contracts_done")
	Audio.play("objective", -2.0)
	world.message.emit("Contract complete: %s  +%s" % [str(c.get("text", "")), GameData.format_money(reward)], "notice")
	contract_completed.emit(c)
	_open_next(int(c.get("k", 0)) + 1)


func _set_progress(v: int) -> void:
	var c := current()
	if c.is_empty() or v == int(c.get("progress", 0)):
		return
	c["progress"] = v
	GameState.flags[_key()] = c
	contract_changed.emit(c)
	if v >= int(c.get("amount", 1)):
		_complete()


func _on_delivered(material_id: String, units: int) -> void:
	var c := current()
	if str(c.get("kind", "")) == "deliver" and str(c.get("target", "")) == material_id:
		_set_progress(mini(int(c.get("progress", 0)) + units, int(c.get("amount", 1))))


func _process(delta: float) -> void:
	if world == null or not world.is_ready or world.player == null:
		return
	_check -= delta
	if _check > 0.0:
		return
	_check = 0.5
	var c := current()
	match str(c.get("kind", "")):
		"relay":
			if world.nav.relay_active(str(c.get("target", ""))):
				_set_progress(1)
		"depth":
			var here := str(world.nav.current_region.get("id", ""))
			if here == str(c.get("target", "")):
				var d := int(floor(world.player.depth))
				if d > int(c.get("progress", 0)):
					_set_progress(mini(d, int(c.get("amount", 1))))
