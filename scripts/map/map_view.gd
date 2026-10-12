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
const UNIT_BOX := Vector2(46, 18)
const UNIT_LETTERS := {"infantry": "I", "armor": "A", "artillery": "R"}

var geometry: MapGeometry
var camera: MapCamera
var selected_province: String = ""
var hovered_province: String = ""
## Step 9: player divisions selected for move orders (ids).
var selected_divisions: Array[int] = []
const ORDER_LINE := Color(1, 0.92, 0.35, 0.95)
const PREVIEW_LINE := Color(1, 1, 1, 0.55)

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
	EventBus.division_created.connect(_on_divisions_changed)
	EventBus.division_destroyed.connect(_on_divisions_changed)
	EventBus.division_moved.connect(_on_divisions_changed)
	EventBus.province_changed.connect(_on_divisions_changed)
	EventBus.division_order_changed.connect(_on_divisions_changed)
	EventBus.day_passed.connect(_on_day_for_units)
	EventBus.division_selected.connect(_on_division_selected)
	EventBus.division_destroyed.connect(_on_division_destroyed)
	EventBus.divisions_selected.connect(func(ids: Array) -> void:
		if ids.is_empty():
			clear_unit_selection())
	EventBus.game_state_ready.connect(func() -> void: selected_divisions.clear())


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
## Step 9: with player divisions selected, clicking another province orders
## them to move there (the click does not change the province selection).
## Clicking a player unit icon selects the province and its player divisions.
func click_at(world_pos: Vector2) -> String:
	var pid := province_at(world_pos)
	var icon := unit_icon_at(world_pos)
	if not icon.is_empty() and String(icon.owner) == GameState.player_nation:
		var ip: String = icon.province
		select_province(ip)
		var ids: Array[int] = []
		for d: DivisionState in GameState.divisions_in(ip):
			if d.owner == GameState.player_nation:
				ids.append(d.id)
		ids.sort()
		select_divisions(ids)
		return ip
	if pid != "" and not selected_divisions.is_empty() and not _units_in(pid):
		order_selected_move(pid)
		return pid
	if pid == "":
		clear_selection()
	else:
		select_province(pid)
	return pid


func select_province(pid: String) -> void:
	clear_unit_selection()
	selected_province = pid
	refresh_layer("Highlight")
	EventBus.province_selected.emit(pid)


func clear_selection() -> void:
	clear_unit_selection()
	if selected_province == "":
		return
	selected_province = ""
	refresh_layer("Highlight")
	EventBus.selection_cleared.emit()


func _on_selection_cleared() -> void:
	clear_unit_selection()
	if selected_province != "":
		selected_province = ""
		refresh_layer("Highlight")


# --- Unit selection / move orders (step 9) -----------------------------------

## Select player divisions for move orders; emits divisions_selected(ids).
func select_divisions(ids: Array) -> void:
	selected_divisions.clear()
	for did in ids:
		var d: DivisionState = GameState.division(int(did))
		if d and d.owner == GameState.player_nation:
			selected_divisions.append(d.id)
	refresh_layer("Units")
	EventBus.divisions_selected.emit(selected_divisions.duplicate())


func clear_unit_selection() -> void:
	if selected_divisions.is_empty():
		return
	selected_divisions.clear()
	refresh_layer("Units")


func _on_division_selected(did: int) -> void:
	var d: DivisionState = GameState.division(did)
	selected_divisions.clear()
	if d and d.owner == GameState.player_nation:
		selected_divisions.append(did)
	refresh_layer("Units")


func _on_division_destroyed(did: int) -> void:
	selected_divisions.erase(did)


## True if every selected division is already in [param pid].
func _units_in(pid: String) -> bool:
	for did in selected_divisions:
		var d: DivisionState = GameState.division(did)
		if d and d.province != pid:
			return false
	return true


## Order the selected divisions to [param pid]. Returns the number that moved.
func order_selected_move(pid: String) -> int:
	var mv := get_node_or_null("/root/Movement")
	if mv == null or selected_divisions.is_empty():
		return 0
	var moved := 0
	var reason := ""
	for did in selected_divisions:
		var d: DivisionState = GameState.division(did)
		if d == null or d.province == pid:
			continue
		if mv.order_move(did, pid):
			moved += 1
		elif reason == "":
			reason = mv.move_error(did, pid)
	if moved == 0 and reason != "":
		EventBus.notify.emit(reason)
	refresh_layer("Units")
	return moved


## The unit icon under [param world_pos] ({} if none).
func unit_icon_at(world_pos: Vector2) -> Dictionary:
	for icon: Dictionary in unit_icons():
		if (icon.rect as Rect2).grow(2.0).has_point(world_pos):
			return icon
	return {}


func set_hovered(pid: String) -> void:
	if pid == hovered_province:
		return
	hovered_province = pid
	refresh_layer("Highlight")
	if not selected_divisions.is_empty():
		refresh_layer("Units")   # move preview follows the cursor
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
				if not selected_divisions.is_empty():
					order_selected_move(pid)
				EventBus.province_right_clicked.emit(pid)
	elif event is InputEventMouseMotion:
		set_hovered(province_at(_event_world_pos((event as InputEventMouseMotion).position)))
	elif event is InputEventKey and event.pressed and (event as InputEventKey).keycode == KEY_ESCAPE:
		if not selected_divisions.is_empty():
			clear_unit_selection()
			EventBus.divisions_selected.emit([])
			get_viewport().set_input_as_handled()


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


