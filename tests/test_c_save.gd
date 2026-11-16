extends TestSuite
## Save files: round trip, atomic rotation, backup recovery from corruption, migration.


func before_all() -> void:
	use_sandbox("save")


func _main_path() -> String:
	return SaveSystem.save_dir.path_join(SaveSystem.SAVE_FILE)


func _backup_path() -> String:
	return SaveSystem.save_dir.path_join(SaveSystem.BACKUP_FILE)


func test_save_and_load_round_trip() -> void:
	use_sandbox("save")
	GameState.reset()
	assert_false(SaveSystem.has_save(), "no save yet")
	GameState.money = 777
	GameState.add_to_inventory("copper", 4)
	GameState.tiers["shovel"] = 2
	GameState.stats["max_depth"] = 9.25
	assert_true(SaveSystem.save_game(), "save succeeds")
	assert_true(SaveSystem.has_save(), "save exists")
	GameState.reset()
	assert_true(SaveSystem.load_game(), "load succeeds")
	assert_eq(GameState.money, 777, "money restored")
	assert_eq(int(GameState.inventory["copper"]), 4, "inventory restored")
	assert_eq(GameState.tier_of("shovel"), 2, "tools restored")
	assert_near(float(GameState.stats["max_depth"]), 9.25, 0.001, "float stat restored")
	assert_false(SaveSystem.last_load_recovered, "no recovery needed")
	var info := SaveSystem.peek()
	assert_eq(int(info["money"]), 777, "peek reports money without loading")


func test_backup_is_kept_and_used_when_main_is_corrupted() -> void:
	use_sandbox("save")
	GameState.reset()
	GameState.money = 100
	SaveSystem.save_game()
	GameState.money = 200
	SaveSystem.save_game()          # the 100 save rotates to backup
	assert_true(FileAccess.file_exists(_backup_path()), "backup written")
	# scribble over the main save
	var f := FileAccess.open(_main_path(), FileAccess.WRITE)
	f.store_string("{ this is not a save file")
	f.close()
	GameState.reset()
	assert_true(SaveSystem.load_game(), "load falls back to the backup")
	assert_true(SaveSystem.last_load_recovered, "recovery flagged")
	assert_eq(GameState.money, 100, "backup contents loaded")


func test_tampered_or_truncated_saves_are_rejected() -> void:
	use_sandbox("save")
	GameState.reset()
	GameState.money = 555
	SaveSystem.save_game()
	var text := FileAccess.get_file_as_string(_main_path())
	# truncated write (power cut half-way): no checksum trailer
	var f := FileAccess.open(_main_path(), FileAccess.WRITE)
	f.store_string(text.substr(0, text.length() / 2))
	f.close()
	GameState.reset()
	assert_false(SaveSystem.load_game(), "truncated save with no backup is rejected")
	assert_true(SaveSystem.last_error != "", "error message set")
	# valid JSON but edited contents: checksum mismatch
	f = FileAccess.open(_main_path(), FileAccess.WRITE)
	f.store_string(text.replace("555", "999999"))
	f.close()
	assert_false(SaveSystem.load_game(), "edited save fails its checksum")
	assert_eq(GameState.money, 0, "state untouched by a failed load")


func test_saving_over_a_corrupt_main_file_recovers() -> void:
	use_sandbox("save")
	var f := FileAccess.open(_main_path(), FileAccess.WRITE)
	f.store_string("garbage")
	f.close()
	GameState.reset()
	GameState.money = 42
	assert_true(SaveSystem.save_game(), "can save over garbage")
	GameState.reset()
	assert_true(SaveSystem.load_game(), "new save loads")
	assert_eq(GameState.money, 42, "new save contents")


func test_migration_from_version_1() -> void:
	var old := {"money": 300, "tiers": {"shovel": 2}, "upgrades": {"backpack": 2}, "inventory": {}, "discoveries": []}
	var migrated := SaveSystem.migrate(old, 1)
	assert_true(migrated.has("gear"), "v1 'upgrades' renamed to 'gear'")
	assert_false(migrated.has("upgrades"), "old key removed")
	assert_eq(int(migrated["slot_seed"]), 0, "slot seed defaulted")
	GameState.reset()
	assert_true(GameState.from_dict(migrated), "migrated data loads")
	assert_eq(GameState.gear_level("backpack"), 2, "gear level carried over")


func test_delete_save() -> void:
	use_sandbox("save")
	GameState.reset()
	SaveSystem.save_game()
	assert_true(SaveSystem.has_save(), "exists")
	SaveSystem.delete_save()
	assert_false(SaveSystem.has_save(), "deleted")
	assert_false(SaveSystem.load_game(), "nothing to load")


## Writes a save file exactly as an older build would have (same checksum trailer).
func _write_old_save(version: int, state: Dictionary) -> String:
	var payload := {"magic": SaveSystem.MAGIC, "version": version, "saved_at": "2026-11-01 12:00:00", "state": state}
	var body := JSON.stringify(payload, "  ")
	var text := body + SaveSystem.CHECK_PREFIX + body.sha256_text() + "\n"
	var f := FileAccess.open(SaveSystem.save_dir.path_join(SaveSystem.SAVE_FILE), FileAccess.WRITE)
	f.store_string(text)
	f.close()
	return text


