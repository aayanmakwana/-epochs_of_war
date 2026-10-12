class_name Minimap
extends PanelContainer
## Bottom-right minimap: the whole map scaled down plus a rectangle showing
## the camera's visible area. Click or drag on it to move the camera.

var map_view: MapView
var camera: MapCamera
var canvas: MinimapCanvas


func _ready() -> void:
	name = "Minimap"
	mouse_filter = Control.MOUSE_FILTER_STOP
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 1.0
	anchor_bottom = 1.0
	var h := UIStyle.MINIMAP_WIDTH * 0.62 + 20
	offset_left = -UIStyle.MINIMAP_WIDTH - UIStyle.MARGIN
	offset_right = -UIStyle.MARGIN
	offset_top = -h - UIStyle.MARGIN
	offset_bottom = -UIStyle.MARGIN
	add_theme_stylebox_override("panel", _style())
	canvas = MinimapCanvas.new()
	canvas.name = "Canvas"
	canvas.owner_minimap = self
	canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(canvas)
	EventBus.province_changed.connect(func(_p: String) -> void: canvas.queue_redraw())
	EventBus.game_state_ready.connect(canvas.queue_redraw)
	EventBus.fog_changed.connect(canvas.queue_redraw)   # step 12: hidden provinces drawn grey


func _style() -> StyleBoxFlat:
	var sb := UIStyle.panel_box(Color(0.05, 0.08, 0.12, 0.95), 2, 4)
	sb.set_content_margin_all(4)
	return sb


func setup(view: MapView, cam: MapCamera) -> void:
	map_view = view
	camera = cam
	camera.view_changed.connect(canvas.queue_redraw)
	canvas.queue_redraw()


## Scale and offset that fit the map bounds into the canvas (keeps aspect).
func map_transform() -> Transform2D:
	var b: Rect2 = GameData.geometry.bounds()
	var sz := canvas.size
	if b.size.x <= 0 or b.size.y <= 0 or sz.x <= 0 or sz.y <= 0:
		return Transform2D.IDENTITY
	var s := minf(sz.x / b.size.x, sz.y / b.size.y)
	var off := (sz - b.size * s) * 0.5 - b.position * s
	return Transform2D(0.0, Vector2(s, s), 0.0, off)


## Canvas-local point -> world point.
func to_world(local: Vector2) -> Vector2:
	return map_transform().affine_inverse() * local


## World point -> canvas-local point.
func to_local_point(world: Vector2) -> Vector2:
	return map_transform() * world


## Viewport rectangle in canvas coordinates.
func viewport_rect_local() -> Rect2:
	if camera == null:
		return Rect2()
	var r := camera.visible_world_rect()
	var t := map_transform()
	return Rect2(t * r.position, r.size * t.get_scale())


## Centre the camera on the world point under canvas-local [param local].
func focus_local(local: Vector2) -> void:
	if camera:
		camera.focus_on(to_world(local))


class MinimapCanvas extends Control:
	var owner_minimap: Minimap
	var _dragging := false

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		clip_contents = true

	func _draw() -> void:
		var m := owner_minimap
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.1, 0.18, 0.27))
		var t := m.map_transform()
		draw_set_transform_matrix(t)
		for pid in GameData.province_ids:
			var col: Color = m.map_view.province_display_color(pid) if m.map_view else GameData.nation_color(GameData.province(pid).get("owner", ""))
			for loop: PackedVector2Array in GameData.geometry.outlines.get(pid, []):
				draw_colored_polygon(loop, col)
		draw_set_transform_matrix(Transform2D.IDENTITY)
		var vr := m.viewport_rect_local().intersection(Rect2(Vector2.ZERO, size))
		if vr.has_area():
			draw_rect(vr, Color(1, 1, 1, 0.12))
			draw_rect(vr, Color(1, 0.95, 0.7, 0.95), false, 1.5)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			_dragging = event.pressed
			if event.pressed:
				owner_minimap.focus_local(event.position)
			accept_event()
		elif event is InputEventMouseMotion and _dragging:
			owner_minimap.focus_local(event.position)
			accept_event()
