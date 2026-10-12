class_name FlagView
extends Control
## Procedural nation flag drawn from a nations.json "flag" dictionary:
##   {layout: horizontal|vertical|solid|cross|triangle, colors: [...], emblem?: "star", emblem_color?}
## Pure (no autoloads): callers pass the dictionary via set_flag().

var flag: Dictionary = {}


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(42, 28)


func set_flag(f: Dictionary) -> void:
	flag = f
	queue_redraw()


func _draw() -> void:
	draw_flag(self, Rect2(Vector2.ZERO, size), flag)


static func _col(colors: Array, i: int) -> Color:
	if colors.is_empty():
		return Color.GRAY
	return Color.from_string(String(colors[clampi(i, 0, colors.size() - 1)]), Color.GRAY)


## Draw [param f] into [param rect] on [param canvas].
static func draw_flag(canvas: CanvasItem, rect: Rect2, f: Dictionary) -> void:
	var colors: Array = f.get("colors", [])
	var layout: String = f.get("layout", "solid")
	var n := maxi(1, colors.size())
	match layout:
		"horizontal":
			var h := rect.size.y / n
			for i in n:
				canvas.draw_rect(Rect2(rect.position + Vector2(0, h * i), Vector2(rect.size.x, h + 0.5)), _col(colors, i))
		"vertical":
			var w := rect.size.x / n
			for i in n:
				canvas.draw_rect(Rect2(rect.position + Vector2(w * i, 0), Vector2(w + 0.5, rect.size.y)), _col(colors, i))
		"cross":
			# Simplified Union Jack: field, white saltire, red saltire, white cross, red cross.
			var field := _col(colors, 0)
			var white := _col(colors, 1)
			var red := _col(colors, 2)
			canvas.draw_rect(rect, field)
			var tl := rect.position
			var br := rect.end
			var tr := Vector2(br.x, tl.y)
			var bl := Vector2(tl.x, br.y)
			var t := rect.size.y
			canvas.draw_line(tl, br, white, t * 0.2)
			canvas.draw_line(tr, bl, white, t * 0.2)
			canvas.draw_line(tl, br, red, t * 0.07)
			canvas.draw_line(tr, bl, red, t * 0.07)
			var c := rect.get_center()
			canvas.draw_rect(Rect2(Vector2(tl.x, c.y - t * 0.17), Vector2(rect.size.x, t * 0.34)), white)
			canvas.draw_rect(Rect2(Vector2(c.x - t * 0.17, tl.y), Vector2(t * 0.34, t)), white)
			canvas.draw_rect(Rect2(Vector2(tl.x, c.y - t * 0.1), Vector2(rect.size.x, t * 0.2)), red)
			canvas.draw_rect(Rect2(Vector2(c.x - t * 0.1, tl.y), Vector2(t * 0.2, t)), red)
		"triangle":
			# Two horizontal stripes plus a hoist triangle in colours[2].
			var h2 := rect.size.y * 0.5
			canvas.draw_rect(Rect2(rect.position, Vector2(rect.size.x, h2 + 0.5)), _col(colors, 0))
			canvas.draw_rect(Rect2(rect.position + Vector2(0, h2), Vector2(rect.size.x, h2)), _col(colors, 1))
			canvas.draw_colored_polygon(PackedVector2Array([
				rect.position, rect.position + Vector2(rect.size.x * 0.5, h2), rect.position + Vector2(0, rect.size.y)
			]), _col(colors, 2))
		_:
			canvas.draw_rect(rect, _col(colors, 0))
	if String(f.get("emblem", "")) == "star":
		var ec := Color.from_string(String(f.get("emblem_color", "#ffd700")), Color.GOLD)
		var center := rect.position + Vector2(rect.size.x * 0.22, rect.size.y * 0.3)
		var r := rect.size.y * 0.17
		var pts := PackedVector2Array()
		for i in 10:
			var rr := r if i % 2 == 0 else r * 0.45
			var ang := -PI / 2.0 + i * PI / 5.0
			pts.append(center + Vector2(cos(ang), sin(ang)) * rr)
		canvas.draw_colored_polygon(pts, ec)
	# Thin dark frame.
	canvas.draw_rect(rect, Color(0, 0, 0, 0.7), false, 1.0)
