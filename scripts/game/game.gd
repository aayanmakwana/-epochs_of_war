extends Node
## The in-game screen: strategic map world + HUD canvas layer.
## Expects GameState to be active (new game or loaded) before it is added.

@onready var map_view: MapView = $World/MapView
@onready var camera: MapCamera = $World/MapCamera
@onready var ui_layer: CanvasLayer = $UI
@onready var hud: Hud = $UI/HUD

# --- Pause menu (step 18) -------------------------------------------------------
var _pause_layer: CanvasLayer = null
var pause_menu: Control = null


func _build_pause_menu() -> void:
	_pause_layer = CanvasLayer.new()
	_pause_layer.name = "PauseMenuLayer"
	_pause_layer.layer = 20
	add_child(_pause_layer)

	var bg := ColorRect.new()
	bg.name = "PauseMenu"
	bg.color = Color(0, 0, 0, 0.6)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	_pause_layer.add_child(bg)
	pause_menu = bg

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.custom_minimum_size = Vector2(240, 0)
	bg.add_child(box)

	var title := Label.new()
	title.text = "PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var sep := Control.new()
	sep.custom_minimum_size = Vector2(0, 16)
	box.add_child(sep)

	var btn_save := Button.new()
	btn_save.name = "SaveButton"
	btn_save.text = "Save Game"
	btn_save.pressed.connect(func() -> void:
		var sl := get_node_or_null("/root/SaveLoad")
		if sl:
			sl.save_game()
	)
	box.add_child(btn_save)

	var btn_load := Button.new()
	btn_load.name = "LoadButton"
	btn_load.text = "Load Game"
	btn_load.pressed.connect(func() -> void:
		var sl := get_node_or_null("/root/SaveLoad")
		if sl and sl.has_save():
			sl.load_game()
			hide_pause_menu()
	)
	box.add_child(btn_load)

	var btn_resume := Button.new()
	btn_resume.name = "ResumeButton"
	btn_resume.text = "Resume"
	btn_resume.pressed.connect(hide_pause_menu)
	box.add_child(btn_resume)


func show_pause_menu() -> void:
	if _pause_layer == null:
		_build_pause_menu()
	_pause_layer.visible = true
	TimeManager.pause()


func hide_pause_menu() -> void:
	if _pause_layer != null:
		_pause_layer.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE and tactical_view == null:
			if _pause_layer != null and _pause_layer.visible:
				hide_pause_menu()
			else:
				show_pause_menu()
			get_viewport().set_input_as_handled()


func _ready() -> void:
	camera.setup(GameData.geometry.bounds())
	map_view.set_camera(camera)
	hud.setup(map_view, camera)
	var capital: String = GameData.nation(GameState.player_nation).get("capital", "")
	if capital != "":
		camera.focus_on(GameData.geometry.anchors[capital].lerp(GameData.geometry.bounds().get_center(), 0.5))
	EventBus.tactical_battle_requested.connect(open_tactical)
	EventBus.game_state_ready.connect(close_tactical)
	EventBus.tactical_prompt_requested.connect(show_prompt)
	EventBus.game_state_ready.connect(_clear_prompts)
	prompt_dialog = ConfirmationDialog.new()
	prompt_dialog.name = "TacticalPrompt"
	prompt_dialog.title = "City battle"
	prompt_dialog.ok_button_text = "Yes"
	prompt_dialog.cancel_button_text = "No"
	prompt_dialog.confirmed.connect(func() -> void: answer_prompt(true))
	prompt_dialog.canceled.connect(func() -> void: answer_prompt(false))
	add_child(prompt_dialog)


# --- "Battle for X. Command your forces?" prompt (step 17) ----------------------------

var prompt_dialog: ConfirmationDialog
## Province of the prompt on screen ("" = none) and those waiting behind it.
var prompt_province: String = ""
var _prompt_queue: Array[String] = []


func show_prompt(pid: String) -> void:
	if pid == prompt_province or _prompt_queue.has(pid):
		return
	if prompt_province != "":
		_prompt_queue.append(pid)
		return
	prompt_province = pid
	prompt_dialog.dialog_text = "Battle for %s. Command your forces?" % GameData.province_name(pid)
	prompt_dialog.popup_centered()


## Yes -> tactical view (Combat.accept_tactical); No -> auto-resolve and resume the clock.
func answer_prompt(yes: bool) -> void:
	var pid := prompt_province
	if pid == "":
		return
	prompt_province = ""
	if prompt_dialog.visible:
		prompt_dialog.hide()
	var combat := get_node_or_null("/root/Combat")
	if yes and combat and combat.accept_tactical(pid):
		pass
	else:
		if combat:
			combat.decline_tactical(pid)
		if _prompt_queue.is_empty():
			TimeManager.resume()
	if not _prompt_queue.is_empty():
		show_prompt(_prompt_queue.pop_front())


func _clear_prompts() -> void:
	prompt_province = ""
	_prompt_queue.clear()
	if prompt_dialog and prompt_dialog.visible:
		prompt_dialog.hide()


# --- Tactical view (step 15) ---------------------------------------------------------

const TACTICAL_SCENE := "res://scenes/tactical/tactical_view.tscn"

## Open tactical view, or null. Lives on its own CanvasLayer above the HUD.
var tactical_view: TacticalView = null
var _tactical_layer: CanvasLayer = null


## Replace the strategic view with the tactical grid for [param pid]
## (pauses the clock; the World and HUD are hidden and stop processing).
func open_tactical(pid: String) -> void:
	close_tactical()
	_tactical_layer = CanvasLayer.new()
	_tactical_layer.name = "TacticalLayer"
	_tactical_layer.layer = 10
	add_child(_tactical_layer)
	tactical_view = (load(TACTICAL_SCENE) as PackedScene).instantiate()
	_tactical_layer.add_child(tactical_view)
	var view := tactical_view
	tactical_view.closed.connect(func(_p: String) -> void:
		var done := view.phase == "finished"
		close_tactical()
		if done:
			TimeManager.resume())   # results applied: back to the map, clock running
	$World.visible = false
	$World.process_mode = Node.PROCESS_MODE_DISABLED
	ui_layer.visible = false
	hud.process_mode = Node.PROCESS_MODE_DISABLED
	tactical_view.open(pid)


## Back to the strategic view (no-op when no tactical view is open).
func close_tactical() -> void:
	if _tactical_layer != null and is_instance_valid(_tactical_layer):
		_tactical_layer.queue_free()
	_tactical_layer = null
	tactical_view = null
	$World.visible = true
	$World.process_mode = Node.PROCESS_MODE_INHERIT
	ui_layer.visible = true
	hud.process_mode = Node.PROCESS_MODE_INHERIT
