class_name TacticalBattle
extends RefCounted
## Tactical battle state and unit actions (step 16). Pure data class (no
## autoload references) built on top of a TacticalDeployment.
##
## Phases alternate attacker -> defender (turn +1 when the attacker's phase
## starts again). In its side's phase every unit gets:
##   - movement: `moves_left` points (= movement) spent on tile move costs
##     (Dijkstra, 4 directions). Units may pass through own units but not
##     through enemies, and never end on an occupied tile. Moving clears dig in
##     and turns the unit's `facing` to the direction of its last step.
##   - one action (`acted`):
##       attack     - an enemy within `attack_range` (Manhattan). Ends movement.
##       ability    - infantry dig_in: +2 defense until it moves.
##                    armor overrun: move next to / in range of an enemy and
##                    attack as ONE action; unused movement points are kept.
##                    artillery barrage: a tile in range; full damage to the enemy
##                    on it, half damage to enemies on the 4 adjacent tiles. Ends movement.
##       overwatch  - skip the action; during the enemy's next phase the unit fires
##                    at the first enemy that moves (ends a step) within its range.
##                    Ends movement; expires when the unit's own phase starts again.
##
## Damage = max(1, round(damage_scale x A x A / (A + D) x attack_multiplier)),
## A = attack x (0.5 + 0.5 x HP fraction), D = (defense + dig in) x (1 + tile defense bonus).
## Barrage splash = half of that (min 1). 0 HP -> destroyed (off the map).
##
## Step 17 adds turn limit, flanking (override attack_multiplier), morale, victory.

signal changed
signal event_logged(event: Dictionary)

var deployment: TacticalDeployment
var map: TacticalMap
var turn: int = 1
var active_side: String = "attacker"
var started: bool = false
var damage_scale: float = 1.5
## Every action as a dict: {kind: move|attack|overrun|barrage|dig_in|overwatch|overwatch_fire|destroyed|phase, ...}.
var events: Array[Dictionary] = []
var log_lines: PackedStringArray = []
## HP each unit had when the battle started (casualty accounting, step 17).
var start_hp: Dictionary = {}

# --- Battle flow (step 17) ---
## Emitted once when the battle ends: winner "attacker" | "defender".
signal finished(winner: String, reason: String)
## Defender wins if the attacker has not taken all objectives by the end of this turn.
var turn_limit: int = 20
## Extra damage factor when attacking from outside the target's front arc.
var flank_bonus: float = 0.5
## Units below this HP fraction roll a morale check at the start of their side's phase.
var morale_threshold: float = 0.3
## Probability of passing a morale check.
var morale_pass_chance: float = 0.5
var rng := RandomNumberGenerator.new()
var is_finished: bool = false
## "attacker" | "defender" once finished.
var winner: String = ""
## objectives | defender_eliminated | attacker_eliminated | turn_limit
var end_reason: String = ""
## Owner side of each map objective (same order as map.objectives). Last side to
## stand on it keeps it; all start with the defender.
var objective_owner: PackedStringArray = []
## Both sides had units on the map at start (elimination victories need this).
var contested: bool = false


func _init(dep: TacticalDeployment = null, rules: Dictionary = {}) -> void:
	deployment = dep
	map = dep.map if dep else null
	damage_scale = float(rules.get("damage_scale", 1.5))
	turn_limit = int(rules.get("turn_limit", 20))
	flank_bonus = float(rules.get("flank_damage_bonus", 0.5))
	morale_threshold = float(rules.get("morale_hp_threshold", 0.3))
	morale_pass_chance = float(rules.get("morale_pass_chance", 0.5))
	rng.seed = int(rules.get("seed", hash(map.city_id if map else "")))


## Begin the battle: turn 1, attacker phase.
func start() -> void:
	started = true
	turn = 1
	active_side = "attacker"
	objective_owner = PackedStringArray()
	for o in map.objectives:
		objective_owner.append("defender")
	for u in deployment.units:
		start_hp[u.id] = u.hp
		u.moves_left = 0
		u.acted = false
		u.overwatch = false
	for u in deployment.units:
		if u.is_active():
			_mark_objective(u)
	contested = not active_units("attacker").is_empty() and not active_units("defender").is_empty()
	_begin_phase(active_side)
	_changed()


static func other_side(side: String) -> String:
	return "defender" if side == "attacker" else "attacker"


