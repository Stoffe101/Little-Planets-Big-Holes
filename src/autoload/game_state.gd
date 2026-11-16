extends Node
## Player progression: money, inventory, tools, gear, discoveries, objectives, stats.
## Pure game-logic (no scene access) so it can be unit-tested headless and later
## replicated/authoritative in multiplayer.
## Autoload name: GameState

signal money_changed(amount: int, delta: int)
signal inventory_changed()
signal inventory_full()
signal tools_changed()
signal gear_changed(id: String)
signal equipped_changed(family_id: String)
signal discovery_made(id: String)
signal objective_changed()
signal objective_completed(objective: Dictionary)
signal purchase_made(kind: String, id: String)
signal sold(total: int, items: Dictionary)
signal planet_unlocked(id: String)

const SAVE_VERSION := 2

var money: int = 0
var inventory: Dictionary = {}        ## material id -> units (int)
var tiers: Dictionary = {}            ## family id -> owned tier (0 = none, 1..n)
var mods: Dictionary = {}             ## "family/mod" -> level
var gear_levels: Dictionary = {}      ## gear id -> level
var discoveries: Dictionary = {}      ## discovery id -> true
var visited: Dictionary = {}          ## planet id -> true
var stats: Dictionary = {}
var current_planet: String = "pipseed"
var equipped: String = "shovel"
var objective_index: int = 0
var playtime: float = 0.0
var slot_seed: int = 0                ## per-save seed offset mixed into planet seeds (0 = canonical worlds)
var flags: Dictionary = {}            ## misc persistent world state, e.g. "pipseed/formation_12": true


func _ready() -> void:
	reset()


func reset() -> void:
	money = 0
	inventory = {}
	tiers = {"shovel": 1}
	mods = {}
	gear_levels = {}
	discoveries = {}
	visited = {"pipseed": true}
	stats = {"digs": 0, "chunks_collected": 0, "sales": 0, "total_earned": 0, "scans": 0,
		"max_depth": 0.0, "volume_dug": 0.0, "purchases": 0, "blocked_digs": 0, "bonus_gems": 0}
	current_planet = "pipseed"
	equipped = "shovel"
	objective_index = 0
	playtime = 0.0
	slot_seed = 0
	flags = {}
	_emit_all()


func _emit_all() -> void:
	money_changed.emit(money, 0)
	inventory_changed.emit()
	tools_changed.emit()
	gear_changed.emit("")
	equipped_changed.emit(equipped)
	objective_changed.emit()


# ---------------------------------------------------------------- money

func add_money(amount: int, count_as_earned := true) -> void:
	if amount == 0:
		return
	money += amount
	if amount > 0 and count_as_earned:
		stats["total_earned"] = int(stats.get("total_earned", 0)) + amount
	money_changed.emit(money, amount)
	check_objectives()


func can_afford(cost: int) -> bool:
	return money >= cost


func _spend(cost: int) -> bool:
	if money < cost:
		return false
	money -= cost
	stats["purchases"] = int(stats.get("purchases", 0)) + 1
	money_changed.emit(money, -cost)
	return true


# ---------------------------------------------------------------- inventory

func capacity() -> int:
	return int(gear_value("backpack"))


func inventory_count() -> int:
	var total := 0
	for k: String in inventory:
		total += int(inventory[k])
	return total


func free_space() -> int:
	return maxi(0, capacity() - inventory_count())


func is_full() -> bool:
	return inventory_count() >= capacity()


## Adds up to `amount` units. Returns how many were accepted.
func add_to_inventory(material_id: String, amount: int) -> int:
	var accepted := mini(amount, free_space())
	if accepted <= 0:
		inventory_full.emit()
		return 0
	inventory[material_id] = int(inventory.get(material_id, 0)) + accepted
	stats["chunks_collected"] = int(stats.get("chunks_collected", 0)) + accepted
	var key := "collected_" + material_id
	stats[key] = int(stats.get(key, 0)) + accepted
	inventory_changed.emit()
	if is_full():
		inventory_full.emit()
	check_objectives()
	return accepted


func inventory_value() -> int:
	var total := 0.0
	for k: String in inventory:
		total += float(inventory[k]) * unit_value(k)
	return int(round(total))


