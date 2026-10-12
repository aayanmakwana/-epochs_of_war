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
	tactical_view.closed.connect(func(_p: String) -> void: close_tactical())
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