## End the active side's phase; the other side's units get fresh movement/actions.
## After the defender's phase of the last turn the defender wins (turn limit).
func end_phase() -> void:
	if is_finished:
		return
	if active_side == "defender" and turn >= turn_limit:
		_finish("defender", "turn_limit")
		changed.emit()
		return
	active_side = other_side(active_side)
	if active_side == "attacker":
		turn += 1
	_begin_phase(active_side)
	_changed()


func _begin_phase(side: String) -> void:
	for u in deployment.units_of(side):
		u.begin_phase()
	_log({kind = "phase", side = side, turn = turn}, "Turn %d: %s phase" % [turn, side.capitalize()])
	_morale_checks(side)


## Morale: every active unit of [param side] under morale_threshold x max HP rolls;
## a failed check routs it (leaves the battle, keeps its HP).
func _morale_checks(side: String) -> void:
	for u in active_units(side):
		if float(u.hp) >= morale_threshold * float(u.max_hp):
			continue
		var roll := rng.randf()
		if roll < morale_pass_chance:
			_log({kind = "morale_pass", unit = u.id}, "%s holds (morale check passed)" % _uname(u))
		else:
			rout(u)


## Remove [param u] from the battle as routed.
func rout(u: TacticalUnit) -> void:
	var at := u.pos
	u.routed = true
	u.overwatch = false
	u.dug_in = false
	u.pos = TacticalUnit.NO_POS
	_log({kind = "routed", unit = u.id, tile = at}, "%s routs and leaves the battle" % _uname(u))


func _changed() -> void:
	_check_victory()
	changed.emit()


## Objectives currently owned by the attacker.
func attacker_objectives() -> int:
	var n := 0
	for s in objective_owner:
		if s == "attacker":
			n += 1
	return n


func _mark_objective(u: TacticalUnit) -> void:
	if map == null or not map.is_objective(u.pos):
		return
	var i := map.objectives.find(u.pos)
	if i < 0 or i >= objective_owner.size() or objective_owner[i] == u.side:
		return
	objective_owner[i] = u.side
	_log({kind = "objective", unit = u.id, objective = i, side = u.side},
		"%s takes objective %d" % [_uname(u), i + 1])


## End the battle if a side has won.
func _check_victory() -> void:
	if not started or is_finished:
		return
	if not objective_owner.is_empty() and attacker_objectives() == objective_owner.size():
		_finish("attacker", "objectives")
	elif not contested:
		return   # one side never had units on the map (test setups): no elimination victory
	elif active_units("attacker").is_empty():
		_finish("defender", "attacker_eliminated")
	elif active_units("defender").is_empty():
		_finish("attacker", "defender_eliminated")


func _finish(w: String, reason: String) -> void:
	if is_finished:
		return
	is_finished = true
	winner = w
	end_reason = reason
	var why: String = {"objectives": "all objectives taken", "defender_eliminated": "defenders eliminated",
		"attacker_eliminated": "attackers eliminated", "turn_limit": "turn limit reached"}.get(reason, reason)
	_log({kind = "victory", side = w, reason = reason}, "%s wins (%s)" % [w.capitalize(), why])
	finished.emit(w, reason)


## Division ids per side: {"attacker": [...], "defender": [...]}.
func divisions() -> Dictionary:
	var out := {"attacker": [], "defender": []}
	for u in deployment.units:
		if u.division_id >= 0 and not out[u.side].has(u.division_id):
			out[u.side].append(u.division_id)
	return out


## Outcome: {finished, winner, attacker_won, reason, turn, objectives, casualties: {division id: 0..1}}.
func result() -> Dictionary:
	var cas := {}
	for side in ["attacker", "defender"]:
		for did in divisions()[side]:
			cas[did] = casualty_fraction(did)
	return {"finished": is_finished, "winner": winner, "attacker_won": winner == "attacker",
		"reason": end_reason, "turn": turn, "objectives": attacker_objectives(), "casualties": cas}


# --- Queries -------------------------------------------------------------------

func unit(uid: int) -> TacticalUnit:
	return deployment.unit(uid)


## Active (on the map, alive) unit at [param p], or null.
func unit_at(p: Vector2i) -> TacticalUnit:
	for u in deployment.units:
		if u.pos == p and u.is_active():
			return u
	return null


