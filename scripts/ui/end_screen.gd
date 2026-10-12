extends Control
## End screen (step 19).
## Shows the game result (victory / defeat), stats, and a Main Menu button.

@onready var _result_label: Label = $VBox/ResultLabel
@onready var _stats_label: Label = $VBox/StatsLabel
@onready var _btn_menu: Button = $VBox/MainMenuButton


func _ready() -> void:
	_btn_menu.pressed.connect(_on_main_menu)
	# Result is passed via Main.pop_result() because change_scene_to_file
	# replaces the tree before show_result() can be called externally.
	var main: Node = get_node_or_null("/root/Main")
	if main and main.has_method("pop_result"):
		show_result(main.pop_result())


## Called by Main when the game ends.
func show_result(result: String) -> void:
	if result == "victory":
		_result_label.text = "VICTORY!"
		_result_label.modulate = Color(0.2, 1.0, 0.2)
	else:
		_result_label.text = "DEFEAT"
		_result_label.modulate = Color(1.0, 0.2, 0.2)

	var gs: Node = get_node_or_null("/root/GameState")
	if gs == null:
		return

	# Gather stats.
	var provinces_conquered: int = 0
	var battles_won: int = 0
	var divisions_lost: int = 0
	var time_played: float = 0.0

	var player_id: String = gs.player_nation
	# Provinces conquered = provinces controlled by player that are not originally owned by player.
	var gd: Node = get_node_or_null("/root/GameData")
	if gd:
		for pid in gd.province_ids:
			var ps: Object = gs.province(pid)
			if ps == null:
				continue
			var original_owner: String = gd.province(pid).get("owner", "")
			if ps.controller == player_id and original_owner != player_id:
				provinces_conquered += 1

	# Battles won: tracked via GameState if available, otherwise 0.
	if gs.has_method("battles_won"):
		battles_won = gs.battles_won(player_id)
	elif gs.get("_battles_won") != null:
		battles_won = gs._battles_won.get(player_id, 0)

	# Divisions lost: tracked via GameState if available.
	if gs.has_method("divisions_lost"):
		divisions_lost = gs.divisions_lost(player_id)
	elif gs.get("_divisions_lost") != null:
		divisions_lost = gs._divisions_lost.get(player_id, 0)

	time_played = gs.time_played

	var minutes: int = int(time_played) / 60
	var seconds: int = int(time_played) % 60

	_stats_label.text = (
		"Provinces conquered: %d\n" % provinces_conquered +
		"Battles won: %d\n" % battles_won +
		"Divisions lost: %d\n" % divisions_lost +
		"Time played: %02d:%02d" % [minutes, seconds]
	)


func _on_main_menu() -> void:
	var main: Node = get_node_or_null("/root/Main")
	if main:
		main.show_start_screen()
