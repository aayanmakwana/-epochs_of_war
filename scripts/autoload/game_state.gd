extends Node
## The whole mutable world (autoload "GameState").
##
## Everything a save file needs lives here and round-trips through
## to_dict() / load_from_dict(). UI-only state (selection, camera) does not.
## Systems mutate this state and then emit EventBus.province_changed /
## nation_changed so the UI can refresh.

const SAVE_VERSION := 1

var active: bool = false          # true once a game has been started or loaded
var day_index: int = 0            # days since 1 Jan 1936 (GameDate.EPOCH_YEAR)
var hour: int = 0                 # 0-23
var player_nation: String = ""
var provinces: Dictionary = {}    # id -> ProvinceState
var nations: Dictionary = {}      # id -> NationState
var divisions: Dictionary = {}    # int id -> DivisionState
var next_division_id: int = 1
## Running strategic battles (step 10, driven by the Combat autoload):
## province id -> {"province", "attacker", "defender", "attackers": Array[int],
## "days": int, "start_day": int}. Saved with the game.
var battles: Dictionary = {}
var rng_seed: int = 0
var game_over: bool = false
## Real seconds spent in this game (end screen "time played", step 19).
var time_played: float = 0.0


func reset() -> void:
	active = false
	day_index = 0
	hour = 0
	player_nation = ""
	provinces.clear()
	nations.clear()
	divisions.clear()
	next_division_id = 1
	battles.clear()
	rng_seed = 0
	game_over = false
	time_played = 0.0


## Build the 1 January 1936 world with [param player_id] as the player.
func new_game(player_id: String, seed_value: int = 1936) -> void:
	reset()
	player_nation = player_id
	rng_seed = seed_value
	day_index = GameDate.to_index(int(GameData.rule("start_year", 1936)),
		int(GameData.rule("start_month", 1)), int(GameData.rule("start_day", 1)))
	for pid in GameData.province_ids:
		var def: Dictionary = GameData.provinces[pid]
		var p := ProvinceState.new()
		p.id = pid
		p.owner = def.owner
		p.controller = def.owner
		p.factories = int(def.get("factories", 0))
		p.infrastructure = int(def.get("infrastructure", 1))
		provinces[pid] = p
	for nid in GameData.nation_ids:
		var def: Dictionary = GameData.nations[nid]
		var n := NationState.new()
		n.id = nid
		n.is_player = nid == player_id
		n.manpower = int(def.get("manpower", 0))
		var sp: Dictionary = def.get("stockpile", {})
		for k in NationState.STOCKPILE_KEYS:
			n.stockpile[k] = float(sp.get(k, 0.0))
		for eq in GameData.equipment_ids:
			n.factory_allocation[eq] = 0
			n.production_progress[eq] = 0.0
		for t in def.get("starting_techs", []):
			n.researched.append(String(t))
		nations[nid] = n
	for nid in GameData.nation_ids:
		for sd: Dictionary in GameData.nations[nid].get("starting_divisions", []):
			add_division(sd.template, nid, sd.province)
	# Step 6: every nation starts with its factories split by rules.default_production_split.
	var production := get_node_or_null("/root/Production")
	if production:
		for nid in GameData.nation_ids:
			production.apply_default_allocation(nid)
	active = true
	EventBus.game_state_ready.emit()


## Create a division at full strength. Costs are paid by the caller (step 8).
func add_division(template_id: String, owner_id: String, province_id: String) -> DivisionState:
	var n: NationState = nations.get(owner_id)
	var stats := TechEffects.division_stats(template_id, n.researched if n else [])
	var d := DivisionState.new()
	d.id = next_division_id
	next_division_id += 1
	d.template = template_id
	d.owner = owner_id
	d.province = province_id
	d.origin = province_id
	d.hp = stats.hp
	d.organization = stats.organization
	divisions[d.id] = d
	return d


func remove_division(division_id: int) -> void:
	divisions.erase(division_id)


# --- Queries ----------------------------------------------------------------

func province(pid: String) -> ProvinceState:
	return provinces.get(pid)


func nation(nid: String) -> NationState:
	return nations.get(nid)


