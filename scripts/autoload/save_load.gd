extends Node
## Save / load system (autoload "SaveLoad", step 18).
##
## Saves GameState.to_dict() as JSON to user://saves/<slot>.json.
## Autosaves every rules.autosave_interval_days (30) in-game days on
## EventBus.day_passed.  One save slot is fine; the UI uses slot "auto"
## for autosaves and slot "manual" for explicit saves.

const SAVE_DIR := "user://saves/"
const AUTOSAVE_SLOT := "auto"
const MANUAL_SLOT := "manual"

## Emitted after a successful save (slot name).
signal saved(slot: String)
## Emitted after a successful load (slot name).
signal loaded(slot: String)
## Emitted when a save or load fails (slot name, reason).
signal save_error(slot: String, reason: String)

var _autosave_interval: int = 30
var _days_since_autosave: int = 0


func _ready() -> void:
	_autosave_interval = int(GameData.rule("autosave_interval_days", 30))
	EventBus.day_passed.connect(_on_day_passed)
	EventBus.game_state_ready.connect(_on_game_state_ready)


func _on_game_state_ready() -> void:
	_days_since_autosave = 0


func _on_day_passed(_day_index: int) -> void:
	if GameState.game_over:
		return
	_days_since_autosave += 1
	if _days_since_autosave >= _autosave_interval:
		_days_since_autosave = 0
		save_game(AUTOSAVE_SLOT)


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Save the current GameState to user://saves/<slot>.json.
## Returns true on success.
func save_game(slot: String = MANUAL_SLOT) -> bool:
	if not GameState.player_nation:
		save_error.emit(slot, "No active game")
		return false
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var path := _slot_path(slot)
	var data: Dictionary = GameState.to_dict()
	var json_text: String = JSON.stringify(data, "\t")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		var reason := "Cannot open %s for writing (error %d)" % [path, FileAccess.get_open_error()]
		save_error.emit(slot, reason)
		return false
	file.store_string(json_text)
	file.close()
	saved.emit(slot)
	return true


## Load a save from user://saves/<slot>.json into GameState.
## Returns true on success.
func load_game(slot: String = MANUAL_SLOT) -> bool:
	var path := _slot_path(slot)
	if not FileAccess.file_exists(path):
		save_error.emit(slot, "Save file not found: " + path)
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		save_error.emit(slot, "Cannot open " + path)
		return false
	var text := file.get_as_text()
	file.close()
	var parsed = JSON.parse_string(text)
	if parsed == null or not parsed is Dictionary:
		save_error.emit(slot, "Invalid JSON in " + path)
		return false
	var ok: bool = GameState.load_from_dict(parsed)
	if not ok:
		save_error.emit(slot, "load_from_dict failed for " + path)
		return false
	loaded.emit(slot)
	return true


## True if a save file exists for [param slot].
func has_save(slot: String = MANUAL_SLOT) -> bool:
	return FileAccess.file_exists(_slot_path(slot))


## Path for a given slot name.
func _slot_path(slot: String) -> String:
	return SAVE_DIR + slot + ".json"
