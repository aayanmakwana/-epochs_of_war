class_name TacticalGrid
extends Control
## Draws a TacticalMap + the deployed units (step 15) and turns mouse input into
## tile events. Owned by TacticalView (scripts/tactical/tactical_view.gd).

signal tile_clicked(tile: Vector2i, button: int)
signal tile_hovered(tile: Vector2i)   # NO_TILE when leaving the grid

const NO_TILE := Vector2i(-1, -1)
const GRID_LINE := Color(0, 0, 0, 0.35)
const OBJECTIVE := Color(1.0, 0.82, 0.2)
const SELECT := Color(1.0, 0.95, 0.3)
const VALID := Color(0.5, 1.0, 0.5, 0.9)

var map: TacticalMap
var deployment: TacticalDeployment
var tile_size: float = 44.0
var show_zones: bool = true
var attacker_color: Color = Color(0.8, 0.3, 0.3)
var defender_color: Color = Color(0.3, 0.45, 0.85)
var selected_unit: int = -1
var hovered: Vector2i = NO_TILE


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true


func setup(m: TacticalMap, dep: TacticalDeployment, tsize: float) -> void:
	map = m
	deployment = dep
	tile_size = tsize
	custom_minimum_size = Vector2.ONE * tile_size * m.size
	size = custom_minimum_size
	queue_redraw()


func tile_at(local: Vector2) -> Vector2i:
	if map == null:
		return NO_TILE
	var t := Vector2i(floori(local.x / tile_size), floori(local.y / tile_size))
	return t if map.in_bounds(t) else NO_TILE


func tile_rect(t: Vector2i) -> Rect2:
	return Rect2(Vector2(t) * tile_size, Vector2.ONE * tile_size)


func tile_center(t: Vector2i) -> Vector2:
	return tile_rect(t).get_center()


func _gui_input(event: InputEvent) -> void:
	var mm := event as InputEventMouseMotion
	if mm:
		var t := tile_at(mm.position)
		if t != hovered:
			hovered = t
			tile_hovered.emit(t)
			queue_redraw()
		return
	var mb := event as InputEventMouseButton
	if mb and mb.pressed and (mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_RIGHT):
		var t := tile_at(mb.position)
		if t != NO_TILE:
			tile_clicked.emit(t, mb.button_index)
			accept_event()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and hovered != NO_TILE:
		hovered = NO_TILE
		tile_hovered.emit(NO_TILE)
		queue_redraw()


# --- Drawing -------------------------------------------------------------------

func _draw() -> void:
	if map == null:
		return
	for y in map.size:
		for x in map.size:
			_draw_tile(Vector2i(x, y))
	if show_zones:
		_draw_zones()
	for i in map.objectives.size():
		_draw_objective(map.objectives[i], i + 1)
	_draw_valid_tiles()
	if deployment:
		for u in deployment.units:
			if u.is_deployed():
				_draw_unit(u)
	if hovered != NO_TILE:
		draw_rect(tile_rect(hovered).grow(-1), Color(1, 1, 1, 0.8), false, 2.0)
	draw_rect(Rect2(Vector2.ZERO, Vector2.ONE * tile_size * map.size), Color(0, 0, 0, 0.9), false, 2.0)


func _draw_tile(t: Vector2i) -> void:
	var r := tile_rect(t)
	var c := map.tile_color(t)
	draw_rect(r, c)
	var s := tile_size
	match map.tile(t):
		"building":
			draw_rect(r.grow(-s * 0.14), c.darkened(0.25))
			draw_rect(r.grow(-s * 0.14), c.lightened(0.15), false, 1.0)
		"rubble":
			var rng := RandomNumberGenerator.new()
			rng.seed = t.x * 73856093 ^ t.y * 19349663
			for i in 5:
				var p := r.position + Vector2(rng.randf_range(0.15, 0.85), rng.randf_range(0.15, 0.85)) * s
				draw_rect(Rect2(p - Vector2.ONE * s * 0.06, Vector2.ONE * s * 0.12), c.darkened(0.35))
		"park":
			draw_circle(r.position + Vector2(0.32, 0.35) * s, s * 0.16, c.darkened(0.3))
			draw_circle(r.position + Vector2(0.68, 0.62) * s, s * 0.14, c.darkened(0.3))
		"river":
			for k in 2:
				var yy := r.position.y + s * (0.35 + 0.3 * k)
				draw_line(Vector2(r.position.x + s * 0.15, yy), Vector2(r.position.x + s * 0.5, yy - s * 0.08), c.lightened(0.3), 1.5)
				draw_line(Vector2(r.position.x + s * 0.5, yy - s * 0.08), Vector2(r.position.x + s * 0.85, yy), c.lightened(0.3), 1.5)
		"bridge":
			var horizontal_river := map.river_orientation == "horizontal"
			for k in 4:
				var f := (k + 0.5) / 4.0
				if horizontal_river:
					draw_line(r.position + Vector2(0.1 * s, f * s), r.position + Vector2(0.9 * s, f * s), c.darkened(0.35), 1.5)
				else:
					draw_line(r.position + Vector2(f * s, 0.1 * s), r.position + Vector2(f * s, 0.9 * s), c.darkened(0.35), 1.5)
		"fortification":
			draw_rect(r.grow(-s * 0.12), Color(0.75, 0.68, 0.45), false, maxf(2.0, s * 0.08))
	draw_rect(r, GRID_LINE, false, 1.0)


