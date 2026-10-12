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
	EventBus.game_state_ready.connect(_on_game_state_ready)


func _on_game_state_ready() -> void:
	pending_prompts.clear()
	for pid in GameState.battles:
		GameState.battles[pid].erase("tactical")   # no tactical view survives a load


# --- Tactical city battles (step 17) ---------------------------------------------
#
# A battle that starts in a major city with the player as attacker or defender
# raises a prompt (clock paused, EventBus.tactical_prompt_requested). Yes ->
# accept_tactical: the battle is flagged "tactical" (daily ticks skip it) and
# EventBus.tactical_battle_requested opens the TacticalView. No -> decline_tactical:
# normal daily auto-resolve. The view reports back with apply_tactical_result
# (battle finished) or abandon_tactical (left early: losses so far applied, then
# auto-resolve continues).

## Provinces whose "Command your forces?" prompt is waiting for an answer.
var pending_prompts: Array[String] = []


func should_prompt(pid: String) -> bool:
	if not bool(GameData.rule("tactical_prompts", true)) or not GameData.is_major_city(pid):
		return false
	var b := battle_at(pid)
	if b.is_empty() or not _involves_player(b):
		return false
	var ai := get_node_or_null("/root/AI")
	return ai == null or not ai.auto_resolves_tactical(GameState.player_nation)


func request_prompt(pid: String) -> void:
	if pending_prompts.has(pid):
		return
	pending_prompts.append(pid)
	var tm := get_node_or_null("/root/TimeManager")
	if tm:
		tm.pause()
	EventBus.tactical_prompt_requested.emit(pid)


func is_tactical(pid: String) -> bool:
	return bool(battle_at(pid).get("tactical", false))


## Player chose to command the battle: flag it and open the tactical view.
func accept_tactical(pid: String) -> bool:
	pending_prompts.erase(pid)
	if not has_battle(pid):
		return false
	GameState.battles[pid]["tactical"] = true
	EventBus.tactical_battle_requested.emit(pid)
	return true


## Player chose to auto-resolve: nothing changes, daily combat resolves it.
func decline_tactical(pid: String) -> void:
	pending_prompts.erase(pid)
	if has_battle(pid):
		GameState.battles[pid].erase("tactical")


func _max_hp(d: DivisionState) -> float:
	return maxf(1.0, float(_stats(d).hp))


## HP loss proportional to the tactical casualty fraction (of the HP it fought with).
func _apply_casualties(casualties: Dictionary) -> void:
	for did in casualties:
		var d: DivisionState = GameState.division(int(did))
		if d == null:
			continue
		var f := clampf(float(casualties[did]), 0.0, 1.0)
		d.hp = maxf(0.0, d.hp * (1.0 - f))
		d.organization = maxf(0.0, d.organization * (1.0 - f))


## Apply a finished tactical battle to the strategic layer. Every division loses
## HP in proportion to its tactical casualties; the losing side additionally loses
## a share of its remaining HP (defenders heavy: rules.tactical_defender_defeat_loss,
## attackers moderate: rules.tactical_attacker_defeat_loss) and all organization.
## Attacker won: surviving defenders retreat, the attackers enter and the province
## changes hands. Defender won: the attackers stay in (return to) their origin
## province. Emits tactical_battle_finished.
func apply_tactical_result(pid: String, attacker_won: bool, casualties: Dictionary) -> void:
	pending_prompts.erase(pid)
	_apply_casualties(casualties)
	var b := battle_at(pid)
	if not b.is_empty():
		b.erase("tactical")
		var losers: Array[DivisionState] = defenders(pid, b.attacker) if attacker_won else attackers(pid)
		var extra := _r("tactical_defender_defeat_loss", 0.4) if attacker_won else _r("tactical_attacker_defeat_loss", 0.2)
		for d in losers:
			d.hp = maxf(0.0, d.hp - d.hp * extra)
			d.organization = 0.0
		for d in defenders(pid, b.attacker) + attackers(pid):
			if d.hp < 0.5:
				destroy(d)
		if attacker_won:
			for d in defenders(pid, b.attacker):
				retreat(d)
		_finish(pid, attacker_won)
	else:
		for did in casualties:
			var d: DivisionState = GameState.division(int(did))
			if d and d.hp < 0.5:
				destroy(d)
	EventBus.tactical_battle_finished.emit(pid, attacker_won)


## The player left the tactical view before the end: apply the losses so far and
## let the strategic battle auto-resolve from here.
func abandon_tactical(pid: String, casualties: Dictionary) -> void:
	pending_prompts.erase(pid)
	_apply_casualties(casualties)
	for did in casualties:
		var d: DivisionState = GameState.division(int(did))
		if d and d.hp < 0.5:
			destroy(d)
	if has_battle(pid):
		GameState.battles[pid].erase("tactical")


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
		if should_prompt(pid):
			request_prompt(pid)
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
	if bool(b.get("tactical", false)):
		return   # the player commands this battle on the tactical map (step 17)
	if pending_prompts.has(pid) and int(b.get("start_day", -1)) == GameState.day_index:
		return   # prompt just raised: no auto-resolve damage before the player answers
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