func _v2_state() -> Dictionary:
	return {"version": 2, "money": 12345, "inventory": {"copper": 7, "gold": 2}, "tiers": {"shovel": 3, "drill": 2},
		"mods": {"drill/turbo": 1}, "gear": {"backpack": 3, "boots": 1, "scanner": 1}, "discoveries": ["dormant_bot", "time_capsule"],
		"visited": ["pipseed"], "stats": {"digs": 420, "volume_dug": 900.5}, "current_planet": "pipseed", "equipped": "drill",
		"objective_index": 4, "playtime": 3600.0, "slot_seed": 77, "flags": {"pipseed/crystal_3": true}}


func test_migration_from_version_2_keeps_progress_and_old_terrain() -> void:
	use_sandbox("migrate_v2")
	var original := _write_old_save(2, _v2_state())
	# a first-generation dig site from the small planet
	var legacy := SaveSystem.save_dir.path_join("terrain_pipseed.sqlite")
	var fake := PackedByteArray()
	for i in 4096:
		fake.append((i * 31 + 7) % 251)
	var f := FileAccess.open(legacy, FileAccess.WRITE)
	f.store_buffer(fake)
	f.close()

	GameState.reset()
	assert_true(SaveSystem.load_game(), "v2 save loads")
	# progression carries over completely
	assert_eq(GameState.money, 12345, "credits kept")
	assert_eq(GameState.tier_of("shovel"), 3, "tool tiers kept")
	assert_eq(GameState.tier_of("drill"), 2, "second tool family kept")
	assert_eq(GameState.gear_level("backpack"), 3, "gear kept")
	assert_eq(GameState.gear_level("scanner"), 1, "scanner kept")
	assert_eq(int(GameState.mods.get("drill/turbo", 0)), 1, "attachments kept")
	assert_eq(int(GameState.inventory.get("copper", 0)), 7, "inventory kept")
	assert_true(GameState.has_discovery("time_capsule"), "discoveries kept")
	assert_eq(GameState.equipped, "drill", "equipped tool kept")
	assert_eq(GameState.slot_seed, 77, "slot seed kept")
	assert_eq(int(GameState.terrain_generations.get("pipseed", 0)), 1, "remembers the save was made on generation 1")
	# a verbatim copy of the pre-migration save is kept next to it
	var copy := SaveSystem.save_dir.path_join("progress.v2.json")
	assert_true(FileAccess.file_exists(copy), "pre-migration copy written")
	assert_eq(FileAccess.get_file_as_string(copy), original, "copy is byte-identical to the v2 save")
	# terrain: the new generation uses its own database; the old one is untouched
	var path := SaveSystem.terrain_db_path("pipseed")
	assert_true(path.ends_with("terrain_pipseed_g%d.sqlite" % SaveSystem.terrain_generation("pipseed")), "generation-specific terrain file (%s)" % path.get_file())
	assert_true(path.get_file() != legacy.get_file(), "never the legacy file")
	assert_true(SaveSystem.archived_terrain_files().has("terrain_pipseed.sqlite"), "legacy file reported as archived")
	# saving writes v3 and leaves both the copy and the old terrain alone
	assert_true(SaveSystem.save_game(), "save after migration")
	GameState.reset()
	assert_true(SaveSystem.load_game(), "v3 save loads")
	assert_eq(GameState.money, 12345, "credits survive the round trip")
	assert_false(FileAccess.file_exists(SaveSystem.save_dir.path_join("progress.v3.json")), "no copy made for a current save")
	assert_eq(FileAccess.get_file_as_string(copy), original, "pre-migration copy unchanged")
	assert_eq(FileAccess.get_file_as_bytes(legacy), fake, "legacy terrain bytes unchanged")


func test_migration_falls_back_to_backup_and_still_copies_it() -> void:
	use_sandbox("migrate_v2_backup")
	var original := _write_old_save(2, _v2_state())
	var dir := DirAccess.open(SaveSystem.save_dir)
	dir.rename(SaveSystem.SAVE_FILE, SaveSystem.BACKUP_FILE)
	var f := FileAccess.open(SaveSystem.save_dir.path_join(SaveSystem.SAVE_FILE), FileAccess.WRITE)
	f.store_string("{ truncated")
	f.close()
	GameState.reset()
	assert_true(SaveSystem.load_game(), "recovers the v2 backup")
	assert_eq(GameState.money, 12345, "progress from the backup")
	assert_eq(FileAccess.get_file_as_string(SaveSystem.save_dir.path_join("progress.v2.json")), original, "the readable v2 file was preserved")


func test_v3_round_trip_keeps_terrain_generations() -> void:
	use_sandbox("v3")
	GameState.reset()
	GameState.terrain_generations = {"pipseed": 2, "glimmerock": 2, "nowhere": 5}
	assert_true(SaveSystem.save_game(), "saved")
	GameState.reset()
	assert_true(SaveSystem.load_game(), "loaded")
	assert_eq(int(GameState.terrain_generations.get("pipseed", 0)), 2, "generation stored")
	assert_false(GameState.terrain_generations.has("nowhere"), "unknown planets dropped")
