class_name TacticalAI
extends RefCounted
## Minimal opponent for the tactical battle (step 16), used for the side the
## player does not command. Simple if/else per unit, in id order:
##   - armor: overrun the weakest enemy it can reach, else advance.
##   - others: attack the weakest enemy in range; otherwise advance and attack if
##     now in range; artillery barrages when an enemy is in range and another
##     enemy stands next to it.
##   - "advance" for the attacker = towards the nearest enemy if one is within
##     ENGAGE_DISTANCE movement, else towards the nearest objective. The defender
##     only moves when it can attack after moving; otherwise infantry digs in and
##     the rest go on overwatch.
## Step 17 may refine this (objectives, morale).

const ENGAGE_DISTANCE := 6


static func run_phase(battle: TacticalBattle, side: String) -> void:
	if battle == null or battle.active_side != side:
		return
	var ids: Array[int] = []
	for u in battle.active_units(side):
		ids.append(u.id)
	for uid in ids:
		var u := battle.unit(uid)
		if u == null or not u.is_active():
			continue
		act(battle, u)


static func _weakest(units: Array[TacticalUnit]) -> TacticalUnit:
	var best: TacticalUnit = null
	for t in units:
		if best == null or t.hp < best.hp or (t.hp == best.hp and t.id < best.id):
			best = t
	return best


static func act(battle: TacticalBattle, u: TacticalUnit) -> void:
	if u.ability == "overrun":
		var target := _weakest(battle.overrun_targets(u.id))
		if target != null:
			battle.overrun(u.id, target.id)
			return
	if _fire(battle, u):
		return
	var enemies := battle.active_units(TacticalBattle.other_side(u.side))
	if enemies.is_empty():
		return
	var goal := _move_goal(battle, u, enemies)
	if goal != TacticalUnit.NO_POS:
		battle.move_unit(u.id, goal)
		if not u.is_active():
			return
		if _fire(battle, u):
			return
	if u.acted:
		return
	if u.ability == "dig_in" and not u.dug_in:
		battle.dig_in(u.id)
	else:
		battle.set_overwatch(u.id)


## Attack (or barrage) from the current tile if possible.
static func _fire(battle: TacticalBattle, u: TacticalUnit) -> bool:
	var targets := battle.attack_targets(u.id)
	if targets.is_empty():
		return false
	var target := _weakest(targets)
	if u.ability == "barrage":
		for t in targets:
			for n in battle.map.neighbors(t.pos):
				var other := battle.unit_at(n)
				if other != null and other.side != u.side:
					return battle.barrage(u.id, t.pos)
	return battle.attack(u.id, target.id) >= 0


## Tile to move to this phase, or NO_POS to stay.
static func _move_goal(battle: TacticalBattle, u: TacticalUnit, enemies: Array[TacticalUnit]) -> Vector2i:
	var reach := battle.reachable(u.id)
	if reach.is_empty():
		return TacticalUnit.NO_POS
	# Any reachable tile from which an enemy is in range? Take the cheapest.
	var best := TacticalUnit.NO_POS
	var best_cost := 1 << 30
	for p in reach:
		for e in enemies:
			if TacticalBattle.distance(p, e.pos) <= u.attack_range and reach[p] < best_cost:
				best = p
				best_cost = reach[p]
	if best != TacticalUnit.NO_POS:
		return best
	if u.side == "defender":
		return TacticalUnit.NO_POS
	# Attacker: close in on nearby enemies, else head for the objectives.
	var enemy_tiles: Array[Vector2i] = []
	for e in enemies:
		enemy_tiles.append(e.pos)
	var field := battle.distance_field(enemy_tiles)
	if int(field.get(u.pos, 1 << 30)) > ENGAGE_DISTANCE:
		var objs: Array[Vector2i] = []
		for o in battle.map.objectives:
			var occ := battle.unit_at(o)
			if occ == null or occ.side != u.side:
				objs.append(o)
		if not objs.is_empty():
			field = battle.distance_field(objs)
	var here := int(field.get(u.pos, 1 << 30))
	var best_d := here
	for p in reach:
		var d := int(field.get(p, 1 << 30))
		if d < best_d or (d == best_d and best != TacticalUnit.NO_POS and reach[p] < reach[best]):
			best_d = d
			best = p
	return best
