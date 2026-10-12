extends Node
## Read-only game definitions (autoload "GameData").
##
## Loads every JSON file in res://data/ once at startup and builds the map
## geometry. Nothing here changes during play; runtime state lives in
## GameState. Dictionaries keep the raw JSON shape (numbers are floats, so
## wrap them in int() where you need integers).
##
## NOTE for export (later): add "data/*.json" to the export preset's
## non-resource include filter, otherwise the JSON files are not packed.

const DATA_DIR := "res://data/"

var terrain: Dictionary = {}      # terrain id -> def
var provinces: Dictionary = {}    # province id -> def
var province_ids: PackedStringArray = []   # design-doc order
var nations: Dictionary = {}      # nation id -> def
var nation_ids: PackedStringArray = []
var divisions: Dictionary = {}    # template id -> def
var division_ids: PackedStringArray = []
var equipment: Dictionary = {}    # equipment id -> def
var equipment_ids: PackedStringArray = []
var techs: Dictionary = {}        # tech id -> def
var tech_ids: PackedStringArray = []
var tech_branches: PackedStringArray = []
var tactical: Dictionary = {}
var rules: Dictionary = {}
var map_def: Dictionary = {}
var geometry: MapGeometry = null

## Problems found by load_all() / validate(). Empty = data is consistent.
var errors: PackedStringArray = []


func _ready() -> void:
	load_all()
	if not errors.is_empty():
		for e in errors:
			push_error("GameData: " + e)


func load_all() -> bool:
	errors.clear()
	terrain = _load_json("terrain.json")
	terrain.erase("_comment")
	rules = _load_json("rules.json")
	rules.erase("_comment")
	tactical = _load_json("tactical.json")
	map_def = _load_json("map.json")

	provinces.clear()
	province_ids.clear()
	for p: Dictionary in _load_json("provinces.json").get("provinces", []):
		provinces[p.id] = p
		province_ids.append(p.id)

	nations.clear()
	nation_ids.clear()
	for n: Dictionary in _load_json("nations.json").get("nations", []):
		nations[n.id] = n
		nation_ids.append(n.id)

	divisions.clear()
	division_ids.clear()
	for d: Dictionary in _load_json("divisions.json").get("divisions", []):
		divisions[d.id] = d
		division_ids.append(d.id)

	equipment.clear()
	equipment_ids.clear()
	for e: Dictionary in _load_json("equipment.json").get("equipment", []):
		equipment[e.id] = e
		equipment_ids.append(e.id)

	var tech_file := _load_json("techs.json")
	tech_branches = PackedStringArray(tech_file.get("branches", []))
	techs.clear()
	tech_ids.clear()
	for t: Dictionary in tech_file.get("techs", []):
		techs[t.id] = t
		tech_ids.append(t.id)

	geometry = MapGeometry.new()
	geometry.build(map_def)
	for e in geometry.errors:
		errors.append("map: " + e)

	errors.append_array(validate())
	return errors.is_empty()


func _load_json(file_name: String) -> Dictionary:
	var path := DATA_DIR + file_name
	if not FileAccess.file_exists(path):
		errors.append("missing data file " + path)
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		errors.append("could not parse " + path)
		return {}
	return parsed


## Cross-checks the data files. Returns a list of problems.
func validate() -> PackedStringArray:
	var out: PackedStringArray = []
	for pid in province_ids:
		var p: Dictionary = provinces[pid]
		if not terrain.has(p.get("terrain", "")):
			out.append("province %s has unknown terrain %s" % [pid, p.get("terrain", "")])
		if not nations.has(p.get("owner", "")):
			out.append("province %s has unknown owner %s" % [pid, p.get("owner", "")])
		if geometry and not geometry.province_cells.has(pid):
			out.append("province %s does not appear on the map" % pid)
	if geometry:
		for pid in geometry.province_cells:
			if not provinces.has(pid):
				out.append("map uses undefined province " + pid)
	for nid in nation_ids:
		var n: Dictionary = nations[nid]
		var cap: String = n.get("capital", "")
		if not provinces.has(cap):
			out.append("nation %s has unknown capital %s" % [nid, cap])
		elif provinces[cap].owner != nid:
			out.append("nation %s does not own its capital %s" % [nid, cap])
		for t in n.get("starting_techs", []):
			if not techs.has(t):
				out.append("nation %s has unknown starting tech %s" % [nid, t])
		for sd: Dictionary in n.get("starting_divisions", []):
			if not divisions.has(sd.get("template", "")):
				out.append("nation %s starting division has unknown template" % nid)
			if not provinces.has(sd.get("province", "")):
				out.append("nation %s starting division in unknown province" % nid)
	for tid in tech_ids:
		var t: Dictionary = techs[tid]
		var req: String = t.get("requires", "")
		if req != "" and not techs.has(req):
			out.append("tech %s requires unknown tech %s" % [tid, req])
		if not tech_branches.has(t.get("branch", "")):
			out.append("tech %s has unknown branch" % tid)
	for did in division_ids:
		var d: Dictionary = divisions[did]
		for eq in d.get("equipment", {}):
			if not equipment.has(eq):
				out.append("division %s uses unknown equipment %s" % [did, eq])
		var req_t: String = d.get("required_tech", "")
		if req_t != "" and not techs.has(req_t):
			out.append("division %s requires unknown tech %s" % [did, req_t])
	return out


# --- Lookups ----------------------------------------------------------------

func province(pid: String) -> Dictionary:
	return provinces.get(pid, {})


func nation(nid: String) -> Dictionary:
	return nations.get(nid, {})


func terrain_of(pid: String) -> Dictionary:
	return terrain.get(province(pid).get("terrain", ""), {})


func province_name(pid: String) -> String:
	return province(pid).get("name", pid)


func nation_name(nid: String) -> String:
	return nation(nid).get("name", nid)


func nation_color(nid: String) -> Color:
	return Color.from_string(nation(nid).get("color", "#808080"), Color.GRAY)


func is_naval(pid: String) -> bool:
	return bool(terrain_of(pid).get("naval", false))


func is_major_city(pid: String) -> bool:
	return bool(province(pid).get("major_city", false))


func is_capital(pid: String) -> bool:
	for nid in nation_ids:
		if nations[nid].get("capital", "") == pid:
			return true
	return false


func adjacent(pid: String) -> PackedStringArray:
	return geometry.adjacency.get(pid, PackedStringArray())


func are_adjacent(a: String, b: String) -> bool:
	return geometry.are_adjacent(a, b)


func playable_nations() -> PackedStringArray:
	var out: PackedStringArray = []
	for nid in nation_ids:
		if nations[nid].get("playable", false):
			out.append(nid)
	return out


func major_cities() -> PackedStringArray:
	var out: PackedStringArray = []
	for pid in province_ids:
		if is_major_city(pid):
			out.append(pid)
	return out


## Techs of a branch sorted by tier.
func techs_in_branch(branch: String) -> PackedStringArray:
	var list: Array = []
	for tid in tech_ids:
		if techs[tid].get("branch", "") == branch:
			list.append(techs[tid])
	list.sort_custom(func(a, b): return int(a.tier) < int(b.tier))
	var out: PackedStringArray = []
	for t in list:
		out.append(t.id)
	return out


func rule(key: String, default: Variant = null) -> Variant:
	return rules.get(key, default)
