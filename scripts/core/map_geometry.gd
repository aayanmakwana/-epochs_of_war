class_name MapGeometry
extends RefCounted
## Derives all strategic-map geometry from the cell grid in data/map.json:
## province outlines (jittered so borders look organic), adjacency, label
## anchors, border segments and point-in-province lookup.
##
## Lattice vertex (i, j) is the corner at the top-left of cell (i, j).
## Every vertex and every unit edge midpoint is jittered deterministically
## from its lattice coordinates, so neighbouring provinces share exactly the
## same border points (no gaps, no overlaps).

var cell_size: float = 50.0
var cols: int = 0
var rows: int = 0
var vertex_jitter: float = 10.0
var edge_jitter: float = 7.0
var seed_value: int = 0

## Flat array cols*rows of province ids ("" = sea / off-map).
var cells: PackedStringArray = []
## id -> Array[Vector2i]
var province_cells: Dictionary = {}
## id -> Array[PackedVector2Array] (world-space closed loops, clockwise on screen)
var outlines: Dictionary = {}
## id -> PackedStringArray of adjacent province ids (sorted)
var adjacency: Dictionary = {}
## id -> Vector2 (world position for label / unit icons; always inside the province)
var anchors: Dictionary = {}
## "a|b" -> Array[PackedVector2Array]. a < b. Coastline / map edge uses "a|".
var borders: Dictionary = {}
## Problems found while building (empty = OK).
var errors: PackedStringArray = []


func build(map_def: Dictionary) -> bool:
	errors.clear()
	cell_size = float(map_def.get("cell_size", 50))
	vertex_jitter = float(map_def.get("vertex_jitter", 10))
	edge_jitter = float(map_def.get("edge_jitter", 7))
	seed_value = int(map_def.get("seed", 0))
	var legend: Dictionary = map_def.get("legend", {})
	var row_strings: Array = map_def.get("rows", [])
	rows = row_strings.size()
	cols = 0 if rows == 0 else String(row_strings[0]).length()
	cells.resize(cols * rows)
	province_cells.clear()
	for y in rows:
		var line: String = row_strings[y]
		if line.length() != cols:
			errors.append("map row %d has length %d, expected %d" % [y, line.length(), cols])
		for x in cols:
			var ch: String = line[x] if x < line.length() else "."
			var pid: String = ""
			if ch != ".":
				if legend.has(ch):
					pid = legend[ch]
				else:
					errors.append("map char '%s' at (%d,%d) not in legend" % [ch, x, y])
			cells[y * cols + x] = pid
			if pid != "":
				if not province_cells.has(pid):
					province_cells[pid] = []
				province_cells[pid].append(Vector2i(x, y))
	_check_non_manifold()
	_build_adjacency()
	_build_outlines()
	_build_borders()
	_build_anchors()
	return errors.is_empty()


# --- Queries ----------------------------------------------------------------

func cell_at(c: Vector2i) -> String:
	if c.x < 0 or c.y < 0 or c.x >= cols or c.y >= rows:
		return ""
	return cells[c.y * cols + c.x]


func bounds() -> Rect2:
	return Rect2(0, 0, cols * cell_size, rows * cell_size)


func province_ids() -> PackedStringArray:
	var ids := PackedStringArray(province_cells.keys())
	ids.sort()
	return ids


## Province under a world-space point, or "".
func province_at(pos: Vector2) -> String:
	var c := Vector2i(floori(pos.x / cell_size), floori(pos.y / cell_size))
	var candidates: Array[String] = []
	var center := cell_at(c)
	if center != "":
		candidates.append(center)
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var pid := cell_at(c + Vector2i(dx, dy))
			if pid != "" and not candidates.has(pid):
				candidates.append(pid)
	for pid in candidates:
		for loop: PackedVector2Array in outlines.get(pid, []):
			if Geometry2D.is_point_in_polygon(pos, loop):
				return pid
	return ""


func are_adjacent(a: String, b: String) -> bool:
	return adjacency.has(a) and (adjacency[a] as PackedStringArray).has(b)


## Jittered world position of lattice vertex v.
func vertex_position(v: Vector2i) -> Vector2:
	var base := Vector2(v) * cell_size
	var off := Vector2(_hash01(v.x, v.y, 1) * 2.0 - 1.0, _hash01(v.x, v.y, 2) * 2.0 - 1.0)
	return base + off * vertex_jitter


## Jittered midpoint of the unit lattice edge a-b (order independent).
func edge_midpoint(a: Vector2i, b: Vector2i) -> Vector2:
	var lo := a
	var hi := b
	if b.x < a.x or (b.x == a.x and b.y < a.y):
		lo = b
		hi = a
	var pa := vertex_position(lo)
	var pb := vertex_position(hi)
	var dir := Vector2(hi - lo)
	var perp := Vector2(-dir.y, dir.x)
	var h := _hash01(lo.x + hi.x, lo.y + hi.y, 3) * 2.0 - 1.0
	return (pa + pb) * 0.5 + perp * h * edge_jitter


# --- Construction -----------------------------------------------------------

func _hash01(x: int, y: int, salt: int) -> float:
	var h: int = (x * 73856093) ^ (y * 19349663) ^ (salt * 83492791) ^ (seed_value * 2654435761)
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return float(h & 0xFFFF) / 65535.0