func player() -> NationState:
	return nations.get(player_nation)


func division(did: int) -> DivisionState:
	return divisions.get(did)


func controlled_provinces(nid: String) -> PackedStringArray:
	var out: PackedStringArray = []
	for pid in GameData.province_ids:
		if provinces[pid].controller == nid:
			out.append(pid)
	return out


func owned_provinces(nid: String) -> PackedStringArray:
	var out: PackedStringArray = []
	for pid in GameData.province_ids:
		if provinces[pid].owner == nid:
			out.append(pid)
	return out


## Total factories in provinces the nation controls.
func factory_count(nid: String) -> int:
	var total := 0
	for pid in controlled_provinces(nid):
		total += provinces[pid].factories
	return total


func divisions_in(pid: String) -> Array[DivisionState]:
	var out: Array[DivisionState] = []
	for d: DivisionState in divisions.values():
		if d.province == pid:
			out.append(d)
	return out


func divisions_of(nid: String) -> Array[DivisionState]:
	var out: Array[DivisionState] = []
	for d: DivisionState in divisions.values():
		if d.owner == nid:
			out.append(d)
	return out


func date() -> Dictionary:
	return GameDate.from_index(day_index)


func date_string() -> String:
	return GameDate.format(day_index)


# --- Serialization (used by save/load, step 18) ------------------------------

func to_dict() -> Dictionary:
	var p_out: Dictionary = {}
	for pid in provinces:
		p_out[pid] = provinces[pid].to_dict()
	var n_out: Dictionary = {}
	for nid in nations:
		n_out[nid] = nations[nid].to_dict()
	var d_out: Array = []
	var ids := divisions.keys()
	ids.sort()
	for did in ids:
		d_out.append(divisions[did].to_dict())
	return {
		"version": SAVE_VERSION,
		"day_index": day_index,
		"hour": hour,
		"player_nation": player_nation,
		"next_division_id": next_division_id,
		"rng_seed": rng_seed,
		"game_over": game_over,
		"time_played": time_played,
		"provinces": p_out,
		"nations": n_out,
		"divisions": d_out,
		"battles": battles.duplicate(true),
	}


## Replace the current state with [param d] (as produced by to_dict(),
## possibly after a JSON round-trip). Returns false if d is unusable.
func load_from_dict(d: Dictionary) -> bool:
	if not d.has("provinces") or not d.has("nations"):
		return false
	reset()
	day_index = int(d.get("day_index", 0))
	hour = int(d.get("hour", 0))
	player_nation = String(d.get("player_nation", ""))
	next_division_id = int(d.get("next_division_id", 1))
	rng_seed = int(d.get("rng_seed", 0))
	game_over = bool(d.get("game_over", false))
	time_played = float(d.get("time_played", 0.0))
	var p_in: Dictionary = d.get("provinces", {})
	for pid in GameData.province_ids:
		if p_in.has(pid):
			provinces[pid] = ProvinceState.from_dict(p_in[pid])
	var n_in: Dictionary = d.get("nations", {})
	for nid in GameData.nation_ids:
		if n_in.has(nid):
			nations[nid] = NationState.from_dict(n_in[nid])
	for dd: Dictionary in d.get("divisions", []):
		var dv := DivisionState.from_dict(dd)
		divisions[dv.id] = dv
		next_division_id = maxi(next_division_id, dv.id + 1)
	var b_in: Dictionary = d.get("battles", {})
	for pid in b_in:
		var b: Dictionary = b_in[pid]
		var ids: Array = []
		for did in b.get("attackers", []):
			ids.append(int(did))
		battles[String(pid)] = {
			"province": String(b.get("province", pid)),
			"attacker": String(b.get("attacker", "")),
			"defender": String(b.get("defender", "")),
			"attackers": ids,
			"days": int(b.get("days", 0)),
			"start_day": int(b.get("start_day", 0)),
		}
	if provinces.size() != GameData.province_ids.size() or nations.size() != GameData.nation_ids.size():
		reset()
		return false
	active = true
	EventBus.game_state_ready.emit()
	return true
