extends Node
## The in-game screen: strategic map world + HUD canvas layer.
## Expects GameState to be active (new game or loaded) before it is added.

@onready var map_view: MapView = $World/MapView
@onready var camera: MapCamera = $World/MapCamera
@onready var ui_layer: CanvasLayer = $UI
@onready var hud: Hud = $UI/HUD


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
