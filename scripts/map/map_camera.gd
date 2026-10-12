class_name MapCamera
extends Camera2D
## Strategic map camera: mouse-wheel zoom towards the cursor, drag to pan
## (left or middle button), arrow keys / WASD to pan. Clamped to the map.

signal view_changed

const DRAG_THRESHOLD := 6.0

var min_zoom: float = 0.45
var max_zoom: float = 3.0
var zoom_step: float = 1.15
var key_pan_speed: float = 900.0
var map_bounds: Rect2 = Rect2(0, 0, 2000, 1200)

## Distance the mouse moved since the last button press (to tell clicks from drags).
var drag_distance: float = 0.0
var _drag_button: int = 0


func setup(bounds: Rect2) -> void:
	map_bounds = bounds
	position = bounds.get_center()
	set_zoom_level(0.95)


func zoom_level() -> float:
	return zoom.x


func set_zoom_level(z: float, screen_anchor: Variant = null) -> void:
	z = clampf(z, min_zoom, max_zoom)
	var vp_size := get_viewport_rect().size
	if screen_anchor is Vector2:
		# Keep the world point under the cursor fixed while zooming.
		var offset_px: Vector2 = (screen_anchor as Vector2) - vp_size * 0.5
		var world: Vector2 = position + offset_px / zoom.x
		zoom = Vector2(z, z)
		position = world - offset_px / z
	else:
		zoom = Vector2(z, z)
	clamp_to_bounds()
	view_changed.emit()


func pan_by(world_delta: Vector2) -> void:
	position += world_delta
	clamp_to_bounds()
	view_changed.emit()


func focus_on(world_pos: Vector2) -> void:
	position = world_pos
	clamp_to_bounds()
	view_changed.emit()


func clamp_to_bounds() -> void:
	var b := map_bounds.grow(100)
	position = position.clamp(b.position, b.end)


## World-space rectangle currently visible.
func visible_world_rect() -> Rect2:
	var size := get_viewport_rect().size / zoom.x
	return Rect2(position - size * 0.5, size)


func was_drag() -> bool:
	return drag_distance > DRAG_THRESHOLD


## Runs before the GUI: a drag that started on the map but is released over a
## HUD panel (which consumes the release) must still end the drag.
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and _drag_button != 0:
		var mb := event as InputEventMouseButton
		if not mb.pressed and mb.button_index == _drag_button:
			_drag_button = 0


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			set_zoom_level(zoom.x * zoom_step, mb.position)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			set_zoom_level(zoom.x / zoom_step, mb.position)
		elif mb.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE]:
			if mb.pressed:
				_drag_button = mb.button_index
				drag_distance = 0.0
			elif mb.button_index == _drag_button:
				_drag_button = 0
	elif event is InputEventMouseMotion and _drag_button != 0:
		var mm := event as InputEventMouseMotion
		drag_distance += mm.relative.length()
		if was_drag() or _drag_button == MOUSE_BUTTON_MIDDLE:
			pan_by(-mm.relative / zoom.x)


func _process(delta: float) -> void:
	var dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A):
		dir.x -= 1
	if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D):
		dir.x += 1
	if Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_W):
		dir.y -= 1
	if Input.is_key_pressed(KEY_DOWN) or Input.is_key_pressed(KEY_S):
		dir.y += 1
	if dir != Vector2.ZERO:
		pan_by(dir.normalized() * key_pan_speed * delta / zoom.x)
