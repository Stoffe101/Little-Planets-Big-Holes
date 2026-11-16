extends Node
## Static game database loaded from res://data/*.json.
## Autoload name: GameData

var materials: Array[Dictionary] = []          ## ordered; index = material index used by shaders
var material_index: Dictionary = {}            ## id -> index
var tool_families: Array[Dictionary] = []
var tool_family_by_id: Dictionary = {}
var gear: Array[Dictionary] = []
var gear_by_id: Dictionary = {}
var planets: Dictionary = {}                   ## id -> config
var planet_order: Array[String] = []
var discoveries: Array[Dictionary] = []
var discovery_by_id: Dictionary = {}
var objectives: Array[Dictionary] = []

const MAX_MATERIALS := 24


func _ready() -> void:
	reload()


func reload() -> void:
	materials.clear(); material_index.clear()
	for m: Dictionary in _load_json("res://data/materials.json").get("materials", []):
		m["index"] = materials.size()
		m["color_c"] = Color(m.get("color", "#ffffff"))
		m["color2_c"] = Color(m.get("color2", m.get("color", "#ffffff")))
		material_index[m["id"]] = materials.size()
		materials.append(m)
	assert(materials.size() <= MAX_MATERIALS)

	tool_families.clear(); tool_family_by_id.clear()
	for f: Dictionary in _load_json("res://data/tools.json").get("families", []):
		tool_families.append(f)
		tool_family_by_id[f["id"]] = f
	tool_families.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["slot"]) < int(b["slot"]))

	gear.clear(); gear_by_id.clear()
	for g: Dictionary in _load_json("res://data/gear.json").get("gear", []):
		gear.append(g)
		gear_by_id[g["id"]] = g

	discoveries.clear(); discovery_by_id.clear()
	for d: Dictionary in _load_json("res://data/discoveries.json").get("discoveries", []):
		discoveries.append(d)
		discovery_by_id[d["id"]] = d

	objectives.clear()
	for o: Dictionary in _load_json("res://data/objectives.json").get("objectives", []):
		objectives.append(o)

	planets.clear(); planet_order.clear()
	var dir := DirAccess.open("res://data/planets")
	if dir:
		for file in dir.get_files():
			# Exported builds may list remapped names; only accept .json
			if file.ends_with(".json"):
				var cfg := _load_json("res://data/planets/" + file)
				if cfg.has("id"):
					planets[cfg["id"]] = cfg
	planet_order.assign(planets.keys())
	planet_order.sort_custom(func(a: String, b: String) -> bool: return int(planets[a].get("order", 0)) < int(planets[b].get("order", 0)))


func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("GameData: missing %s" % path)
		return {}
	var text := FileAccess.get_file_as_string(path)
	var json := JSON.new()
	if json.parse(text) != OK:
		push_error("GameData: JSON error in %s line %d: %s" % [path, json.get_error_line(), json.get_error_message()])
		return {}
	return json.data if json.data is Dictionary else {}


func material(id_or_index: Variant) -> Dictionary:
	if id_or_index is String or id_or_index is StringName:
		return materials[material_index[id_or_index]]
	return materials[int(id_or_index)]


func mat_index(id: String) -> int:
	return int(material_index.get(id, 0))


func mat_id(index: int) -> String:
	return materials[index]["id"]


func family(id: String) -> Dictionary:
	return tool_family_by_id.get(id, {})


func family_for_slot(slot: int) -> Dictionary:
	for f in tool_families:
		if int(f["slot"]) == slot:
			return f
	return {}


func discovery(id: String) -> Dictionary:
	return discovery_by_id.get(id, {})


func planet(id: String) -> Dictionary:
	return planets.get(id, {})


static func format_money(amount: int) -> String:
	var s := str(absi(amount))
	var out := ""
	var count := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return ("-" if amount < 0 else "") + out
