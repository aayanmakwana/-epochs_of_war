extends Node
## Root of the application. Owns the current "screen" (start menu, nation
## select, game, end screen) and swaps between them (step 19).
##
## Registered as an autoload ("Main"). Uses get_tree().change_scene_to_file()
## so the scene tree root is always the active screen.

const GAME_SCENE          := "res://scenes/game/game.tscn"
const START_SCENE         := "res://scenes/start_screen.tscn"
const NATION_SELECT_SCENE := "res://scenes/nation_select.tscn"
const END_SCENE           := "res://scenes/end_screen.tscn"

# Kept for compatibility; not used for scene management any more.
var current_screen: Node = null


func _ready() -> void:
	EventBus.game_over.connect(_on_game_over)
	EventBus.province_captured.connect(_on_province_captured)


# ---------------------------------------------------------------------------
# Screen transitions
# ---------------------------------------------------------------------------

func show_start_screen() -> void:
	get_tree().change_scene_to_file(START_SCENE)


func show_nation_select() -> void:
	get_tree().change_scene_to_file(NATION_SELECT_SCENE)


func start_game_screen() -> void:
	get_tree().change_scene_to_file(GAME_SCENE)


func show_end_screen(result: String) -> void:
	# Store result so the end screen can read it after the scene change.
	_pending_result = result
	get_tree().change_scene_to_file(END_SCENE)


var _pending_result: String = ""


## Called by end_screen.gd in its _ready() to get the result string.
func pop_result() -> String:
	var r := _pending_result
	_pending_result = ""
	return r


# ---------------------------------------------------------------------------
# End-condition: province_captured -> check capitals -> game_over
# ---------------------------------------------------------------------------

func _on_province_captured(province_id: String, new_controller: String, old_controller: String) -> void:
	if not GameData.is_capital(province_id):
		return
	var has_capital := false
	for nid in GameData.nation_ids:
		var cap: String = GameData.nation(nid).get("capital", "")
		if cap == "" or nid != old_controller:
			continue
		var ps: Object = GameState.province(cap)
		if ps != null and ps.controller == old_controller:
			has_capital = true
			break
	if has_capital:
		return
	if not GameState.game_over:
		var result: String = "defeat" if old_controller == GameState.player_nation else "victory"
		GameState.game_over = true
		TimeManager.pause()
		EventBus.game_over.emit(result)


func _on_game_over(result: String) -> void:
	show_end_screen(result)
