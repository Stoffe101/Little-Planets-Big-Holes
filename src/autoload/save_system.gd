extends Node
## Versioned save files with atomic writes, a rolling backup and corrupted-save recovery.
## Progress lives in JSON; terrain edits live in one SQLite voxel database per planet AND per
## terrain generation (written by Voxel Tools' VoxelStreamSQLite).
##
## Terrain generations: when a planet's shape, size or caves change (data/planets/*.json
## "generation"), stored voxel edits no longer line up with the regenerated ground. Such a planet
## gets a fresh database file (terrain_<id>_g<gen>.sqlite); the old file is never opened, changed
## or deleted, so nothing is lost and an older build can still read it. Progress (credits,
## tools, upgrades, discoveries) is independent of terrain and always carries over.
## Autoload name: SaveSystem

signal saved(ok: bool)
signal loaded(ok: bool, recovered_from_backup: bool)

const SAVE_DIR := "user://saves/slot1"
const SAVE_FILE := "progress.json"
const BACKUP_FILE := "progress.bak.json"
const TEMP_FILE := "progress.tmp.json"
const MAGIC := "LPBH"
const CHECK_PREFIX := "\n#sha256:"

var save_dir: String = SAVE_DIR      ## overridable (tests use a sandbox directory)
var last_error: String = ""
var last_load_recovered := false


func _path(file: String) -> String:
	return save_dir.path_join(file)


func ensure_dir() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(save_dir))


func has_save() -> bool:
	return FileAccess.file_exists(_path(SAVE_FILE)) or FileAccess.file_exists(_path(BACKUP_FILE))


func terrain_db_path(planet_id: String) -> String:
	ensure_dir()
	return _path(terrain_db_file(planet_id, terrain_generation(planet_id)))


static func terrain_generation(planet_id: String) -> int:
	return maxi(1, int(GameData.planet(planet_id).get("generation", 1)))


## Generation 1 keeps the original v0.x file name so old dig sites stay where they were.
static func terrain_db_file(planet_id: String, generation: int) -> String:
	if generation <= 1:
		return "terrain_%s.sqlite" % planet_id
	return "terrain_%s_g%d.sqlite" % [planet_id, generation]


## Terrain databases in the slot that belong to an older generation of a planet (kept, unused).
func archived_terrain_files() -> Array[String]:
	var out: Array[String] = []
	for pid: String in GameData.planet_order:
		for g in range(1, terrain_generation(pid)):
			var f := terrain_db_file(pid, g)
			if FileAccess.file_exists(_path(f)):
				out.append(f)
	return out


## Returns a short summary for the "Continue" button without mutating GameState.
func peek() -> Dictionary:
	var d := _read_valid(_path(SAVE_FILE))
	if d.is_empty():
		d = _read_valid(_path(BACKUP_FILE))
	if d.is_empty():
		return {}
	var s: Dictionary = d.get("state", {})
	return {
		"money": int(s.get("money", 0)),
		"planet": str(s.get("current_planet", "pipseed")),
		"playtime": float(s.get("playtime", 0.0)),
		"discoveries": (s.get("discoveries", []) as Array).size(),
		"saved_at": str(d.get("saved_at", "")),
	}


func save_game() -> bool:
	ensure_dir()
	last_error = ""
	var payload := {
		"magic": MAGIC,
		"version": GameState.SAVE_VERSION,
		"saved_at": Time.get_datetime_string_from_system(false, true),
		"state": GameState.to_dict(),
	}
	# File layout: pretty JSON, then a trailer line with the SHA-256 of the JSON text.
	var body := JSON.stringify(payload, "  ")
	var text := body + CHECK_PREFIX + body.sha256_text() + "\n"

	# 1) write to a temp file and verify it round-trips
	var f := FileAccess.open(_path(TEMP_FILE), FileAccess.WRITE)
	if f == null:
		last_error = "Cannot open save file for writing (error %d)" % FileAccess.get_open_error()
		saved.emit(false)
		return false
	f.store_string(text)
	f.close()
	if _read_valid(_path(TEMP_FILE)).is_empty():
		last_error = "Save verification failed"
		saved.emit(false)
		return false

	# 2) rotate: current -> backup, temp -> current
	var dir := DirAccess.open(save_dir)
	if dir == null:
		last_error = "Cannot open save directory"
		saved.emit(false)
		return false
	if dir.file_exists(SAVE_FILE):
		if not _read_valid(_path(SAVE_FILE)).is_empty():
			dir.rename(SAVE_FILE, BACKUP_FILE)
		else:
			dir.remove(SAVE_FILE)
	var err := dir.rename(TEMP_FILE, SAVE_FILE)
	if err != OK:
		last_error = "Could not finalise save (error %d)" % err
		saved.emit(false)
		return false
	saved.emit(true)
	return true


