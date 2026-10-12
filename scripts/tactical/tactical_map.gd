class_name TacticalMap
extends RefCounted
## Tactical city battle grid (step 15). Pure data class: no autoload references,
## so tests can use it directly.
##
## generate(city_id) builds a size x size grid (default 20) from a
## RandomNumberGenerator seeded with hash(city_id): the same city always gets the
## same layout. Layout: a street grid with building blocks (some parks, some
## rubble), a meandering river across the city with 2-3 bridges, 3 objective
## tiles (city centre + 2 key buildings) ringed by a few fortifications.
##
## Deploy zones: attacker = the DEPLOY_DEPTH rows/columns along the south and
## west edges, defender = along the north and east edges. The NW and SE corners
## (where the bands overlap) belong to nobody. River tiles are never deployable.
##
## Coordinates: Vector2i(x, y), x to the east, y to the south (row 0 = north).

const TILE_TYPES: PackedStringArray = ["street", "building", "rubble", "park", "river", "bridge", "fortification"]
## Fallback tile rules (the doc values; GameData.tactical.tiles may override).
const DEFAULT_TILES := {
	"street":        {"name": "Street",        "color": "#8a8578", "move_cost": 1, "defense_bonus": 0.0,  "passable": true},
	"building":      {"name": "Building",      "color": "#5d5a55", "move_cost": 1, "defense_bonus": 0.3,  "passable": true},
	"rubble":        {"name": "Rubble",        "color": "#7a6a58", "move_cost": 2, "defense_bonus": 0.15, "passable": true},
	"park":          {"name": "Park",          "color": "#5f8a4a", "move_cost": 1, "defense_bonus": 0.0,  "passable": true},
	"river":         {"name": "River",         "color": "#3b6ea5", "move_cost": 0, "defense_bonus": 0.0,  "passable": false},
	"bridge":        {"name": "Bridge",        "color": "#9b8a6a", "move_cost": 1, "defense_bonus": 0.0,  "passable": true},
	"fortification": {"name": "Fortification", "color": "#4a4a3a", "move_cost": 1, "defense_bonus": 0.5,  "passable": true},
}
const DEPLOY_DEPTH := 3
const DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

var city_id: String = ""
var seed_value: int = 0
var size: int = 20
## Row-major tile ids: tiles[y * size + x].
var tiles: PackedStringArray = []
var objectives: Array[Vector2i] = []
var bridges: Array[Vector2i] = []
## "horizontal" (flows west-east) or "vertical".
var river_orientation: String = ""
var tile_defs: Dictionary = DEFAULT_TILES


## Build the map for [param city]. [param defs] = tile rules (e.g. GameData.tactical.tiles).
static func generate(city: String, grid_size: int = 20, defs: Dictionary = {}) -> TacticalMap:
	var m := TacticalMap.new()
	m.city_id = city
	m.seed_value = hash(city)
	m.size = maxi(10, grid_size)
	if not defs.is_empty():
		m.tile_defs = defs
	m._build()
	return m


# --- Queries -----------------------------------------------------------------

func in_bounds(p: Vector2i) -> bool:
	return p.x >= 0 and p.y >= 0 and p.x < size and p.y < size


func tile(p: Vector2i) -> String:
	return tiles[p.y * size + p.x] if in_bounds(p) else ""


func tile_def(p: Vector2i) -> Dictionary:
	return tile_defs.get(tile(p), {})


func is_passable(p: Vector2i) -> bool:
	return in_bounds(p) and bool(tile_def(p).get("passable", false))


## Movement points to enter [param p]; -1 = impassable.
func move_cost(p: Vector2i) -> int:
	if not is_passable(p):
		return -1
	return maxi(1, int(tile_def(p).get("move_cost", 1)))


## Defense multiplier bonus of [param p] (0.3 = +30%).
func defense_bonus(p: Vector2i) -> float:
	return float(tile_def(p).get("defense_bonus", 0.0))


func tile_name(p: Vector2i) -> String:
	return str(tile_def(p).get("name", tile(p).capitalize()))


func tile_color(p: Vector2i) -> Color:
	return Color.html(str(tile_def(p).get("color", "#ff00ff")))


func is_objective(p: Vector2i) -> bool:
	return objectives.has(p)


func count(tile_type: String) -> int:
	var n := 0
	for t in tiles:
		if t == tile_type:
			n += 1
	return n


func _in_attacker_band(p: Vector2i) -> bool:
	return p.y >= size - DEPLOY_DEPTH or p.x < DEPLOY_DEPTH


func _in_defender_band(p: Vector2i) -> bool:
	return p.y < DEPLOY_DEPTH or p.x >= size - DEPLOY_DEPTH


## Zone membership ignoring tile type: "attacker", "defender" or "".
func zone_of(p: Vector2i) -> String:
	if not in_bounds(p):
		return ""
	var a := _in_attacker_band(p)
	var d := _in_defender_band(p)
	if a and not d:
		return "attacker"
	if d and not a:
		return "defender"
	return ""