func unit_value(material_id: String) -> float:
	return float(GameData.material(material_id).get("value", 1)) * sell_multiplier()


func sell_multiplier() -> float:
	var m := float(gear_value("refinery"))
	if discoveries.has("pip_heart"):
		m *= 1.2
	return m


## Sells the whole inventory. Returns {"total": int, "items": {material_id: {"units": int, "value": int}}}.
func sell_all() -> Dictionary:
	var items := {}
	var total := 0
	for k: String in inventory:
		var units := int(inventory[k])
		if units <= 0:
			continue
		var value := int(round(float(units) * unit_value(k)))
		items[k] = {"units": units, "value": value}
		total += value
	if items.is_empty():
		return {"total": 0, "items": {}}
	inventory = {}
	stats["sales"] = int(stats.get("sales", 0)) + 1
	inventory_changed.emit()
	add_money(total)
	sold.emit(total, items)
	return {"total": total, "items": items}


## Sells a partial amount of one material (used by helper bots and the animated sell stream).
func sell_units(material_id: String, units: int, from_inventory := true) -> int:
	if units <= 0:
		return 0
	if from_inventory:
		var have := int(inventory.get(material_id, 0))
		units = mini(units, have)
		if units <= 0:
			return 0
		if have - units <= 0:
			inventory.erase(material_id)
		else:
			inventory[material_id] = have - units
		inventory_changed.emit()
	var value := int(round(float(units) * unit_value(material_id)))
	add_money(value)
	return value


# ---------------------------------------------------------------- requirements

func requirement_met(req: Variant) -> bool:
	if req == null or not (req is Dictionary) or (req as Dictionary).is_empty():
		return true
	var r: Dictionary = req
	if r.has("tier"):
		for fam: String in r["tier"]:
			if int(tiers.get(fam, 0)) < int(r["tier"][fam]):
				return false
	if r.has("gear"):
		for g: String in r["gear"]:
			if gear_level(g) < int(r["gear"][g]):
				return false
	if r.has("discovery"):
		if not discoveries.has(r["discovery"]):
			return false
	if r.has("discoveries"):
		for d: String in r["discoveries"]:
			if not discoveries.has(d):
				return false
	if r.has("total_earned"):
		if int(stats.get("total_earned", 0)) < int(r["total_earned"]):
			return false
	return true


func requirement_text(req: Variant) -> String:
	if req == null or not (req is Dictionary) or (req as Dictionary).is_empty():
		return ""
	var r: Dictionary = req
	var parts: Array[String] = []
	if r.has("tier"):
		for fam: String in r["tier"]:
			var f := GameData.family(fam)
			var t := int(r["tier"][fam])
			if int(tiers.get(fam, 0)) < t and not f.is_empty():
				parts.append("Own the %s" % f["tiers"][t - 1]["name"])
	if r.has("gear"):
		for g: String in r["gear"]:
			if gear_level(g) < int(r["gear"][g]):
				parts.append("Own %s" % GameData.gear_by_id[g]["name"])
	if r.has("discovery") and not discoveries.has(r["discovery"]):
		parts.append("Discover something buried...")
	if r.has("discoveries"):
		var missing := 0
		for d: String in r["discoveries"]:
			if not discoveries.has(d):
				missing += 1
		if missing > 0:
			parts.append("%d discoveries missing" % missing)
	if r.has("total_earned") and int(stats.get("total_earned", 0)) < int(r["total_earned"]):
		parts.append("Earn %s total" % GameData.format_money(int(r["total_earned"])))
	return ", ".join(parts)


# ---------------------------------------------------------------- tools

func owns_family(family_id: String) -> bool:
	return int(tiers.get(family_id, 0)) > 0


func tier_of(family_id: String) -> int:
	return int(tiers.get(family_id, 0))


func current_tier_def(family_id: String) -> Dictionary:
	var t := tier_of(family_id)
	if t <= 0:
		return {}
	return GameData.family(family_id)["tiers"][t - 1]


func next_tier_def(family_id: String) -> Dictionary:
	var fam := GameData.family(family_id)
	var t := tier_of(family_id)
	if fam.is_empty() or t >= (fam["tiers"] as Array).size():
		return {}
	return fam["tiers"][t]


