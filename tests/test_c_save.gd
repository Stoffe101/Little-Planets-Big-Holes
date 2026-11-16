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
