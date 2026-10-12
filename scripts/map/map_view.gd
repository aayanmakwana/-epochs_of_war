class_name MapView
extends Node2D
## Renders the strategic map from GameData.geometry + GameState.
##
## Child layers, bottom to top:
##   Fills      one Polygon2D per province outline (nation colour)
##   Borders    DrawLayer: province borders, nation borders, coastlines, city markers
##   Fronts     DrawLayer: front lines (step 10) - empty for now
##   Highlight  DrawLayer: hover / selection outline
##   Units      DrawLayer: division icons (step 8) - empty for now
##   Labels     Label per province
##   Fog        DrawLayer: fog of war (step 12) - empty for now
## Later steps add drawing code by giving the layer a draw_func, or by
## extending the _draw_* methods below, then call refresh_layer().

const LAND_TERRAIN_BLEND := 0.18
const SEA_OWNER_BLEND := 0.12
const BORDER_PROVINCE := Color(0, 0, 0, 0.35)
const BORDER_NATION := Color(0.06, 0.06, 0.06, 0.95)
const BORDER_COAST := Color(0.05, 0.1, 0.18, 0.9)
const HOVER_FILL := Color(1, 1, 1, 0.13)
const SELECT_LINE := Color(1, 1, 0.75, 1)

var geometry: MapGeometry
var camera: MapCamera
var selected_province: String = ""
var hovered_province: String = ""

## pid -> Array[Polygon2D]
var fill_nodes: Dictionary = {}
## pid -> Label
var label_nodes: Dictionary = {}
var layers: Dictionary = {}   # layer name -> Node2D


func _ready() -> void:
	build()
	EventBus.game_state_ready.connect(refresh_all)
	EventBus.province_changed.connect(_on_province_changed)
	EventBus.selection_cleared.connect(_on_selection_cleared)


## (Re)create all child nodes from the geometry.
func build() -> void:
	for c in get_children():
		if c != camera:
			remove_child(c)   # detach now so rebuilt nodes keep their names
			c.queue_free()
	fill_nodes.clear()
	label_nodes.clear()
	layers.clear()
	geometry = GameData.geometry

	var fills := Node2D.new()
	fills.name = "Fills"
	add_child(fills)
	layers["Fills"] = fills
	for pid in GameData.province_ids:
		var polys: Array = []
		for loop: PackedVector2Array in geometry.outlines.get(pid, []):
			var poly := Polygon2D.new()
			poly.polygon = loop
			poly.antialiased = true
			poly.name = pid
			fills.add_child(poly)
			polys.append(poly)
		fill_nodes[pid] = polys

	_add_layer("Borders", _draw_borders)
	_add_layer("Fronts", _draw_fronts)
	_add_layer("Highlight", _draw_highlight)
	_add_layer("Units", _draw_units)

	var labels := Node2D.new()
	labels.name = "Labels"
	add_child(labels)
	layers["Labels"] = labels
	for pid in GameData.province_ids:
		var lbl := Label.new()
		lbl.text = GameData.province_name(pid)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", 17)
		lbl.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
		lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		lbl.add_theme_constant_override("outline_size", 5)
		lbl.size = Vector2(200, 24)
		lbl.position = geometry.anchors[pid] - Vector2(100, 22)
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		labels.add_child(lbl)
		label_nodes[pid] = lbl

	_add_layer("Fog", _draw_fog)
	refresh_all()


func _add_layer(layer_name: String, func_to_call: Callable) -> DrawLayer:
	var layer := DrawLayer.new(func_to_call, layer_name)
	add_child(layer)
	layers[layer_name] = layer
	return layer


func set_camera(cam: MapCamera) -> void:
	camera = cam
	camera.view_changed.connect(_on_view_changed)


func refresh_all() -> void:
	for pid in fill_nodes:
		_update_fill(pid)
	for layer_name in layers:
		refresh_layer(layer_name)


func refresh_layer(layer_name: String) -> void:
	var layer: Node2D = layers.get(layer_name)
	if layer:
		layer.queue_redraw()


## Fill colour of a province from its controller (or 1936 owner if no game).
func province_color(pid: String) -> Color:
	var nid: String = GameData.province(pid).get("owner", "")
	var ps: ProvinceState = GameState.province(pid) if GameState.active else null
	if ps:
		nid = ps.controller
	var nation_col := GameData.nation_color(nid)
	var terrain_col := Color.from_string(GameData.terrain_of(pid).get("color", "#808080"), Color.GRAY)
	if GameData.is_naval(pid):
		return terrain_col.lerp(nation_col, SEA_OWNER_BLEND)
	return nation_col.lerp(terrain_col, LAND_TERRAIN_BLEND)


func _update_fill(pid: String) -> void:
	var col := province_color(pid)
	for poly: Polygon2D in fill_nodes.get(pid, []):
		poly.color = col