func active_units(side: String) -> Array[TacticalUnit]:
	var out: Array[TacticalUnit] = []
	for u in deployment.units_of(side):
		if u.is_active():
			out.append(u)
	return out


static func distance(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


func in_range(u: TacticalUnit, p: Vector2i) -> bool:
	return distance(u.pos, p) <= u.attack_range


## Effective defense of [param u] standing on its tile.
func effective_defense(u: TacticalUnit) -> float:
	return u.base_defense() * (1.0 + map.defense_bonus(u.pos))


func effective_attack(u: TacticalUnit) -> float:
	return u.attack * (0.5 + 0.5 * float(u.hp) / maxf(1.0, float(u.max_hp)))


## True if [param p] lies in the front arc of [param u]: the 3 tiles ahead in its
## facing (straight ahead and the two forward diagonals) and the 90-degree cone
## they open further out (so ranged fire from straight ahead is frontal too).
static func in_front_arc(u: TacticalUnit, p: Vector2i) -> bool:
	var f := u.facing
	if f == Vector2i.ZERO:
		return true
	var rel := p - u.pos
	var ahead := rel.x * f.x + rel.y * f.y
	var across := absi(rel.x * f.y - rel.y * f.x)
	return ahead > 0 and across <= ahead


## Attack from outside the target's front arc (step 17).
func is_flanking(attacker: TacticalUnit, target: TacticalUnit) -> bool:
	return not in_front_arc(target, attacker.pos)


## Extra damage factor: 1 + flank_bonus when flanking, else 1.
func attack_multiplier(attacker: TacticalUnit, target: TacticalUnit) -> float:
	return 1.0 + flank_bonus if is_flanking(attacker, target) else 1.0


## Damage [param attacker] deals to [param target] with a normal attack.
func damage(attacker: TacticalUnit, target: TacticalUnit) -> int:
	var a := effective_attack(attacker)
	var d := effective_defense(target)
	var raw := damage_scale * a * a / maxf(0.01, a + d) * attack_multiplier(attacker, target)
	return maxi(1, int(round(raw)))


func splash_damage(attacker: TacticalUnit, target: TacticalUnit) -> int:
	return maxi(1, int(round(damage(attacker, target) * 0.5)))


## Dijkstra over move costs within the unit's moves_left. Returns
## {dist: {tile: cost}, prev: {tile: previous tile}} (includes the start tile and
## own-occupied tiles it may pass through).
func _search(u: TacticalUnit) -> Dictionary:
	var dist := {u.pos: 0}
	var prev := {}
	var open: Array[Vector2i] = [u.pos]
	while not open.is_empty():
		var best := 0
		for i in open.size():
			if dist[open[i]] < dist[open[best]]:
				best = i
		var p: Vector2i = open[best]
		open.remove_at(best)
		for n in map.neighbors(p):
			var c := map.move_cost(n)
			if c < 0:
				continue
			var other := unit_at(n)
			if other != null and other.side != u.side:
				continue
			var nd: int = dist[p] + c
			if nd > u.moves_left:
				continue
			if not dist.has(n) or nd < dist[n]:
				dist[n] = nd
				prev[n] = p
				if not open.has(n):
					open.append(n)
	return {dist = dist, prev = prev}


## Tiles unit [param uid] can move to this phase: tile -> movement cost.
func reachable(uid: int) -> Dictionary:
	var out := {}
	var u := unit(uid)
	if u == null or not u.is_active() or u.moves_left <= 0:
		return out
	var dist: Dictionary = _search(u).dist
	for t in dist:
		if t != u.pos and unit_at(t) == null:
			out[t] = dist[t]
	return out


## Cheapest path (excluding the start) for [param uid] to [param target]; empty if unreachable.
func path_to(uid: int, target: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var u := unit(uid)
	if u == null or not u.is_active():
		return out
	var s := _search(u)
	if not s.dist.has(target) or target == u.pos:
		return out
	var p := target
	while p != u.pos:
		out.push_front(p)
		p = s.prev[p]
	return out


func _phase_error(u: TacticalUnit) -> String:
	if not started:
		return "The battle has not started"
	if is_finished:
		return "The battle is over"
	if u == null or u.destroyed:
		return "No such unit"
	if not u.is_active():
		return "Unit is in reserve"
	if u.side != active_side:
		return "Not this side's phase"
	return ""


## "" if [param uid] may move to [param target] now, else the reason.
func move_error(uid: int, target: Vector2i) -> String:
	var u := unit(uid)
	var e := _phase_error(u)
	if e != "":
		return e
	if not map.in_bounds(target):
		return "Outside the map"
	if target == u.pos:
		return "Already there"
	if not map.is_passable(target):
		return "%s is impassable" % map.tile_name(target)
	if unit_at(target) != null:
		return "Tile is occupied"
	if u.moves_left <= 0:
		return "No movement points left"
	if not reachable(uid).has(target):
		return "Out of reach (%d movement left)" % u.moves_left
	return ""


func can_move(uid: int, target: Vector2i) -> bool:
	return move_error(uid, target) == ""


## Move along the cheapest path. Enemy overwatch may fire after each step;
## a destroyed unit stops. Returns true if the order was accepted.
func move_unit(uid: int, target: Vector2i) -> bool:
	if not can_move(uid, target):
		return false
	_walk(unit(uid), path_to(uid, target))
	_changed()
	return true


func _walk(u: TacticalUnit, path: Array[Vector2i]) -> void:
	var from := u.pos
	for step in path:
		var prev := u.pos
		u.moves_left -= map.move_cost(step)
		u.pos = step
		u.facing = step - prev
		u.dug_in = false
		_check_overwatch(u)
		if u.destroyed:
			break
		_mark_objective(u)
	if u.pos != from or u.destroyed:
		_log({kind = "move", unit = u.id, from = from, to = u.pos if not u.destroyed else from},
			"%s moves (%d,%d) -> (%d,%d)" % [_uname(u), from.x, from.y, u.pos.x, u.pos.y] if not u.destroyed
			else "%s destroyed while moving" % _uname(u))


func _check_overwatch(mover: TacticalUnit) -> void:
	for w in deployment.units_of(other_side(mover.side)):
		if mover.destroyed:
			return
		if not w.overwatch or not w.is_active() or not in_range(w, mover.pos):
			continue
		w.overwatch = false
		var dmg := damage(w, mover)
		_log({kind = "overwatch_fire", unit = w.id, target = mover.id, damage = dmg},
			"Overwatch! %s fires at %s: -%d HP" % [_uname(w), _uname(mover), dmg])
		_apply_damage(mover, dmg)


# --- Actions -------------------------------------------------------------------

func _action_error(u: TacticalUnit) -> String:
	var e := _phase_error(u)
	if e != "":
		return e
	if u.acted:
		return "Already acted this turn"
	return ""


## "" if [param uid] may attack unit [param target_uid], else the reason.
func attack_error(uid: int, target_uid: int) -> String:
	var u := unit(uid)
	var e := _action_error(u)
	if e != "":
		return e
	var t := unit(target_uid)
	if t == null or not t.is_active():
		return "No target"
	if t.side == u.side:
		return "Cannot attack own units"
	if not in_range(u, t.pos):
		return "Target out of range (%d)" % u.attack_range
	return ""


func can_attack(uid: int, target_uid: int) -> bool:
	return attack_error(uid, target_uid) == ""


## Enemy units [param uid] can attack from where it stands.
func attack_targets(uid: int) -> Array[TacticalUnit]:
	var out: Array[TacticalUnit] = []
	var u := unit(uid)
	if u == null:
		return out
	for t in active_units(other_side(u.side)):
		if can_attack(uid, t.id):
			out.append(t)
	return out


## Attack: uses the action and ends the unit's movement. Returns damage dealt (-1 refused).
func attack(uid: int, target_uid: int) -> int:
	if not can_attack(uid, target_uid):
		return -1
	var u := unit(uid)
	var dmg := _strike(u, unit(target_uid), "attack")
	u.acted = true
	u.moves_left = 0
	_changed()
	return dmg


func _strike(u: TacticalUnit, t: TacticalUnit, kind: String) -> int:
	var dmg := damage(u, t)
	var flank := is_flanking(u, t)
	_log({kind = kind, unit = u.id, target = t.id, damage = dmg, flank = flank},
		"%s %s %s: -%d HP%s" % [_uname(u), "overruns" if kind == "overrun" else "attacks", _uname(t), dmg,
		" (flank)" if flank else ""])
	_apply_damage(t, dmg)
	return dmg


## "" if [param uid] may use its ability (target unit / tile depend on the ability), else the reason.
func ability_error(uid: int, target: Vector2i = TacticalUnit.NO_POS) -> String:
	var u := unit(uid)
	var e := _action_error(u)
	if e != "":
		return e
	match u.ability:
		"dig_in":
			if u.dug_in:
				return "Already dug in"
			return ""
		"overrun":
			if target == TacticalUnit.NO_POS:
				return "" if not overrun_targets(uid).is_empty() else "No enemy within reach"
			var t := unit_at(target)
			if t == null or t.side == u.side:
				return "Pick an enemy unit"
			if overrun_tile(uid, t.id) == TacticalUnit.NO_POS:
				return "Enemy out of reach"
			return ""
		"barrage":
			if target == TacticalUnit.NO_POS:
				return ""
			if not map.in_bounds(target):
				return "Outside the map"
			if target == u.pos or distance(u.pos, target) > u.attack_range:
				return "Target out of range (%d)" % u.attack_range
			return ""
	return "No ability"


## True if the ability needs a target tile (overrun, barrage).
static func ability_needs_target(ability: String) -> bool:
	return ability == "overrun" or ability == "barrage"


static func ability_name(ability: String) -> String:
	match ability:
		"dig_in":
			return "Dig in"
		"overrun":
			return "Overrun"
		"barrage":
			return "Barrage"
	return ability.capitalize()


## Use the unit's ability. dig_in ignores [param target]; overrun takes the enemy's
## tile; barrage takes the target tile. Returns true if done.
func use_ability(uid: int, target: Vector2i = TacticalUnit.NO_POS) -> bool:
	var u := unit(uid)
	if u == null:
		return false
	match u.ability:
		"dig_in":
			return dig_in(uid)
		"overrun":
			var t := unit_at(target)
			return t != null and overrun(uid, t.id)
		"barrage":
			return barrage(uid, target)
	return false


## Infantry: +2 defense until the unit moves.
func dig_in(uid: int) -> bool:
	var u := unit(uid)
	if u == null or u.ability != "dig_in" or ability_error(uid) != "":
		return false
	u.dug_in = true
	u.acted = true
	_log({kind = "dig_in", unit = u.id}, "%s digs in (+%d defense)" % [_uname(u), TacticalUnit.DIG_IN_DEFENSE])
	_changed()
	return true


## Tile from which [param uid] would overrun [param target_uid]: its own tile if the
## target is already in range, else the cheapest reachable tile in range. NO_POS if none.
func overrun_tile(uid: int, target_uid: int) -> Vector2i:
	var u := unit(uid)
	var t := unit(target_uid)
	if u == null or t == null or not t.is_active() or t.side == u.side:
		return TacticalUnit.NO_POS
	if in_range(u, t.pos):
		return u.pos
	var best := TacticalUnit.NO_POS
	var best_cost := 1 << 30
	var reach := reachable(uid)
	for p in reach:
		if distance(p, t.pos) <= u.attack_range:
			var c: int = reach[p]
			if c < best_cost or (c == best_cost and (p.y * map.size + p.x) < (best.y * map.size + best.x)):
				best = p
				best_cost = c
	return best


## Enemy units the armor can overrun this phase.
func overrun_targets(uid: int) -> Array[TacticalUnit]:
	var out: Array[TacticalUnit] = []
	var u := unit(uid)
	if u == null or u.ability != "overrun":
		return out
	for t in active_units(other_side(u.side)):
		if overrun_tile(uid, t.id) != TacticalUnit.NO_POS:
			out.append(t)
	return out


## Armor: move into range of the target and attack as one action; leftover
## movement is kept. [param via] forces the attack tile (must be reachable/in range).
func overrun(uid: int, target_uid: int, via: Vector2i = TacticalUnit.NO_POS) -> bool:
	var u := unit(uid)
	var t := unit(target_uid)
	if u == null or t == null or u.ability != "overrun" or _action_error(u) != "":
		return false
	var tile := via if via != TacticalUnit.NO_POS else overrun_tile(uid, target_uid)
	if tile == TacticalUnit.NO_POS or not t.is_active() or t.side == u.side:
		return false
	if distance(tile, t.pos) > u.attack_range:
		return false
	if tile != u.pos and not reachable(uid).has(tile):
		return false
	u.acted = true
	if tile != u.pos:
		_walk(u, path_to(uid, tile))
	if not u.destroyed and t.is_active() and in_range(u, t.pos):
		_strike(u, t, "overrun")
	_changed()
	return true


## Tiles an artillery battery can barrage (in range, not its own tile).
func barrage_tiles(uid: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var u := unit(uid)
	if u == null or u.ability != "barrage":
		return out
	for y in map.size:
		for x in map.size:
			var p := Vector2i(x, y)
			if p != u.pos and distance(u.pos, p) <= u.attack_range:
				out.append(p)
	return out


## Tiles hit by a barrage on [param center]: the centre first, then its 4 neighbours.
func barrage_area(center: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = [center]
	out.append_array(map.neighbors(center))
	return out


## Artillery: full damage to the enemy on [param target], half damage to enemies
## on the adjacent tiles (own units are not hit). Uses the action, ends movement.
func barrage(uid: int, target: Vector2i) -> bool:
	var u := unit(uid)
	if u == null or u.ability != "barrage" or ability_error(uid, target) != "":
		return false
	u.acted = true
	u.moves_left = 0
	var hits: Array = []
	for p in barrage_area(target):
		var t := unit_at(p)
		if t == null or t.side == u.side:
			continue
		var dmg := damage(u, t) if p == target else splash_damage(u, t)
		hits.append({unit = t.id, damage = dmg})
	_log({kind = "barrage", unit = u.id, tile = target, hits = hits},
		"%s barrages (%d,%d): %d unit(s) hit" % [_uname(u), target.x, target.y, hits.size()])
	for h in hits:
		_apply_damage(unit(h.unit), h.damage)
	_changed()
	return true


func overwatch_error(uid: int) -> String:
	return _action_error(unit(uid))


## Skip the action and watch: fires at the first enemy moving within range in the enemy phase.
func set_overwatch(uid: int) -> bool:
	var u := unit(uid)
	if overwatch_error(uid) != "":
		return false
	u.overwatch = true
	u.acted = true
	u.moves_left = 0
	_log({kind = "overwatch", unit = u.id}, "%s on overwatch" % _uname(u))
	_changed()
	return true


# --- Damage --------------------------------------------------------------------

func _apply_damage(t: TacticalUnit, dmg: int) -> void:
	t.hp = maxi(0, t.hp - dmg)
	if t.hp <= 0:
		_destroy(t)


func _destroy(t: TacticalUnit) -> void:
	var at := t.pos
	t.hp = 0
	t.destroyed = true
	t.overwatch = false
	t.dug_in = false
	t.pos = TacticalUnit.NO_POS
	_log({kind = "destroyed", unit = t.id, tile = at}, "%s destroyed" % _uname(t))


## Fraction of starting HP a strategic division lost in this battle (0..1).
func casualty_fraction(division_id: int) -> float:
	var start := 0
	var now := 0
	for u in deployment.units:
		if u.division_id == division_id:
			start += int(start_hp.get(u.id, u.hp))
			now += u.hp
	return 0.0 if start <= 0 else clampf(1.0 - float(now) / float(start), 0.0, 1.0)


# --- Distance fields (AI helpers) --------------------------------------------------

## Movement cost from every passable tile to the nearest of [param sources]
## (units ignored). Bucket queue: costs are small integers.
func distance_field(sources: Array[Vector2i]) -> Dictionary:
	var dist := {}
	var buckets: Array = [[]]
	for s in sources:
		if map.in_bounds(s) and not dist.has(s):
			dist[s] = 0
			buckets[0].append(s)
	var d := 0
	while d < buckets.size():
		var bucket: Array = buckets[d]
		var i := 0
		while i < bucket.size():
			var p: Vector2i = bucket[i]
			i += 1
			if dist[p] != d:
				continue
			for n in map.neighbors(p):
				var c := map.move_cost(n)
				if c < 0:
					continue
				var nd := d + c
				if not dist.has(n) or nd < dist[n]:
					dist[n] = nd
					while buckets.size() <= nd:
						buckets.append([])
					buckets[nd].append(n)
		d += 1
	return dist


func _uname(u: TacticalUnit) -> String:
	return "%s %s #%d" % [u.nation.capitalize(), u.name, u.id]


func _log(event: Dictionary, text: String) -> void:
	event["turn"] = turn
	event["text"] = text
	events.append(event)
	log_lines.append(text)
	event_logged.emit(event)