## Loads progress into GameState. Falls back to the backup if the main file is damaged.
func load_game() -> bool:
	last_error = ""
	last_load_recovered = false
	var d := _read_valid(_path(SAVE_FILE))
	if d.is_empty():
		d = _read_valid(_path(BACKUP_FILE))
		if not d.is_empty():
			last_load_recovered = true
			push_warning("SaveSystem: main save unreadable, recovered from backup")
	if d.is_empty():
		last_error = "No readable save found"
		loaded.emit(false, false)
		return false
	var version := int(d.get("version", 1))
	if version < GameState.SAVE_VERSION:
		_keep_pre_migration_copy(version)
	var state := migrate(d.get("state", {}), version)
	if not GameState.from_dict(state):
		last_error = "Save data is incomplete"
		loaded.emit(false, last_load_recovered)
		return false
	loaded.emit(true, last_load_recovered)
	return true


## Upgrades older save layouts to the current one. Each step handles one version bump.
func migrate(state: Dictionary, version: int) -> Dictionary:
	var s := state.duplicate(true)
	if version < 2:
		# v1 stored gear levels under "upgrades" and had no slot seed.
		if s.has("upgrades") and not s.has("gear"):
			s["gear"] = s["upgrades"]
			s.erase("upgrades")
		if not s.has("slot_seed"):
			s["slot_seed"] = 0
	if version < 3:
		# v2 (and older) saves were made on the small first-generation planets. Record that, so
		# the game can tell the player once that a planet was resurveyed (its terrain starts
		# fresh in a new database; the old one stays on disk untouched).
		var gens := {}
		for pid: Variant in (s.get("visited", ["pipseed"]) as Array):
			gens[str(pid)] = 1
		gens[str(s.get("current_planet", "pipseed"))] = 1
		s["terrain_generations"] = gens
	s["version"] = GameState.SAVE_VERSION
	return s


## Before an older save is upgraded, keep a verbatim copy of it next to the slot
## (progress.v2.json, ...). Written once per version and never overwritten (New game clears the
## whole slot, as it always has).
func _keep_pre_migration_copy(version: int) -> void:
	var src := _path(SAVE_FILE) if not _read_valid(_path(SAVE_FILE)).is_empty() else _path(BACKUP_FILE)
	var dst := _path("progress.v%d.json" % version)
	if FileAccess.file_exists(dst) or not FileAccess.file_exists(src):
		return
	var bytes := FileAccess.get_file_as_bytes(src)
	var f := FileAccess.open(dst, FileAccess.WRITE)
	if f != null:
		f.store_buffer(bytes)
		f.close()


func delete_save() -> void:
	var dir := DirAccess.open(save_dir)
	if dir == null:
		return
	for file in dir.get_files():
		dir.remove(file)


func _read_valid(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return {}
	var cut := text.rfind(CHECK_PREFIX)
	if cut < 0:
		return {}   # truncated write: the checksum trailer is always written last
	var body := text.substr(0, cut)
	var check := text.substr(cut + CHECK_PREFIX.length()).strip_edges()
	if body.sha256_text() != check:
		return {}
	var json := JSON.new()
	if json.parse(body) != OK or not (json.data is Dictionary):
		return {}
	var d: Dictionary = json.data
	if str(d.get("magic", "")) != MAGIC or not d.has("state") or not (d["state"] is Dictionary):
		return {}
	return d
