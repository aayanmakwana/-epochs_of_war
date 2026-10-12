extends Node
## Strategic combat (autoload "Combat", step 10).
##
## A division that reaches full movement progress towards a hostile province
## (Movement.hostile_entry hook) either enters it (no enemy divisions there ->
## the province is captured on arrival) or starts / joins the battle there and
## waits in its own province (held at progress 1.0) until the battle ends.
##
## Battles live in GameState.battles (province -> {province, attacker, defender,
## attackers: [division ids], days, start_day}) so they are saved. Defenders are
## recomputed every tick: the divisions in the province whose owner is at war
## with the attacking nation.
##
## Daily system "combat" (order 45, after movement): each side deals
##   damage = combat_damage_scale x attack x clamp(attack / enemy defense, min, max)
## split evenly over the enemy divisions (organization and HP loss). Attack and
## defense are summed over the side's divisions (x strength from HP), the
## attacker's attack is modified by the terrain attack_modifier and artillery
## support, the defender's defense by terrain defense_bonus + entrenchment.
## Division at 0 HP -> destroyed. Defender at 0 org -> retreats to an adjacent
## friendly province (destroyed if none). Attacker at 0 org -> stops (it is
## still in its own province). No defenders left -> the attackers enter and the
## province is captured (controller changes; the owner keeps the claim until
## capitulation, step 13). No attackers left -> defender holds.
## Daily system "combat_recovery" (order 50): entrenchment grows for divisions
## that are not moving; divisions out of battle recover organization and, in
## their own territory, HP.

var _movement: Node


func _ready() -> void:
	_movement = get_node_or_null("/root/Movement")
	if _movement:
		_movement.hostile_entry = _on_hostile_entry
	Simulation.register_daily("combat", run_daily, 45)
	Simulation.register_daily("combat_recovery", run_recovery, 50)
	EventBus.division_moved.connect(_on_division_moved)


func _r(key: String, def: float) -> float:
	return float(GameData.rule(key, def))


# --- Queries -------------------------------------------------------------------

func has_battle(pid: String) -> bool:
	return GameState.battles.has(pid)


func battle_at(pid: String) -> Dictionary:
	return GameState.battles.get(pid, {})


## Enemy divisions in [param pid] that fight a nation [param attacker_nid].
func defenders(pid: String, attacker_nid: String) -> Array[DivisionState]:
	var out: Array[DivisionState] = []
	var n: NationState = GameState.nation(attacker_nid)
	if n == null:
		return out
	for d in GameState.divisions_in(pid):
		if d.owner != attacker_nid and n.is_at_war_with(d.owner):
			out.append(d)
	out.sort_custom(func(a: DivisionState, b: DivisionState) -> bool: return a.id < b.id)
	return out


## Divisions still attacking [param pid] (exist, still ordered into it).
func attackers(pid: String) -> Array[DivisionState]:
	var out: Array[DivisionState] = []
	var b: Dictionary = battle_at(pid)
	for did in b.get("attackers", []):
		var d: DivisionState = GameState.division(int(did))
		if d and d.is_moving() and d.path[0] == pid:
			out.append(d)
	return out


func is_in_battle(d: DivisionState) -> bool:
	for pid in GameState.battles:
		if GameState.battles[pid].attackers.has(d.id) and d.is_moving() and d.path[0] == pid:
			return true
		if d.province == pid and d.owner != GameState.battles[pid].attacker \
				and GameState.nation(GameState.battles[pid].attacker).is_at_war_with(d.owner):
			return true
	return false


func _stats(d: DivisionState) -> Dictionary:
	var n: NationState = GameState.nation(d.owner)
	return TechEffects.division_stats(d.template, n.researched if n else [])


func strength(d: DivisionState) -> float:
	var max_hp := maxf(1.0, float(_stats(d).hp))
	return 1.0 - _r("combat_hp_strength_weight", 0.5) * (1.0 - clampf(d.hp / max_hp, 0.0, 1.0))