func mod_level(family_id: String, mod_id: String) -> int:
	return int(mods.get(family_id + "/" + mod_id, 0))


## Effective stats of the owned tier with all mods applied.
func tool_stats(family_id: String) -> Dictionary:
	return tool_stats_for(family_id, tier_of(family_id))


func tool_stats_for(family_id: String, tier: int) -> Dictionary:
	var fam := GameData.family(family_id)
	if fam.is_empty() or tier <= 0:
		return {}
	var out: Dictionary = (fam["tiers"][tier - 1]["stats"] as Dictionary).duplicate()
	out["ore_yield"] = 0.0
	out["trench"] = 0
	for m: Dictionary in fam.get("mods", []):
		var lvl := mod_level(family_id, m["id"])
		if lvl <= 0:
			continue
		var eff: Dictionary = m["effect"]
		var stat: String = eff["stat"]
		var v := float(eff["values"][mini(lvl, (eff["values"] as Array).size()) - 1])
		match eff["op"]:
			"mul": out[stat] = float(out.get(stat, 1.0)) * v
			"add": out[stat] = float(out.get(stat, 0.0)) + v
			"flag": out[stat] = 1
	return out


func buy_next_tier(family_id: String) -> bool:
	var def := next_tier_def(family_id)
	if def.is_empty() or not requirement_met(def.get("requires")):
		return false
	if not _spend(int(def["cost"])):
		return false
	tiers[family_id] = tier_of(family_id) + 1
	tools_changed.emit()
	purchase_made.emit("tier", def["id"])
	if tiers[family_id] == 1:
		set_equipped(family_id)
	check_objectives()
	return true


func mod_cost(family_id: String, mod_id: String) -> int:
	var m := _mod_def(family_id, mod_id)
	var lvl := mod_level(family_id, mod_id)
	if m.is_empty() or lvl >= int(m["max"]):
		return -1
	return int(m["costs"][lvl])


func _mod_def(family_id: String, mod_id: String) -> Dictionary:
	for m: Dictionary in GameData.family(family_id).get("mods", []):
		if m["id"] == mod_id:
			return m
	return {}


func buy_mod(family_id: String, mod_id: String) -> bool:
	var m := _mod_def(family_id, mod_id)
	if m.is_empty() or not owns_family(family_id) or not requirement_met(m.get("requires")):
		return false
	var cost := mod_cost(family_id, mod_id)
	if cost < 0 or not _spend(cost):
		return false
	mods[family_id + "/" + mod_id] = mod_level(family_id, mod_id) + 1
	tools_changed.emit()
	purchase_made.emit("mod", family_id + "/" + mod_id)
	check_objectives()
	return true


func set_equipped(family_id: String) -> void:
	if not owns_family(family_id) or equipped == family_id:
		return
	equipped = family_id
	equipped_changed.emit(equipped)


func owned_families() -> Array[String]:
	var out: Array[String] = []
	for f in GameData.tool_families:
		if owns_family(f["id"]):
			out.append(f["id"])
	return out


# ---------------------------------------------------------------- gear

func gear_level(id: String) -> int:
	return int(gear_levels.get(id, 0))


func gear_value(id: String) -> Variant:
	var g: Dictionary = GameData.gear_by_id.get(id, {})
	if g.is_empty():
		return 0
	var values: Array = g["values"]
	return values[clampi(gear_level(id), 0, values.size() - 1)]


func gear_max_level(id: String) -> int:
	return (GameData.gear_by_id[id]["costs"] as Array).size()


func gear_cost(id: String) -> int:
	var g: Dictionary = GameData.gear_by_id.get(id, {})
	var lvl := gear_level(id)
	if g.is_empty() or lvl >= (g["costs"] as Array).size():
		return -1
	return int(g["costs"][lvl])


func buy_gear(id: String) -> bool:
	var g: Dictionary = GameData.gear_by_id.get(id, {})
	if g.is_empty() or not requirement_met(g.get("requires")):
		return false
	var cost := gear_cost(id)
	if cost < 0 or not _spend(cost):
		return false
	gear_levels[id] = gear_level(id) + 1
	gear_changed.emit(id)
	purchase_made.emit("gear", id)
	if id == "backpack":
		inventory_changed.emit()
	check_objectives()
	return true