## Step 8: one counter box per (province, owner) below the city marker,
## showing the division count and the type letters (I/A/R) in the nation colour.
## Returns Array of {province, owner, count, letters, rect}.
func unit_icons() -> Array:
	var out: Array = []
	if not GameState.active:
		return out
	var by_prov: Dictionary = {}   # pid -> {owner -> Array[DivisionState]}
	for d: DivisionState in GameState.divisions.values():
		if not by_prov.has(d.province):
			by_prov[d.province] = {}
		var g: Dictionary = by_prov[d.province]
		if not g.has(d.owner):
			g[d.owner] = []
		g[d.owner].append(d)
	for pid in GameData.province_ids:
		if not by_prov.has(pid) or not geometry.anchors.has(pid):
			continue
		var g: Dictionary = by_prov[pid]
		var owners: Array = g.keys()
		owners.sort()
		var total_w := owners.size() * UNIT_BOX.x + (owners.size() - 1) * 4.0
		var x0: float = geometry.anchors[pid].x - total_w / 2.0
		for i in owners.size():
			var oid: String = owners[i]
			var letters := ""
			for tid in GameData.division_ids:
				for d: DivisionState in g[oid]:
					if d.template == tid:
						letters += UNIT_LETTERS.get(tid, tid.substr(0, 1).to_upper())
						break
			var pos := Vector2(x0 + i * (UNIT_BOX.x + 4.0), geometry.anchors[pid].y + 26.0)
			out.append({"province": pid, "owner": oid, "count": g[oid].size(), "letters": letters,
				"rect": Rect2(pos, UNIT_BOX)})
	return out


## Step 9: movement arrows of the player's moving divisions. Returns Array of
## {division, points (PackedVector2Array: unit position then province anchors),
## progress, selected}. Hidden enemy orders are not drawn.
func move_arrows() -> Array:
	var out: Array = []
	if not GameState.active:
		return out
	var ids: Array = GameState.divisions.keys()
	ids.sort()
	for did in ids:
		var d: DivisionState = GameState.divisions[did]
		if not d.is_moving() or d.owner != GameState.player_nation:
			continue
		var pts := PackedVector2Array([unit_anchor(d.province)])
		for p in d.path:
			pts.append(unit_anchor(p))
		out.append({"division": d.id, "points": pts, "progress": d.move_progress,
			"selected": selected_divisions.has(d.id)})
	return out


func unit_anchor(pid: String) -> Vector2:
	return geometry.anchors.get(pid, Vector2.ZERO) + Vector2(0, 35)


func _draw_arrow(canvas: CanvasItem, pts: PackedVector2Array, col: Color, width: float) -> void:
	if pts.size() < 2:
		return
	canvas.draw_polyline(pts, Color(0, 0, 0, col.a * 0.7), width + px(2.0), true)
	canvas.draw_polyline(pts, col, width, true)
	var tip: Vector2 = pts[-1]
	var dir: Vector2 = (tip - pts[-2]).normalized()
	var head := px(14.0)
	var side := dir.orthogonal() * head * 0.5
	canvas.draw_colored_polygon(PackedVector2Array([tip, tip - dir * head + side, tip - dir * head - side]), col)


func _draw_units(canvas: CanvasItem) -> void:
	var font := ThemeDB.fallback_font
	# Movement orders (below the counters).
	for arrow: Dictionary in move_arrows():
		var pts: PackedVector2Array = arrow.points
		var col := ORDER_LINE if arrow.selected else ORDER_LINE.darkened(0.25)
		_draw_arrow(canvas, pts, col, px(3.0 if arrow.selected else 2.0))
		var marker: Vector2 = pts[0].lerp(pts[1], float(arrow.progress))
		canvas.draw_circle(marker, px(6.0), Color(0, 0, 0, 0.9))
		canvas.draw_circle(marker, px(4.5), ORDER_LINE)
	# Preview of a move to the hovered province.
	var mv := get_node_or_null("/root/Movement")
	if mv and not selected_divisions.is_empty() and hovered_province != "":
		var d: DivisionState = GameState.division(selected_divisions[0])
		if d and d.province != hovered_province:
			var path: Array = mv.find_path(d.owner, d.province, hovered_province)
			if not path.is_empty():
				var pts := PackedVector2Array([unit_anchor(d.province)])
				for p in path:
					pts.append(unit_anchor(p))
				_draw_arrow(canvas, pts, PREVIEW_LINE, px(2.0))
	var sel_prov := ""
	if not selected_divisions.is_empty() and GameState.division(selected_divisions[0]):
		sel_prov = GameState.division(selected_divisions[0]).province
	for icon: Dictionary in unit_icons():
		var r: Rect2 = icon.rect
		var col := GameData.nation_color(icon.owner)
		if icon.province == sel_prov and icon.owner == GameState.player_nation:
			canvas.draw_rect(r.grow(4.0), SELECT_LINE)
		canvas.draw_rect(r.grow(1.5), Color(0, 0, 0, 0.85))
		canvas.draw_rect(r, col.darkened(0.15))
		var txt := "%d %s" % [int(icon.count), String(icon.letters)]
		var text_col := Color.BLACK if col.get_luminance() > 0.55 else Color.WHITE
		canvas.draw_string(font, Vector2(r.position.x, r.position.y + 14.0), txt,
			HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 13, text_col)


func _on_divisions_changed(_a: Variant = null, _b: Variant = null, _c: Variant = null) -> void:
	refresh_layer("Units")


func _on_day_for_units(_day: int) -> void:
	for d: DivisionState in GameState.divisions.values():
		if d.is_moving() and d.owner == GameState.player_nation:
			refresh_layer("Units")   # progress markers
			return


func _draw_fog(_canvas: CanvasItem) -> void:
	pass  # Step 12: darken provinces not visible to the player.