func _controller(pid: String) -> String:
	if GameState.active and GameState.province(pid):
		return GameState.province(pid).controller
	return GameData.province(pid).get("owner", "")


## Screen-constant line width in world units.
func px(pixels: float) -> float:
	var z := camera.zoom_level() if camera else 1.0
	return pixels / z


# --- Selection / input -------------------------------------------------------

func province_at(world_pos: Vector2) -> String:
	return geometry.province_at(world_pos)


## Select the province under [param world_pos]. Returns the province id ("" = none).
func click_at(world_pos: Vector2) -> String:
	var pid := province_at(world_pos)
	if pid == "":
		clear_selection()
	else:
		select_province(pid)
	return pid


func select_province(pid: String) -> void:
	selected_province = pid
	refresh_layer("Highlight")
	EventBus.province_selected.emit(pid)


func clear_selection() -> void:
	if selected_province == "":
		return
	selected_province = ""
	refresh_layer("Highlight")
	EventBus.selection_cleared.emit()


func _on_selection_cleared() -> void:
	if selected_province != "":
		selected_province = ""
		refresh_layer("Highlight")


func set_hovered(pid: String) -> void:
	if pid == hovered_province:
		return
	hovered_province = pid
	refresh_layer("Highlight")
	EventBus.province_hovered.emit(pid)


## Viewport (screen) position of a mouse event -> world position. Uses the
## event's own position rather than the OS cursor (works with injected events).
func _event_world_pos(screen_pos: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform().affine_inverse() * screen_pos


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			if camera == null or not camera.was_drag():
				click_at(_event_world_pos(mb.position))
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			var pid := province_at(_event_world_pos(mb.position))
			if pid != "":
				EventBus.province_right_clicked.emit(pid)
	elif event is InputEventMouseMotion:
		set_hovered(province_at(_event_world_pos((event as InputEventMouseMotion).position)))


func _on_province_changed(pid: String) -> void:
	_update_fill(pid)
	refresh_layer("Borders")


func _on_view_changed() -> void:
	# Line widths are zoom dependent.
	refresh_layer("Borders")
	refresh_layer("Highlight")
	refresh_layer("Fronts")


# --- Layer drawing -----------------------------------------------------------

func _draw_borders(canvas: CanvasItem) -> void:
	for key: String in geometry.borders:
		var parts := key.split("|")
		var a: String = parts[0]
		var b: String = parts[1]
		var col := BORDER_PROVINCE
		var width := px(1.0)
		if b == "" or GameData.is_naval(a) != GameData.is_naval(b):
			col = BORDER_COAST
			width = px(2.0)
		elif _controller(a) != _controller(b):
			col = BORDER_NATION
			width = px(2.6)
		for seg: PackedVector2Array in geometry.borders[key]:
			canvas.draw_polyline(seg, col, width, true)
	# City markers below the label.
	for pid in GameData.province_ids:
		var p: Vector2 = geometry.anchors[pid] + Vector2(0, 14)
		if GameData.is_capital(pid):
			_draw_star(canvas, p, 9.0, Color(1, 0.85, 0.2), Color(0, 0, 0, 0.8))
		elif GameData.is_major_city(pid):
			canvas.draw_circle(p, 6.0, Color(0, 0, 0, 0.8))
			canvas.draw_circle(p, 4.5, Color(1, 1, 1))


func _draw_star(canvas: CanvasItem, center: Vector2, radius: float, fill: Color, outline: Color) -> void:
	var pts := PackedVector2Array()
	for i in 10:
		var r := radius if i % 2 == 0 else radius * 0.45
		var ang := -PI / 2.0 + i * PI / 5.0
		pts.append(center + Vector2(cos(ang), sin(ang)) * r)
	canvas.draw_colored_polygon(pts, fill)
	var closed := pts.duplicate()
	closed.append(pts[0])
	canvas.draw_polyline(closed, outline, 1.5, true)


func _draw_highlight(canvas: CanvasItem) -> void:
	if hovered_province != "":
		for loop: PackedVector2Array in geometry.outlines.get(hovered_province, []):
			canvas.draw_colored_polygon(loop, HOVER_FILL)
	if selected_province != "":
		for loop: PackedVector2Array in geometry.outlines.get(selected_province, []):
			var closed := loop.duplicate()
			closed.append(loop[0])
			canvas.draw_polyline(closed, Color(0, 0, 0, 0.6), px(5.0), true)
			canvas.draw_polyline(closed, SELECT_LINE, px(2.5), true)


func _draw_fronts(_canvas: CanvasItem) -> void:
	pass  # Step 10: front lines between provinces of nations at war.


func _draw_units(_canvas: CanvasItem) -> void:
	pass  # Step 8: division icons at GameData.geometry.anchors.


func _draw_fog(_canvas: CanvasItem) -> void:
	pass  # Step 12: darken provinces not visible to the player.