func scanner_range() -> float:
	var g: Dictionary = GameData.gear_by_id["scanner"]
	return float(g["ranges"][gear_level("scanner")])


func luck_chance() -> float:
	var c := float(gear_value("lucky")) / 100.0
	if discoveries.has("glimmer_heart"):
		c *= 2.0
	return c


# ---------------------------------------------------------------- discoveries & planets

func has_discovery(id: String) -> bool:
	return discoveries.has(id)


## Records a discovery; returns true if it is new.
func discover(id: String) -> bool:
	if discoveries.has(id):
		return false
	discoveries[id] = true
	var d := GameData.discovery(id)
	if not d.is_empty() and int(d.get("reward", 0)) > 0:
		add_money(int(d["reward"]))
	discovery_made.emit(id)
	for pid in GameData.planet_order:
		if not visited.has(pid) and planet_unlocked_now(pid):
			planet_unlocked.emit(pid)
	tools_changed.emit()
	gear_changed.emit("")
	check_objectives()
	return true


func discovery_count(planet_id := "") -> int:
	if planet_id == "":
		return discoveries.size()
	var n := 0
	for id: String in discoveries:
		if GameData.discovery(id).get("planet", "") == planet_id:
			n += 1
	return n


func planet_unlocked_now(planet_id: String) -> bool:
	var p := GameData.planet(planet_id)
	if p.is_empty():
		return false
	return requirement_met(p.get("unlock", {}))


func can_travel_to(planet_id: String) -> bool:
	if planet_id == current_planet or not planet_unlocked_now(planet_id):
		return false
	if visited.has(planet_id):
		return true
	return money >= int(GameData.planet(planet_id).get("travel_cost", 0))


## Pays the first-visit fare (if any) and switches planet. The world scene reloads in response.
func travel_to(planet_id: String) -> bool:
	if not can_travel_to(planet_id):
		return false
	if not visited.has(planet_id):
		var cost := int(GameData.planet(planet_id).get("travel_cost", 0))
		if cost > 0 and not _spend(cost):
			return false
		visited[planet_id] = true
	current_planet = planet_id
	check_objectives()
	return true


# ---------------------------------------------------------------- stats & objectives

func add_stat(key: String, amount: Variant = 1) -> void:
	stats[key] = stats.get(key, 0) + amount
	check_objectives()


func set_stat_max(key: String, value: float) -> void:
	if value > float(stats.get(key, 0.0)):
		stats[key] = value
		check_objectives()


func set_flag(key: String, value: Variant = true) -> void:
	flags[key] = value


func has_flag(key: String) -> bool:
	return flags.has(key)


func current_objective() -> Dictionary:
	if objective_index < 0 or objective_index >= GameData.objectives.size():
		return {}
	return GameData.objectives[objective_index]


func _cond_met(cond: Dictionary) -> bool:
	if cond.has("stat"):
		return float(stats.get(cond["stat"], 0)) >= float(cond.get("gte", 1))
	if cond.has("tier"):
		return tier_of(cond["tier"][0]) >= int(cond["tier"][1])
	if cond.has("gear"):
		return gear_level(cond["gear"][0]) >= int(cond["gear"][1])
	if cond.has("discovery"):
		return discoveries.has(cond["discovery"])
	if cond.has("discoveries"):
		for d: String in cond["discoveries"]:
			if not discoveries.has(d):
				return false
		return true
	if cond.has("collected"):
		return int(stats.get("collected_" + str(cond["collected"][0]), 0)) >= int(cond["collected"][1])
	if cond.has("visited"):
		return visited.has(cond["visited"])
	return false


## Progress of the current objective in [0, 1] plus a label such as "3 / 12" (may be empty).
func objective_progress() -> Dictionary:
	var o := current_objective()
	if o.is_empty():
		return {"ratio": 0.0, "label": ""}
	var cond: Dictionary = o["cond"]
	if cond.has("stat"):
		var target := float(cond.get("gte", 1))
		var have := minf(float(stats.get(cond["stat"], 0)), target)
		if target <= 1.0:
			return {"ratio": have / target, "label": ""}
		return {"ratio": have / target, "label": "%d / %d" % [int(have), int(target)]}
	if cond.has("collected"):
		var target2 := float(cond["collected"][1])
		var have2 := minf(float(stats.get("collected_" + str(cond["collected"][0]), 0)), target2)
		return {"ratio": have2 / target2, "label": "%d / %d" % [int(have2), int(target2)]}
	if cond.has("discoveries"):
		var n := 0
		for d: String in cond["discoveries"]:
			if discoveries.has(d):
				n += 1
		return {"ratio": float(n) / float((cond["discoveries"] as Array).size()), "label": "%d / %d" % [n, (cond["discoveries"] as Array).size()]}
	return {"ratio": 1.0 if _cond_met(cond) else 0.0, "label": ""}


