extends Node
## Supply (autoload "Supply", step 11).
##
## A province is in supply for a nation when it can be reached from that
## nation's capital through friendly territory: provinces the nation controls,
## plus land provinces controlled by a nation that granted it military access
## (the same rule as Movement.is_passable). Naval zones count only when the
## nation controls them. If the nation does not control its capital, nothing is
## in supply.
##
## Supply is derived from the map every time it is asked for (20 provinces, a
## BFS is trivial), so it never goes stale and needs no save data.
##
## Daily system "supply" (order 48: after combat 45, before combat_recovery 50):
## every division standing in a province that is out of supply for its owner
## loses rules.attrition_per_day x max HP and rules.attrition_org_per_day x max
## organization. Combat.run_recovery skips HP/organization recovery for
## out-of-supply divisions. A division reaching 0 HP is destroyed
## (Combat.destroy). The player is notified when divisions lose or regain supply.
## EventBus.supply_changed(nation) fires when a nation's supplied set changes
## (checked after province / access changes and every day).

var _movement: Node
var _combat: Node
## nid -> sorted PackedStringArray of supplied provinces (last state announced).
var _snapshot: Dictionary = {}
## Player division ids out of supply at the last daily tick (for notifications).
var _player_out: Dictionary = {}
var _check_queued := false


func _ready() -> void:
	_movement = get_node_or_null("/root/Movement")
	_combat = get_node_or_null("/root/Combat")
	Simulation.register_daily("supply", run_daily, 48)
	EventBus.province_changed.connect(func(_p: String) -> void: queue_check())
	EventBus.military_access_granted.connect(func(_h: String, _g: String) -> void: queue_check())
	EventBus.nation_capitulated.connect(func(_n: String, _c: String) -> void: queue_check())
	EventBus.game_state_ready.connect(_on_game_state_ready)


func _r(key: String, def: float) -> float:
	return float(GameData.rule(key, def))


# --- Queries -------------------------------------------------------------------

## Supply source of [param nid]: its capital if it controls it, else "".
func source(nid: String) -> String:
	var cap := String(GameData.nation(nid).get("capital", ""))
	var ps: ProvinceState = GameState.province(cap)
	if ps == null or ps.controller != nid:
		return ""
	return cap


## True if supply of [param nid] can flow through [param pid].
func is_friendly(nid: String, pid: String) -> bool:
	if _movement:
		return _movement.is_passable(nid, pid)
	var ps: ProvinceState = GameState.province(pid)
	return ps != null and ps.controller == nid


## Set (pid -> true) of the provinces in supply for [param nid].
func supplied_set(nid: String) -> Dictionary:
	var seen: Dictionary = {}
	if not GameState.active or GameState.nation(nid) == null:
		return seen
	var start := source(nid)
	if start == "":
		return seen
	seen[start] = true
	var queue: Array[String] = [start]
	while not queue.is_empty():
		var cur: String = queue.pop_front()
		for nb in GameData.adjacent(cur):
			if not seen.has(nb) and is_friendly(nid, nb):
				seen[nb] = true
				queue.append(nb)
	return seen


## Supplied provinces of [param nid] in design-doc order.
func supplied_provinces(nid: String) -> PackedStringArray:
	var s := supplied_set(nid)
	var out: PackedStringArray = []
	for pid in GameData.province_ids:
		if s.has(pid):
			out.append(pid)
	return out


func is_province_supplied(nid: String, pid: String) -> bool:
	return supplied_set(nid).has(pid)


## Provinces [param nid] controls that are cut off from its capital.
func cut_off_provinces(nid: String) -> PackedStringArray:
	var s := supplied_set(nid)
	var out: PackedStringArray = []
	for pid in GameState.controlled_provinces(nid):
		if not s.has(pid):
			out.append(pid)
	return out


func is_supplied(d: DivisionState) -> bool:
	return d != null and is_province_supplied(d.owner, d.province)


