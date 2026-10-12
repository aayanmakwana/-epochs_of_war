extends Control
## Start screen (step 19).
## Shows "New Game" and "Load Game" buttons.
## Loaded as the main scene; swaps to nation select or game via Main.

@onready var btn_new: Button = $VBox/NewGameButton
@onready var btn_load: Button = $VBox/LoadGameButton


func _ready() -> void:
	btn_new.pressed.connect(_on_new_game)
	btn_load.pressed.connect(_on_load_game)
	# Disable Load if no save exists.
	var sl: Node = get_node_or_null("/root/SaveLoad")
	if sl:
		btn_load.disabled = not sl.has_save()
	else:
		btn_load.disabled = true


func _on_new_game() -> void:
	var main: Node = get_node_or_null("/root/Main")
	if main:
		main.show_nation_select()


func _on_load_game() -> void:
	var sl: Node = get_node_or_null("/root/SaveLoad")
	if sl and sl.has_save():
		sl.load_game()
		var main: Node = get_node_or_null("/root/Main")
		if main:
			main.start_game_screen()
