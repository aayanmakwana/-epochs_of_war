extends Node
## The in-game screen: strategic map world + HUD canvas layer.
## Expects GameState to be active (new game or loaded) before it is added.

@onready var map_view: MapView = $World/MapView
@onready var camera: MapCamera = $World/MapCamera
@onready var ui_layer: CanvasLayer = $UI


func _ready() -> void:
	camera.setup(GameData.geometry.bounds())
	map_view.set_camera(camera)
	var capital: String = GameData.nation(GameState.player_nation).get("capital", "")
	if capital != "":
		camera.focus_on(GameData.geometry.anchors[capital].lerp(GameData.geometry.bounds().get_center(), 0.5))