func _draw_zones() -> void:
	for y in map.size:
		for x in map.size:
			var t := Vector2i(x, y)
			var z := map.zone_of(t)
			if z == "" or not map.is_passable(t):
				continue
			var col := attacker_color if z == "attacker" else defender_color
			draw_rect(tile_rect(t), Color(col, 0.28))
			# Inner edge of the zone gets a line.
			for d in TacticalMap.DIRS:
				var n := t + d
				if map.in_bounds(n) and map.zone_of(n) != z:
					var r := tile_rect(t)
					var a: Vector2
					var b: Vector2
					match d:
						Vector2i(1, 0):
							a = Vector2(r.end.x, r.position.y); b = r.end
						Vector2i(-1, 0):
							a = r.position; b = Vector2(r.position.x, r.end.y)
						Vector2i(0, 1):
							a = Vector2(r.position.x, r.end.y); b = r.end
						_:
							a = r.position; b = Vector2(r.end.x, r.position.y)
					draw_line(a, b, Color(col.lightened(0.3), 0.95), 2.0)


func _draw_objective(t: Vector2i, n: int) -> void:
	var c := tile_center(t)
	draw_rect(tile_rect(t).grow(-2), OBJECTIVE, false, 3.0)
	draw_circle(c, tile_size * 0.28, Color(0.15, 0.12, 0.05, 0.85))
	draw_arc(c, tile_size * 0.28, 0, TAU, 24, OBJECTIVE, 2.0)
	var font := ThemeDB.fallback_font
	var fs := int(tile_size * 0.38)
	draw_string(font, c + Vector2(-tile_size * 0.4, fs * 0.36), str(n), HORIZONTAL_ALIGNMENT_CENTER, tile_size * 0.8, fs, OBJECTIVE)


func valid_tiles() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if deployment == null or selected_unit < 0:
		return out
	for y in map.size:
		for x in map.size:
			var t := Vector2i(x, y)
			if deployment.can_place(selected_unit, t):
				out.append(t)
	return out


func _draw_valid_tiles() -> void:
	for t in valid_tiles():
		draw_rect(tile_rect(t).grow(-3), VALID, false, 1.5)


func _draw_unit(u: TacticalUnit) -> void:
	var r := tile_rect(u.pos).grow(-tile_size * 0.12)
	var col := attacker_color if u.side == "attacker" else defender_color
	draw_rect(r, col)
	draw_rect(r, Color(0, 0, 0, 0.9), false, 1.5)
	var font := ThemeDB.fallback_font
	var fs := int(tile_size * 0.4)
	draw_string(font, Vector2(r.position.x, r.get_center().y + fs * 0.3), u.letter(), HORIZONTAL_ALIGNMENT_CENTER, r.size.x, fs, Color.WHITE)
	# HP bar.
	var frac := float(u.hp) / maxf(1.0, float(u.max_hp))
	var bar := Rect2(r.position + Vector2(0, r.size.y - 4), Vector2(r.size.x, 4))
	draw_rect(bar, Color(0, 0, 0, 0.8))
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * frac, 4)), Color(0.4, 0.9, 0.4) if frac > 0.3 else Color(0.95, 0.4, 0.3))
	# Facing tick.
	var c := r.get_center()
	draw_line(c + Vector2(u.facing) * r.size.x * 0.3, c + Vector2(u.facing) * r.size.x * 0.5, Color.WHITE, 2.0)
	if u.id == selected_unit:
		draw_rect(tile_rect(u.pos).grow(-1), SELECT, false, 3.0)