var _checking := false

func check_objectives() -> void:
	if _checking:
		return
	_checking = true
	var guard := 0
	while guard < 32:
		guard += 1
		var o := current_objective()
		if o.is_empty() or not _cond_met(o["cond"]):
			break
		objective_index += 1
		var reward := int(o.get("reward", 0))
		if reward > 0:
			money += reward
			stats["total_earned"] = int(stats.get("total_earned", 0)) + reward
			money_changed.emit(money, reward)
		objective_completed.emit(o)
	_checking = false
	objective_changed.emit()


# ---------------------------------------------------------------- serialisation

func to_dict() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"money": money,
		"inventory": inventory.duplicate(),
		"tiers": tiers.duplicate(),
		"mods": mods.duplicate(),
		"gear": gear_levels.duplicate(),
		"discoveries": discoveries.keys(),
		"visited": visited.keys(),
		"stats": stats.duplicate(),
		"current_planet": current_planet,
		"equipped": equipped,
		"objective_index": objective_index,
		"playtime": playtime,
		"slot_seed": slot_seed,
		"flags": flags.duplicate(),
	}


## Loads state from a (possibly older or partially damaged) dictionary. Unknown ids are dropped,
## missing fields fall back to defaults. Returns false if the data is unusable.
func from_dict(d: Dictionary) -> bool:
	if not d.has("money") or not d.has("tiers"):
		return false
	reset()
	money = maxi(0, int(d.get("money", 0)))
	for k: Variant in (d.get("inventory", {}) as Dictionary):
		if GameData.material_index.has(str(k)):
			inventory[str(k)] = maxi(0, int(d["inventory"][k]))
	tiers = {"shovel": 1}
	for k: Variant in (d.get("tiers", {}) as Dictionary):
		var fam := GameData.family(str(k))
		if not fam.is_empty():
			tiers[str(k)] = clampi(int(d["tiers"][k]), 0, (fam["tiers"] as Array).size())
	if int(tiers.get("shovel", 0)) < 1:
		tiers["shovel"] = 1
	for k: Variant in (d.get("mods", {}) as Dictionary):
		var parts := str(k).split("/")
		if parts.size() == 2:
			var m := _mod_def(parts[0], parts[1])
			if not m.is_empty():
				mods[str(k)] = clampi(int(d["mods"][k]), 0, int(m["max"]))
	for k: Variant in (d.get("gear", {}) as Dictionary):
		if GameData.gear_by_id.has(str(k)):
			gear_levels[str(k)] = clampi(int(d["gear"][k]), 0, gear_max_level(str(k)))
	for id: Variant in (d.get("discoveries", []) as Array):
		if GameData.discovery_by_id.has(str(id)):
			discoveries[str(id)] = true
	visited = {"pipseed": true}
	for id: Variant in (d.get("visited", []) as Array):
		if GameData.planets.has(str(id)):
			visited[str(id)] = true
	var st: Dictionary = d.get("stats", {})
	for k: Variant in st:
		if st[k] is float or st[k] is int:
			stats[str(k)] = st[k]
	current_planet = str(d.get("current_planet", "pipseed"))
	if not GameData.planets.has(current_planet):
		current_planet = "pipseed"
	equipped = str(d.get("equipped", "shovel"))
	if not owns_family(equipped):
		equipped = "shovel"
	objective_index = clampi(int(d.get("objective_index", 0)), 0, GameData.objectives.size())
	playtime = float(d.get("playtime", 0.0))
	slot_seed = int(d.get("slot_seed", 0))
	for k: Variant in (d.get("flags", {}) as Dictionary):
		flags[str(k)] = d["flags"][k]
	_emit_all()
	check_objectives()
	return true
