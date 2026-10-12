class_name DrawLayer
extends Node2D
## A Node2D whose _draw() is delegated to a Callable(canvas: CanvasItem).
## MapView uses one per visual layer (borders, highlight, units, fog ...)
## so each layer can be redrawn independently with queue_redraw().

var draw_func: Callable


func _init(func_to_call: Callable = Callable(), layer_name: String = "") -> void:
	draw_func = func_to_call
	if layer_name != "":
		name = layer_name


func _draw() -> void:
	if draw_func.is_valid():
		draw_func.call(self)
