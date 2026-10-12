extends "res://tests/test_base.gd"
## Step 18: save / load tests.
## Verifies that SaveLoad writes GameState to disk and restores it correctly.

func run_tests() -> void:
	var gs: Node = autoload("GameState")
	var sl: Node = autoload("SaveLoad")
	autoload("AI").enabled = false

	check(sl != null, "SaveLoad autoload exists")

	# ---- basic save / load round-trip ----------------------------------------
	gs.new_game("germany")
	# Mutate something observable: change a province controller.
	var ps: ProvinceState = gs.province("poland")
	var original_owner: String = ps.owner
	ps.controller = "germany"   # occupy poland

	var day_before: int = gs.day_index
	var player_before: String = gs.player_nation

	var ok_save: bool = sl.save_game("test")
	check(ok_save, "save_game returns true")
	check(sl.has_save("test"), "has_save is true after saving")

	# Overwrite state with a different game.
	gs.new_game("ussr")
	check_eq(gs.player_nation, "ussr", "player is ussr after new_game")

	var ok_load: bool = sl.load_game("test")
	check(ok_load, "load_game returns true")

	check_eq(gs.player_nation, player_before, "player_nation restored")
	check_eq(gs.day_index, day_before, "day_index restored")
	check_eq(gs.province("poland").controller, "germany", "province controller restored")
	check_eq(gs.province("poland").owner, original_owner, "province owner restored")

	# ---- autosave fires after autosave_interval_days -------------------------
	gs.new_game("germany")
	var interval: int = int(autoload("GameData").rule("autosave_interval_days", 30))
	# Delete any existing autosave so we can detect a fresh one.
	var auto_path := "user://saves/auto.json"
	if FileAccess.file_exists(auto_path):
		DirAccess.remove_absolute(auto_path)

	# Advance days via TimeManager.advance_days (bypasses pause).
	var tm: Node = autoload("TimeManager")
	tm.advance_days(interval)
	await process_frame

	check(sl.has_save("auto"), "autosave created after %d days" % interval)

	# ---- load non-existent slot returns false --------------------------------
	var bad: bool = sl.load_game("no_such_slot_xyz")
	check(not bad, "load_game returns false for missing slot")

	# ---- save signals --------------------------------------------------------
	gs.new_game("germany")
	var saved_slots: Array = []
	var loaded_slots: Array = []
	sl.saved.connect(func(s: String) -> void: saved_slots.append(s), CONNECT_ONE_SHOT)
	sl.loaded.connect(func(s: String) -> void: loaded_slots.append(s), CONNECT_ONE_SHOT)

	sl.save_game("sig_test")
	check_eq(saved_slots, ["sig_test"], "saved signal emitted with slot name")

	sl.load_game("sig_test")
	check_eq(loaded_slots, ["sig_test"], "loaded signal emitted with slot name")

	# ---- key fields survive JSON round-trip ----------------------------------
	gs.new_game("uk")
	gs.day_index = 42
	gs.hour = 6
	sl.save_game("roundtrip")
	gs.new_game("germany")
	sl.load_game("roundtrip")
	check_eq(gs.player_nation, "uk", "player_nation survives JSON round-trip")
	check_eq(gs.day_index, 42, "day_index survives JSON round-trip")
	check_eq(gs.hour, 6, "hour survives JSON round-trip")