func _check_non_manifold() -> void:
	# Two cells of one province touching only at a corner make outline
	# tracing ambiguous. The map must not contain this pattern.
	for j in range(1, rows):
		for i in range(1, cols):
			var tl := cell_at(Vector2i(i - 1, j - 1))
			var tr := cell_at(Vector2i(i, j - 1))
			var bl := cell_at(Vector2i(i - 1, j))
			var br := cell_at(Vector2i(i, j))
			if tl != "" and tl == br and tr != tl and bl != tl:
				errors.append("diagonal-only contact of '%s' at vertex (%d,%d)" % [tl, i, j])
			if tr != "" and tr == bl and tl != tr and br != tr:
				errors.append("diagonal-only contact of '%s' at vertex (%d,%d)" % [tr, i, j])


func _build_adjacency() -> void:
	var sets: Dictionary = {}
	for pid in province_cells:
		sets[pid] = {}
	for y in rows:
		for x in cols:
			var a := cell_at(Vector2i(x, y))
			if a == "":
				continue
			for n in [Vector2i(x + 1, y), Vector2i(x, y + 1)]:
				var b := cell_at(n)
				if b != "" and b != a:
					sets[a][b] = true
					sets[b][a] = true
	adjacency.clear()
	for pid in sets:
		var list := PackedStringArray(sets[pid].keys())
		list.sort()
		adjacency[pid] = list


func _build_outlines() -> void:
	outlines.clear()
	for pid in province_cells:
		# start vertex -> Array of end vertices (directed, clockwise on screen)
		var edges: Dictionary = {}
		var edge_count := 0
		for c: Vector2i in province_cells[pid]:
			var x := c.x
			var y := c.y
			if cell_at(Vector2i(x, y - 1)) != pid:
				_add_edge(edges, Vector2i(x, y), Vector2i(x + 1, y))
				edge_count += 1
			if cell_at(Vector2i(x + 1, y)) != pid:
				_add_edge(edges, Vector2i(x + 1, y), Vector2i(x + 1, y + 1))
				edge_count += 1
			if cell_at(Vector2i(x, y + 1)) != pid:
				_add_edge(edges, Vector2i(x + 1, y + 1), Vector2i(x, y + 1))
				edge_count += 1
			if cell_at(Vector2i(x - 1, y)) != pid:
				_add_edge(edges, Vector2i(x, y + 1), Vector2i(x, y))
				edge_count += 1
		var loops: Array = []
		var guard := 0
		while not edges.is_empty() and guard < 1000:
			guard += 1
			var start: Vector2i = edges.keys()[0]
			var loop := PackedVector2Array()
			var cur := start
			var steps := 0
			while steps <= edge_count:
				steps += 1
				var outs: Array = edges.get(cur, [])
				if outs.is_empty():
					errors.append("outline of '%s' is not closed" % pid)
					break
				var nxt: Vector2i = outs.pop_back()
				if outs.is_empty():
					edges.erase(cur)
				loop.append(vertex_position(cur))
				loop.append(edge_midpoint(cur, nxt))
				cur = nxt
				if cur == start:
					break
			loops.append(loop)
		outlines[pid] = loops
		if loops.size() != 1:
			errors.append("province '%s' has %d outline loops (expected 1)" % [pid, loops.size()])
		for loop: PackedVector2Array in loops:
			if Geometry2D.triangulate_polygon(loop).is_empty():
				errors.append("outline of '%s' cannot be triangulated" % pid)


func _add_edge(edges: Dictionary, a: Vector2i, b: Vector2i) -> void:
	if not edges.has(a):
		edges[a] = []
	edges[a].append(b)


func _build_borders() -> void:
	borders.clear()
	# Horizontal lattice edges: between cell (x, y-1) above and (x, y) below.
	for y in rows + 1:
		for x in cols:
			_add_border(cell_at(Vector2i(x, y - 1)), cell_at(Vector2i(x, y)), Vector2i(x, y), Vector2i(x + 1, y))
	# Vertical lattice edges: between cell (x-1, y) left and (x, y) right.
	for y in rows:
		for x in cols + 1:
			_add_border(cell_at(Vector2i(x - 1, y)), cell_at(Vector2i(x, y)), Vector2i(x, y), Vector2i(x, y + 1))


func _add_border(p: String, q: String, va: Vector2i, vb: Vector2i) -> void:
	if p == q:
		return
	var a := p
	var b := q
	if a == "" or (b != "" and b < a):
		a = q
		b = p
	var key := a + "|" + b
	if not borders.has(key):
		borders[key] = []
	borders[key].append(PackedVector2Array([vertex_position(va), edge_midpoint(va, vb), vertex_position(vb)]))


func _build_anchors() -> void:
	anchors.clear()
	for pid in province_cells:
		var list: Array = province_cells[pid]
		var mean := Vector2.ZERO
		for c: Vector2i in list:
			mean += Vector2(c) + Vector2(0.5, 0.5)
		mean /= float(list.size())
		# Prefer interior cells (all 4 neighbours in the same province).
		var best := Vector2.ZERO
		var best_d := INF
		for pass_i in 2:
			for c: Vector2i in list:
				if pass_i == 0:
					var interior := true
					for d in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
						if cell_at(c + d) != pid:
							interior = false
					if not interior:
						continue
				var center := Vector2(c) + Vector2(0.5, 0.5)
				var dist := center.distance_squared_to(mean)
				if dist < best_d:
					best_d = dist
					best = center
			if best_d < INF:
				break
		anchors[pid] = best * cell_size
