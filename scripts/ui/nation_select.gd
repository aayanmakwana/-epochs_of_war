extends Control
## Nation selection screen (step 19).
## Shows Germany, USSR and UK with a brief description each.
## Calls GameState.new_game(nation_id) then loads the game scene.

@onready var _title: Label = $VBox/Title
@onready var _desc: Label = $VBox/Description
@onready var _btn_box: HBoxContainer = $VBox/Buttons
@onready var _btn_start: Button = $VBox/StartButton
@onready var _btn_back: Button = $VBox/BackButton

var _selected: String = ""
var _nation_buttons: Dictionary = {}   # nation_id -> Button


func _ready() -> void:
	_btn_start.disabled = true
	_btn_start.pressed.connect(_on_start)
	_btn_back.pressed.connect(_on_back)

	var gd: Node = get_node_or_null("/root/GameData")
	if gd == null:
		return
	for nid in gd.playable_nations():
		var def: Dictionary = gd.nation(nid)
		var btn := Button.new()
		btn.name = "Btn_" + nid
		btn.text = def.get("name", nid)
		btn.toggle_mode = true
		btn.pressed.connect(_on_nation_pressed.bind(nid))
		_btn_box.add_child(btn)
		_nation_buttons[nid] = btn


func _on_nation_pressed(nid: String) -> void:
	_selected = nid
	var gd: Node = get_node_or_null("/root/GameData")
	var desc := ""
	if gd:
		desc = gd.nation(nid).get("description", "")
	_desc.text = desc
	_btn_start.disabled = false
	# Untoggle other buttons.
	for id in _nation_buttons:
		var b: Button = _nation_buttons[id]
		b.button_pressed = (id == nid)


func _on_start() -> void:
	if _selected == "":
		return
	var gs: Node = get_node_or_null("/root/GameState")
	if gs:
		gs.new_game(_selected)
	var main: Node = get_node_or_null("/root/Main")
	if main:
		main.start_game_screen()


func _on_back() -> void:
	var main: Node = get_node_or_null("/root/Main")
	if main:
		main.show_start_screen()