## Divisions of [param nid] that are out of supply (id order).
func out_of_supply_divisions(nid: String) -> Array[DivisionState]:
	var out: Array[DivisionState] = []
	var s := supplied_set(nid)
	for d in GameState.divisions_of(nid):
		if not s.has(d.province):
			out.append(d)
	out.sort_custom(func(a: DivisionState, b: DivisionState) -> bool: return a.id < b.id)
	return out


## HP / organization lost per day by an out-of-supply division.
func attrition_hp(d: DivisionState) -> float:
	return _r("attrition_per_day", 0.02) * float(_stats(d).hp)


func attrition_org(d: DivisionState) -> float:
	return _r("attrition_org_per_day", 0.05) * float(_stats(d).organization)


## Short status text for the UI.
func status_text(d: DivisionState) -> String:
	if is_supplied(d):
		return "In supply"
	return "OUT OF SUPPLY (-%d HP/day)" % roundi(attrition_hp(d))


func _stats(d: DivisionState) -> Dictionary:
	var n: NationState = GameState.nation(d.owner)
	return TechEffects.division_stats(d.template, n.researched if n else [])


# --- Daily attrition -----------------------------------------------------------

func run_daily() -> void:
	if not GameState.active or GameState.game_over:
		return
	var sets: Dictionary = {}
	var ids: Array = GameState.divisions.keys()
	ids.sort()
	var lost: Dictionary = {}       # pid -> count of player divisions newly out of supply
	var restored: Dictionary = {}   # pid -> count of player divisions back in supply
	var now_out: Dictionary = {}
	var dead: Array[DivisionState] = []
	for did in ids:
		var d: DivisionState = GameState.divisions.get(did)
		if d == null:
			continue
		var n: NationState = GameState.nation(d.owner)
		if n == null or n.capitulated:
			continue
		if not sets.has(d.owner):
			sets[d.owner] = supplied_set(d.owner)
		var supplied: bool = sets[d.owner].has(d.province)
		if d.owner == GameState.player_nation:
			if not supplied:
				now_out[d.id] = true
				if not _player_out.has(d.id):
					lost[d.province] = int(lost.get(d.province, 0)) + 1
			elif _player_out.has(d.id):
				restored[d.province] = int(restored.get(d.province, 0)) + 1
		if supplied:
			continue
		d.hp = maxf(0.0, d.hp - attrition_hp(d))
		d.organization = maxf(0.0, d.organization - attrition_org(d))
		if d.hp <= 0.0:
			dead.append(d)
	for d in dead:
		now_out.erase(d.id)
		if _combat:
			_combat.destroy(d)
		else:
			GameState.remove_division(d.id)
			EventBus.division_destroyed.emit(d.id)
	_player_out = now_out
	for pid in lost:
		EventBus.notify.emit("%d division%s out of supply in %s" % [lost[pid], "" if lost[pid] == 1 else "s",
			GameData.province_name(pid)])
	for pid in restored:
		EventBus.notify.emit("Supply restored in %s" % GameData.province_name(pid))
	check_changes()


# --- Change tracking -------------------------------------------------------------

func queue_check() -> void:
	if _check_queued:
		return
	_check_queued = true
	check_changes.call_deferred()


## Emit supply_changed for every nation whose supplied set differs from the
## last announced one.
func check_changes() -> void:
	_check_queued = false
	if not GameState.active:
		return
	for nid in GameData.nation_ids:
		var now := supplied_provinces(nid)
		if not _snapshot.has(nid) or _snapshot[nid] != now:
			_snapshot[nid] = now
			EventBus.supply_changed.emit(nid)


func _on_game_state_ready() -> void:
	_snapshot.clear()
	_player_out.clear()
	if GameState.active:
		for nid in GameData.nation_ids:
			_snapshot[nid] = supplied_provinces(nid)
		for d in out_of_supply_divisions(GameState.player_nation):
			_player_out[d.id] = true
