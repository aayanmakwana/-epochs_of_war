extends Node
## Root of the application. Owns the current "screen" (start menu, nation
## select, game, end screen) and swaps between them (step 19).
##
## The main scene is now res://scenes/start_screen.tscn.
## main.tscn still exists but is no longer the entry point.

const GAME_SCENE         := "res://scenes/game/game.tscn"
const START_SCENE        := "res://scenes/start_screen.tscn"
const NATION_SELECT_SCENE := "res://scenes/nation_select.tscn"
const END_SCENE          := "res://scenes/end_screen.tscn"

var current_screen: Node = null


func _ready() -> void:
	EventBus.game_over.connect(_on_game_over)
	EventBus.province_captured.connect(_on_province_captured)


# ---------------------------------------------------------------------------
# Screen transitions
# ---------------------------------------------------------------------------

func show_start_screen() -> void:
	change_screen((load(START_SCENE) as PackedScene).instantiate())


func show_nation_select() -> void:
	change_screen((load(NATION_SELECT_SCENE) as PackedScene).instantiate())


func start_game_screen() -> void:
	change_screen((load(GAME_SCENE) as PackedScene).instantiate())


func show_end_screen(result: String) -> void:
	var screen: Node = (load(END_SCENE) as PackedScene).instantiate()
	change_screen(screen)
	# show_result needs the node to be in the tree first.
	if screen.has_method("show_result"):
		screen.show_result(result)


## Replace the current screen with [param screen].
func change_screen(screen: Node) -> void:
	if current_screen != null and is_instance_valid(current_screen):
		current_screen.queue_free()
	current_screen = screen
	add_child(screen)


# ---------------------------------------------------------------------------
# End-condition: province_captured -> check capitals -> game_over
# ---------------------------------------------------------------------------

func _on_province_captured(province_id: String, new_controller: String, old_controller: String) -> void:
	# Only care about capital provinces.
	if not GameData.is_capital(province_id):
		return
	# Check whether old_controller still owns any capital.
	var has_capital := false
	for nid in GameData.nation_ids:
		var cap: String = GameData.nation(nid).get("capital", "")
		if cap == "":
			continue
		# A nation's capital is "lost" when its province is no longer
		# controlled by the original owner.
		if nid == old_controller:
			var ps: Object = GameState.province(cap)
			if ps != null and ps.controller == old_controller:
				has_capital = true
				break
	if has_capital:
		return  # Still has at least one capital – no game over yet.
	# old_controller has lost all capitals.
	if not GameState.game_over:
		var result: String = "defeat" if old_controller == GameState.player_nation else "victory"
		GameState.game_over = true
		TimeManager.pause()
		EventBus.game_over.emit(result)


# ---------------------------------------------------------------------------
# game_over signal handler
# ---------------------------------------------------------------------------

func _on_game_over(result: String) -> void:
	show_end_screen(result)