## Side values for a battle in [param pid]:
## {att_attack, att_defense, def_attack, def_defense}.
func powers(pid: String, atk: Array[DivisionState], dfs: Array[DivisionState]) -> Dictionary:
	var terrain: Dictionary = GameData.terrain_of(pid)
	var ent_bonus := _r("entrenchment_defense_bonus", 0.25)
	var out := {"att_attack": 0.0, "att_defense": 0.0, "def_attack": 0.0, "def_defense": 0.0}
	var att_support := 0.0
	var def_support := 0.0
	for d in atk:
		var s := _stats(d)
		var k := strength(d)
		out.att_attack += float(s.attack) * k
		out.att_defense += float(s.defense) * k
		att_support = maxf(att_support, float(s.support_attack_bonus))
	for d in dfs:
		var s := _stats(d)
		var k := strength(d)
		out.def_attack += float(s.attack) * k
		out.def_defense += float(s.defense) * k * (1.0 + float(terrain.get("defense_bonus", 0.0)) + d.entrenchment * ent_bonus)
		def_support = maxf(def_support, float(s.support_attack_bonus))
	out.att_attack *= (1.0 + att_support) * maxf(0.1, 1.0 + float(terrain.get("attack_modifier", 0.0)))
	out.def_attack *= 1.0 + def_support
	return out


## Damage a side with [param attack] deals to a side with [param defense].
func damage(attack: float, defense: float) -> float:
	var ratio := clampf(attack / maxf(1.0, defense), _r("combat_ratio_min", 0.25), _r("combat_ratio_max", 4.0))
	return _r("combat_damage_scale", 1.8) * attack * ratio


## Attacker share of the remaining organization in [0, 1] (0.5 = even).
func balance(pid: String) -> float:
	var b := battle_at(pid)
	if b.is_empty():
		return 0.5
	var a := 0.0
	var df := 0.0
	for d in attackers(pid):
		a += d.organization
	for d in defenders(pid, b.attacker):
		df += d.organization
	return 0.5 if a + df <= 0.0 else a / (a + df)


# --- Battle lifecycle -----------------------------------------------------------

func _on_hostile_entry(d: DivisionState, pid: String) -> bool:
	if defenders(pid, d.owner).is_empty():
		return true   # undefended: enter, captured in _on_division_moved
	var started := false
	if not GameState.battles.has(pid):
		GameState.battles[pid] = {
			"province": pid, "attacker": d.owner, "defender": GameState.province(pid).controller,
			"attackers": [], "days": 0, "start_day": GameState.day_index,
		}
		started = true
	var b: Dictionary = GameState.battles[pid]
	if not b.attackers.has(d.id):
		b.attackers.append(d.id)
	if started:
		EventBus.battle_started.emit(pid)
		if _involves_player(b):
			EventBus.notify.emit("Battle for %s: %s attacks %s" % [GameData.province_name(pid),
				GameData.nation_name(b.attacker), GameData.nation_name(b.defender)])
	return false


func _involves_player(b: Dictionary) -> bool:
	return b.attacker == GameState.player_nation or b.defender == GameState.player_nation


func run_daily() -> void:
	if not GameState.active or GameState.game_over:
		return
	var pids: Array = GameState.battles.keys()
	pids.sort()
	for pid in pids:
		if GameState.battles.has(pid):
			_tick(pid)


func _tick(pid: String) -> void:
	var b: Dictionary = GameState.battles[pid]
	var atk := attackers(pid)
	var dfs := defenders(pid, b.attacker)
	if atk.is_empty() or dfs.is_empty():
		_finish(pid, dfs.is_empty() and not atk.is_empty())
		return
	b.days = int(b.days) + 1
	var p := powers(pid, atk, dfs)
	_apply(dfs, damage(p.att_attack, p.def_defense))
	_apply(atk, damage(p.def_attack, p.att_defense))
	for d in dfs:
		if d.hp <= 0.0:
			destroy(d)
		elif d.organization <= 0.0:
			retreat(d)
	for d in atk:
		if d.hp <= 0.0:
			destroy(d)
		elif d.organization <= 0.0 and _movement:
			_movement.stop(d.id)   # falls back: it never left its own province
	atk = attackers(pid)
	dfs = defenders(pid, b.attacker)
	if atk.is_empty() or dfs.is_empty():
		_finish(pid, dfs.is_empty() and not atk.is_empty())