## True if a unit of [param side] ("attacker"/"defender") may deploy on [param p].
func is_deploy_tile(side: String, p: Vector2i) -> bool:
	return zone_of(p) == side and is_passable(p) and not is_objective(p)


## Deployable tiles of [param side], front line (deepest into the map) first.
func deploy_tiles(side: String) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in size:
		for x in size:
			var p := Vector2i(x, y)
			if is_deploy_tile(side, p):
				out.append(p)
	out.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var da := _edge_depth(side, a)
		var db := _edge_depth(side, b)
		if da != db:
			return da > db
		var ca := absi(a.x - size / 2) + absi(a.y - size / 2)
		var cb := absi(b.x - size / 2) + absi(b.y - size / 2)
		if ca != cb:
			return ca < cb
		return a.y * size + a.x < b.y * size + b.x)
	return out


## Distance from the side's own edge (0 = on the edge).
func _edge_depth(side: String, p: Vector2i) -> int:
	if side == "attacker":
		return mini(size - 1 - p.y, p.x)
	return mini(p.y, size - 1 - p.x)


func neighbors(p: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for d in DIRS:
		if in_bounds(p + d):
			out.append(p + d)
	return out


## Tiles reachable through passable tiles (4-neighbour) from [param starts].
func reachable_from(starts: Array[Vector2i]) -> Dictionary:
	var seen := {}
	var queue: Array[Vector2i] = []
	for s in starts:
		if is_passable(s) and not seen.has(s):
			seen[s] = true
			queue.append(s)
	var i := 0
	while i < queue.size():
		var p := queue[i]
		i += 1
		for n in neighbors(p):
			if not seen.has(n) and is_passable(n):
				seen[n] = true
				queue.append(n)
	return seen


## Cheapest movement cost from [param from] to [param to] (Dijkstra on move_cost); -1 = unreachable.
func path_cost(from: Vector2i, to: Vector2i) -> int:
	if not is_passable(from) or not is_passable(to):
		return -1
	var dist := {from: 0}
	var open: Array[Vector2i] = [from]
	while not open.is_empty():
		var best := 0
		for i in open.size():
			if dist[open[i]] < dist[open[best]]:
				best = i
		var p: Vector2i = open[best]
		open.remove_at(best)
		if p == to:
			return dist[p]
		for n in neighbors(p):
			var c := move_cost(n)
			if c < 0:
				continue
			var nd: int = dist[p] + c
			if not dist.has(n) or nd < dist[n]:
				dist[n] = nd
				if not open.has(n):
					open.append(n)
	return -1


# --- Generation ----------------------------------------------------------------

func _put(p: Vector2i, t: String) -> void:
	if in_bounds(p):
		tiles[p.y * size + p.x] = t


func _build() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	tiles.resize(size * size)
	tiles.fill("street")
	objectives.clear()
	bridges.clear()

	# 1. Street lines and building blocks.
	var xs := _street_lines(rng)
	var ys := _street_lines(rng)
	var blocks: Array = []   # Array of Array[Vector2i]
	var bounds_x := _segments(xs)
	var bounds_y := _segments(ys)
	for sy in bounds_y:
		for sx in bounds_x:
			var cells: Array[Vector2i] = []
			for y in range(sy.x, sy.y + 1):
				for x in range(sx.x, sx.y + 1):
					cells.append(Vector2i(x, y))
			blocks.append(cells)
	for cells: Array[Vector2i] in blocks:
		var r := rng.randf()
		var kind := "building"
		if r < 0.16:
			kind = "park"
		for c in cells:
			var t := kind
			if kind == "building" and rng.randf() < 0.14:
				t = "rubble"
			elif kind == "park" and rng.randf() < 0.1:
				t = "rubble"
			_put(c, t)
	# A few rubble-strewn streets (shelling damage).
	for i in rng.randi_range(4, 8):
		var p := Vector2i(rng.randi_range(0, size - 1), rng.randi_range(0, size - 1))
		if tile(p) == "street":
			_put(p, "rubble")
	# Guarantee at least one park.
	if count("park") == 0 and not blocks.is_empty():
		for c: Vector2i in blocks[rng.randi_range(0, blocks.size() - 1)]:
			_put(c, "park")

	# 2. River with bridges.
	river_orientation = "horizontal" if rng.randf() < 0.5 else "vertical"
	var river_cells := _carve_river(rng)
	_place_bridges(rng, river_cells, xs if river_orientation == "horizontal" else ys)

	# 3. Objectives: city centre + 2 key buildings, then fortifications around them.
	_place_objectives(rng)
	_place_fortifications(rng)


## Street line positions (every 3-5 tiles).
func _street_lines(rng: RandomNumberGenerator) -> Array[int]:
	var out: Array[int] = []
	var v := rng.randi_range(1, 3)
	while v < size:
		out.append(v)
		v += rng.randi_range(4, 5)
	return out


## Ranges [a, b] between street lines (inclusive), as Vector2i(a, b).
func _segments(lines: Array[int]) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var start := 0
	for l in lines:
		if l - 1 >= start:
			out.append(Vector2i(start, l - 1))
		start = l + 1
	if start <= size - 1:
		out.append(Vector2i(start, size - 1))
	return out


## Meandering river from one edge to the other. Returns river cells per step
## along the flow: Array of Array[Vector2i] (index = column for horizontal).
func _carve_river(rng: RandomNumberGenerator) -> Array:
	var cross := rng.randi_range(size * 2 / 5, size * 3 / 5 - 1)   # row (horizontal) or column
	var per_step: Array = []
	for i in size:
		var cells: Array[Vector2i] = []
		var prev := cross
		if i > 0 and rng.randf() < 0.3:
			cross = clampi(cross + (1 if rng.randf() < 0.5 else -1), size / 3, size * 2 / 3)
		for v in range(mini(prev, cross), maxi(prev, cross) + 1):
			cells.append(Vector2i(i, v) if river_orientation == "horizontal" else Vector2i(v, i))
		for c in cells:
			_put(c, "river")
		per_step.append(cells)
	return per_step


## 2-3 bridges, preferring places where a street line meets the river.
func _place_bridges(rng: RandomNumberGenerator, per_step: Array, street_lines: Array[int]) -> void:
	var want := rng.randi_range(2, 3)
	var candidates: Array[int] = []
	for l in street_lines:
		if l >= 1 and l <= size - 2:
			candidates.append(l)
	var chosen: Array[int] = []
	while chosen.size() < want and not candidates.is_empty():
		var i := rng.randi_range(0, candidates.size() - 1)
		var c := candidates[i]
		candidates.remove_at(i)
		var ok := true
		for o in chosen:
			if absi(o - c) < 3:
				ok = false
		if ok:
			chosen.append(c)
	var tries := 0
	while chosen.size() < want and tries < 100:
		tries += 1
		var c := rng.randi_range(1, size - 2)
		var ok := true
		for o in chosen:
			if absi(o - c) < 3:
				ok = false
		if ok:
			chosen.append(c)
	if chosen.is_empty():
		chosen.append(size / 2)
	chosen.sort()
	for c in chosen:
		for cell: Vector2i in per_step[c]:
			_put(cell, "bridge")
			bridges.append(cell)
		# Approaches on both banks are streets so the bridge is usable.
		for cell: Vector2i in per_step[c]:
			for n in neighbors(cell):
				if tile(n) != "river" and tile(n) != "bridge":
					var along := (n - cell)
					var across := along.y != 0 if river_orientation == "horizontal" else along.x != 0
					if across:
						_put(n, "street")


func _place_objectives(rng: RandomNumberGenerator) -> void:
	var center := Vector2i(size / 2, size / 2)
	var candidates: Array[Vector2i] = []
	for y in size:
		for x in size:
			var p := Vector2i(x, y)
			if is_passable(p) and tile(p) != "bridge" and _clear_of_zones(p):
				candidates.append(p)
	# Objective 1: the passable tile closest to the centre (the city centre).
	var best := Vector2i(-1, -1)
	var best_d := 1 << 30
	for p in candidates:
		var d := absi(p.x - center.x) + absi(p.y - center.y)
		if d < best_d:
			best_d = d
			best = p
	_put(best, "building")
	objectives.append(best)
	# Objectives 2-3: key buildings, spread out, leaning to the defender (north-east) side.
	var tries := 0
	while objectives.size() < 3 and tries < 2000:
		tries += 1
		var p := candidates[rng.randi_range(0, candidates.size() - 1)]
		if objectives.has(p):
			continue
		var min_d := 6 if tries < 1500 else 3
		var far := true
		for o in objectives:
			if absi(o.x - p.x) + absi(o.y - p.y) < min_d:
				far = false
		if not far:
			continue
		if tries < 1000 and (tile(p) != "building" or p.x - p.y < -4):
			continue
		_put(p, "building")
		objectives.append(p)


## At least one tile of margin from both deploy bands.
func _clear_of_zones(p: Vector2i) -> bool:
	var m := DEPLOY_DEPTH + 1
	return p.x >= m and p.y >= m and p.x < size - m and p.y < size - m


func _place_fortifications(rng: RandomNumberGenerator) -> void:
	for o in objectives:
		var ring := neighbors(o)
		var placed := 0
		var want := rng.randi_range(1, 2)
		while placed < want and not ring.is_empty():
			var i := rng.randi_range(0, ring.size() - 1)
			var n := ring[i]
			ring.remove_at(i)
			var t := tile(n)
			if t in ["river", "bridge"] or objectives.has(n) or zone_of(n) != "":
				continue
			_put(n, "fortification")
			placed += 1
	# Keep every objective reachable (fortifications are passable, but be safe):
	# a river-side fortification never blocks since rivers/bridges are untouched.
