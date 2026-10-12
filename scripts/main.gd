extends Node
## Root of the application. Owns the current "screen" (start menu, game,
## end screen ...) and swaps between them.
##
## Until the start screen exists (step 19) it boots straight into a new game.
## Pick the nation from the command line:  godot --path . -- --nation=ussr

const GAME_SCENE := "res://scenes/game/game.tscn"

var current_screen: Node = null


func _ready() -> void:
	if not GameState.active:
		GameState.new_game(_nation_from_cmdline())
	start_game_screen()


func _nation_from_cmdline() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--nation="):
			var nid := arg.trim_prefix("--nation=")
			if GameData.playable_nations().has(nid):
				return nid
	return "germany"


func start_game_screen() -> void:
	change_screen((load(GAME_SCENE) as PackedScene).instantiate())


## Replace the current screen with [param screen].
func change_screen(screen: Node) -> void:
	if current_screen != null and is_instance_valid(current_screen):
		current_screen.queue_free()
	current_screen = screen
	add_child(screen)
