extends Node
## Root of the application. Owns the current "screen" (start menu, game,
## end screen ...) and swaps between them.

var current_screen: Node = null


func _ready() -> void:
	var label := Label.new()
	label.text = "Epochs of War"
	label.set_anchors_preset(Control.PRESET_CENTER)
	change_screen(label)


## Replace the current screen with [param screen].
func change_screen(screen: Node) -> void:
	if current_screen != null and is_instance_valid(current_screen):
		current_screen.queue_free()
	current_screen = screen
	add_child(screen)