func _apply(divs: Array[DivisionState], dmg: float) -> void:
	if divs.is_empty():
		return
	var share := dmg / divs.size()
	for d in divs:
		d.organization = maxf(0.0, d.organization - share * _r("combat_org_per_damage", 1.0))
		d.hp = maxf(0.0, d.hp - share * _r("combat_hp_per_damage", 0.4))


func _finish(pid: String, attacker_won: bool) -> void:
	var b: Dictionary = GameState.battles[pid]
	var atk := attackers(pid)
	GameState.battles.erase(pid)
	if attacker_won:
		for d in atk:
			if _movement:
				_movement.enter_province(d, pid)   # first entry captures the province
	else:
		for d in atk:
			if _movement:
				_movement.stop(d.id)
	var winner: String = b.attacker if attacker_won else b.defender
	var loser: String = b.defender if attacker_won else b.attacker
	if GameState.nation(winner):
		GameState.nation(winner).stats.battles_won += 1
	if GameState.nation(loser):
		GameState.nation(loser).stats.battles_lost += 1
	EventBus.battle_ended.emit(pid, attacker_won)
	if _involves_player(b):
		EventBus.notify.emit("Battle for %s: %s won" % [GameData.province_name(pid), GameData.nation_name(winner)])


## Retreat a defender to an adjacent friendly province (prefer one without a
## battle); destroyed if there is none.
func retreat(d: DivisionState) -> void:
	var best := ""
	for nb in GameData.adjacent(d.province):
		if _movement == null or not _movement.is_passable(d.owner, nb):
			continue
		if not GameState.battles.has(nb):
			best = nb
			break
		if best == "":
			best = nb
	if best == "":
		destroy(d)
		return
	d.path = []
	d.move_progress = 0.0
	d.path.append(best)
	_movement.enter_province(d, best)
	if d.owner == GameState.player_nation:
		EventBus.notify.emit("Division #%d retreats to %s" % [d.id, GameData.province_name(best)])


func destroy(d: DivisionState) -> void:
	var n: NationState = GameState.nation(d.owner)
	if n:
		n.stats.divisions_lost += 1
	GameState.remove_division(d.id)
	EventBus.division_destroyed.emit(d.id)
	if d.owner == GameState.player_nation:
		EventBus.notify.emit("Division #%d destroyed in %s" % [d.id, GameData.province_name(d.province)])


func _on_division_moved(did: int, _from: String, to: String) -> void:
	var d: DivisionState = GameState.division(did)
	if d == null or _movement == null or GameState.battles.has(to):
		return
	if _movement.is_hostile(d.owner, to) and defenders(to, d.owner).is_empty():
		capture(to, d.owner)


## Hand [param pid] to [param nid] (controller; the owner keeps its claim).
func capture(pid: String, nid: String) -> void:
	var ps: ProvinceState = GameState.province(pid)
	if ps == null or ps.controller == nid:
		return
	var old := ps.controller
	ps.controller = nid
	if GameState.nation(nid):
		GameState.nation(nid).stats.provinces_conquered += 1
	EventBus.province_captured.emit(pid, nid, old)
	EventBus.province_changed.emit(pid)
	if nid == GameState.player_nation:
		EventBus.notify.emit("%s captured" % GameData.province_name(pid))
	elif old == GameState.player_nation:
		EventBus.notify.emit("%s lost to %s" % [GameData.province_name(pid), GameData.nation_name(nid)])


# --- Recovery -------------------------------------------------------------------

func run_recovery() -> void:
	if not GameState.active or GameState.game_over:
		return
	var ent_rate := _r("entrenchment_per_day", 0.1)
	for d: DivisionState in GameState.divisions.values():
		if not d.is_moving():
			d.entrenchment = minf(1.0, d.entrenchment + ent_rate)
		if is_in_battle(d):
			continue
		var supply := get_node_or_null("/root/Supply")
		if supply and not supply.is_supplied(d):
			continue   # step 11: out of supply -> attrition instead of recovery
		var s := _stats(d)
		d.organization = minf(float(s.organization), d.organization + _r("org_recovery_per_day", 0.1) * float(s.organization))
		var ps: ProvinceState = GameState.province(d.province)
		if ps and ps.controller == d.owner:
			d.hp = minf(float(s.hp), d.hp + _r("hp_recovery_per_day", 0.02) * float(s.hp))
