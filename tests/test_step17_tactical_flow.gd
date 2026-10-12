extends "res://tests/test_base.gd"
## Step 17: tactical battle flow (TacticalBattle logic): flanking, turn limit,
## objective capture, elimination, morale/rout, result + finished signal,
## AI play-out to the end.

const NO_POS := Vector2i(-1, -1)
var stats: Dictionary = {}
var _div_counter := 0


func make_map(size: int, fill: String = "street", objectives: Array = []) -> TacticalMap:
	var m := TacticalMap.new()
	m.city_id = "test"
	m.size = size
	var t := PackedStringArray()
	t.resize(size * size)
	t.fill(fill)
	m.tiles = t
	for o in objectives:
		m.objectives.append(o)
	return m


func make_battle(m: TacticalMap, rules: Dictionary = {}) -> TacticalBattle:
	var dep := TacticalDeployment.new(m)
	dep.attacker = "germany"
	dep.defender = "ussr"
	var r := {"damage_scale": 1.5, "flank_damage_bonus": 0.5, "turn_limit": 20,
		"morale_hp_threshold": 0.3, "morale_pass_chance": 0.5}
	r.merge(rules, true)
	return TacticalBattle.new(dep, r)


func add(b: TacticalBattle, side: String, type: String, pos: Vector2i, div := -1) -> TacticalUnit:
	var nation := "germany" if side == "attacker" else "ussr"
	if div < 0:
		_div_counter += 1
		div = 100 + _div_counter
	var u: TacticalUnit = b.deployment.add_division(side, nation, div, [type], stats)[0]
	u.pos = pos
	return u


func run_tests() -> void:
	var gd: Node = autoload("GameData")
	stats = gd.tactical.get("units", {})
	check_eq(float(gd.tactical.get("morale_pass_chance", -1.0)), 0.5, "morale_pass_chance in tactical.json")
	check_eq(int(gd.tactical.get("turn_limit", 0)), 20, "turn limit 20 in tactical.json")
	test_flanking()
	test_turn_limit()
	test_objectives()
	test_elimination()
	test_morale()
	test_result()
	test_play_out()


func test_flanking() -> void:
	var b := make_battle(make_map(12))
	var d := add(b, "defender", "infantry", Vector2i(5, 5))   # faces south (0, 1)
	var front := add(b, "attacker", "infantry", Vector2i(5, 6))
	var behind := add(b, "attacker", "infantry", Vector2i(5, 4))
	var side := add(b, "attacker", "infantry", Vector2i(4, 5))
	var diag := add(b, "attacker", "infantry", Vector2i(6, 6))
	var art := add(b, "attacker", "artillery", Vector2i(5, 8))
	b.start()
	check_eq(d.facing, Vector2i(0, 1), "defender faces south at start")
	check(TacticalBattle.in_front_arc(d, Vector2i(5, 6)), "tile ahead is in the front arc")
	check(TacticalBattle.in_front_arc(d, Vector2i(4, 6)) and TacticalBattle.in_front_arc(d, Vector2i(6, 6)),
		"forward diagonals are in the front arc")
	check(not TacticalBattle.in_front_arc(d, Vector2i(4, 5)) and not TacticalBattle.in_front_arc(d, Vector2i(6, 5)),
		"sides are outside the front arc")
	check(not TacticalBattle.in_front_arc(d, Vector2i(5, 4)), "behind is outside the front arc")
	check(TacticalBattle.in_front_arc(d, Vector2i(5, 8)), "straight ahead at range 3 is frontal")
	check(not b.is_flanking(front, d), "attack from the front: no flank")
	check(not b.is_flanking(diag, d), "attack from the forward diagonal: no flank")
	check(b.is_flanking(behind, d), "attack from behind flanks")
	check(b.is_flanking(side, d), "attack from the side flanks")
	check(not b.is_flanking(art, d), "artillery straight ahead: no flank")
	check_eq(b.attack_multiplier(front, d), 1.0, "frontal multiplier 1.0")
	check_eq(b.attack_multiplier(behind, d), 1.5, "flank multiplier 1.5 (+50%)")
	var plain := b.damage(front, d)
	var flank := b.damage(behind, d)
	check(flank > plain, "flank damage %d > frontal %d" % [flank, plain])
	var a := b.effective_attack(behind)
	var expected := maxi(1, int(round(1.5 * a * a / (a + b.effective_defense(d)) * 1.5)))
	check_eq(flank, expected, "flank damage formula x1.5")
	var hp := d.hp
	b.attack(behind.id, d.id)
	check_eq(d.hp, hp - flank, "flank attack applies the bonus")
	check(b.log_lines[b.log_lines.size() - 1].contains("(flank)"), "log marks the flank")
	# Facing follows movement.
	var b2 := make_battle(make_map(12))
	var mover := add(b2, "attacker", "infantry", Vector2i(2, 2))
	add(b2, "defender", "infantry", Vector2i(10, 10))
	b2.start()
	b2.move_unit(mover.id, Vector2i(4, 2))
	check_eq(mover.facing, Vector2i(1, 0), "facing = direction of the last step (east)")
	check(TacticalBattle.in_front_arc(mover, Vector2i(5, 2)) and not TacticalBattle.in_front_arc(mover, Vector2i(4, 1)),
		"front arc turns with the unit")


func test_turn_limit() -> void:
	var b := make_battle(make_map(12), {"turn_limit": 20})
	add(b, "attacker", "infantry", Vector2i(0, 11))
	add(b, "defender", "infantry", Vector2i(11, 0))
	var fired: Array = []
	b.finished.connect(func(w: String, r: String) -> void: fired.append([w, r]))
	b.start()
	var phases := 0
	while not b.is_finished and phases < 100:
		b.end_phase()
		phases += 1
	check(b.is_finished, "battle ends by itself")
	check_eq(phases, 40, "ends when the defender phase of turn 20 ends (40 phase ends)")
	check_eq(b.turn, 20, "turn stays at the limit")
	check_eq(b.winner, "defender", "defender wins on the turn limit")
	check_eq(b.end_reason, "turn_limit", "reason turn_limit")
	check_eq(fired.size(), 1, "finished emitted once")
	check(fired.size() == 1 and fired[0][0] == "defender", "finished carries the winner")
	b.end_phase()
	check_eq(b.turn, 20, "end_phase after the end is a no-op")
	check_eq(fired.size(), 1, "finished not emitted again")
	var u := b.active_units("attacker")[0]
	check(b.move_error(u.id, u.pos + Vector2i(1, 0)).contains("over"), "no orders after the battle ended")
	# Short limit for speed.
	var b2 := make_battle(make_map(12), {"turn_limit": 3})
	add(b2, "attacker", "infantry", Vector2i(0, 11))
	add(b2, "defender", "infantry", Vector2i(11, 0))
	b2.start()
	for i in 5:
		b2.end_phase()
	check(not b2.is_finished, "not over during turn 3's defender phase")
	b2.end_phase()
	check(b2.is_finished and b2.winner == "defender", "turn_limit rule read from rules")


func test_objectives() -> void:
	var objs := [Vector2i(5, 5), Vector2i(7, 5), Vector2i(5, 7)]
	var b := make_battle(make_map(12, "street", objs))
	var a1 := add(b, "attacker", "infantry", Vector2i(5, 8))
	var a2 := add(b, "attacker", "infantry", Vector2i(8, 5))
	var a3 := add(b, "attacker", "infantry", Vector2i(4, 7))
	var dfd := add(b, "defender", "infantry", Vector2i(6, 8))
	add(b, "defender", "infantry", Vector2i(11, 0))
	var fired: Array = []
	b.finished.connect(func(w: String, r: String) -> void: fired.append([w, r]))
	b.start()
	check_eq(b.objective_owner.size(), 3, "3 objective owners")
	check(Array(b.objective_owner) == ["defender", "defender", "defender"], "objectives start with the defender")
	check(b.move_unit(a1.id, Vector2i(5, 7)), "attacker moves onto objective 3")
	check_eq(b.objective_owner[2], "attacker", "attacker takes objective 3")
	check_eq(b.attacker_objectives(), 1, "1 objective held")
	check(b.move_unit(a1.id, Vector2i(5, 6)), "attacker steps off the objective")
	check_eq(b.objective_owner[2], "attacker", "objective stays attacker-held after leaving (last owner keeps it)")
	check(b.move_unit(a2.id, Vector2i(7, 5)), "attacker takes objective 2")
	check_eq(b.attacker_objectives(), 2, "2 objectives held")
	check(not b.is_finished, "2 of 3: battle continues")
	b.end_phase()
	check(b.move_unit(dfd.id, Vector2i(5, 7)), "defender moves onto objective 3")
	check_eq(b.objective_owner[2], "defender", "defender recaptures objective 3")
	b.end_phase()
	dfd.hp = 1
	check(b.attack(a1.id, dfd.id) > 0 and dfd.destroyed, "defender on the objective destroyed")
	check(not b.is_finished, "a defender remains elsewhere")
	check(b.move_unit(a3.id, Vector2i(5, 7)), "attacker retakes objective 3")
	check(not b.is_finished, "objective 1 still missing")
	check(b.move_unit(a2.id, Vector2i(5, 5)), "attacker takes objective 1")
	check(b.is_finished, "all 3 objectives taken ends the battle")
	check_eq(b.winner, "attacker", "attacker wins on objectives")
	check_eq(b.end_reason, "objectives", "reason objectives")
	check(fired.size() == 1 and fired[0] == ["attacker", "objectives"], "finished signal on objective victory")


func test_elimination() -> void:
	var b := make_battle(make_map(12))
	var a := add(b, "attacker", "armor", Vector2i(5, 6))
	var d := add(b, "defender", "infantry", Vector2i(5, 5))
	b.start()
	d.hp = 1
	b.attack(a.id, d.id)
	check(d.destroyed, "last defender destroyed")
	check(b.is_finished and b.winner == "attacker" and b.end_reason == "defender_eliminated",
		"defenders eliminated -> attacker wins")
	var b2 := make_battle(make_map(12))
	var a2 := add(b2, "attacker", "infantry", Vector2i(5, 6))
	var d2 := add(b2, "defender", "armor", Vector2i(5, 5))
	b2.start()
	b2.end_phase()
	a2.hp = 1
	b2.attack(d2.id, a2.id)
	check(b2.is_finished and b2.winner == "defender" and b2.end_reason == "attacker_eliminated",
		"attackers eliminated -> defender wins")
	# One-sided setups (no enemies at start) never end by elimination.
	var b3 := make_battle(make_map(12))
	add(b3, "attacker", "infantry", Vector2i(1, 1))
	b3.start()
	check(not b3.is_finished, "uncontested setup does not end immediately")


func test_morale() -> void:
	# Always fails: a weak unit routs at the start of its side's phase.
	var b := make_battle(make_map(12), {"morale_pass_chance": 0.0})
	var a := add(b, "attacker", "infantry", Vector2i(1, 1))
	var a_ok := add(b, "attacker", "infantry", Vector2i(2, 1))
	var d := add(b, "defender", "infantry", Vector2i(10, 10))
	var d_weak := add(b, "defender", "infantry", Vector2i(9, 10))
	d_weak.hp = 2   # 20% < 30%
	a.hp = 3        # exactly 30%: no check
	b.start()
	check(not a.routed, "unit at exactly 30% HP does not roll")
	check(not d_weak.routed, "defender not checked during the attacker phase")
	b.end_phase()
	check(d_weak.routed, "weak unit fails the check and routs at its phase start")
	check(not d_weak.is_active() and d_weak.pos == NO_POS, "routed unit leaves the map")
	check_eq(d_weak.hp, 2, "routed unit keeps its HP")
	check(not d_weak.destroyed, "routed is not destroyed")
	check(not b.deployment.reserve("defender").has(d_weak), "routed unit is not in the reserve")
	check(b.unit_at(Vector2i(9, 10)) == null, "tile freed")
	check(not d.routed, "healthy unit unaffected")
	var routs := b.events.filter(func(e: Dictionary) -> bool: return e.kind == "routed")
	check_eq(routs.size(), 1, "rout logged")
	# Always passes.
	var b2 := make_battle(make_map(12), {"morale_pass_chance": 1.0})
	var w := add(b2, "attacker", "infantry", Vector2i(1, 1))
	add(b2, "defender", "infantry", Vector2i(10, 10))
	w.hp = 1
	b2.start()
	check(not w.routed and w.is_active(), "passing the check keeps the unit")
	check(b2.events.any(func(e: Dictionary) -> bool: return e.kind == "morale_pass"), "pass logged")
	# Seeded RNG: identical battles give identical rolls.
	var outcomes: Array = []
	for run in 2:
		var bb := make_battle(make_map(12), {"seed": 42})
		var weak: Array = []
		for i in 6:
			var u := add(bb, "attacker", "infantry", Vector2i(i, 0), 500 + i)
			u.hp = 1
			weak.append(u)
		add(bb, "defender", "infantry", Vector2i(10, 10))
		bb.start()
		outcomes.append(weak.map(func(u: TacticalUnit) -> bool: return u.routed))
	check(outcomes[0] == outcomes[1], "seeded morale rolls are deterministic")
	check(outcomes[0].has(true) and outcomes[0].has(false), "50% pass chance: some rout, some hold (seed 42)")
	# Routing every attacker ends the battle.
	var b3 := make_battle(make_map(12), {"morale_pass_chance": 0.0})
	var lone := add(b3, "attacker", "infantry", Vector2i(1, 1))
	add(b3, "defender", "infantry", Vector2i(10, 10))
	b3.start()
	lone.hp = 1
	b3.end_phase()
	b3.end_phase()
	check(lone.routed, "lone weak attacker routs")
	check(b3.is_finished and b3.winner == "defender", "all attackers routed -> defender wins")


func test_result() -> void:
	var b := make_battle(make_map(12))
	var a := add(b, "attacker", "armor", Vector2i(5, 6), 1)
	var a2 := add(b, "attacker", "infantry", Vector2i(6, 6), 1)
	var d := add(b, "defender", "infantry", Vector2i(5, 5), 2)
	var d2 := add(b, "defender", "infantry", Vector2i(6, 5), 3)
	b.start()
	var r0 := b.result()
	check(not r0.finished and r0.winner == "", "result before the end: not finished")
	check_eq(r0.casualties.size(), 3, "casualties for every division")
	check_eq(float(r0.casualties[1]), 0.0, "no casualties yet")
	a2.hp = 5                      # attacker division 1: 25 HP -> 20
	d.hp = 1
	b.attack(a.id, d.id)           # division 2 wiped
	var r := b.result()
	check_eq(float(r.casualties[1]), 0.2, "division 1 lost 20% (5 of 25 HP)")
	check_eq(float(r.casualties[2]), 1.0, "division 2 lost 100%")
	check_eq(float(r.casualties[3]), 0.0, "division 3 untouched")
	check(Array(b.divisions().attacker) == [1] and Array(b.divisions().defender) == [2, 3], "divisions per side")
	check(not r.finished, "a defender remains")
	d2.hp = 1
	b.attack(a2.id, d2.id)
	var r2 := b.result()
	check(r2.finished and r2.attacker_won and r2.winner == "attacker", "result: attacker won")
	check_eq(r2.reason, "defender_eliminated", "result reason")
	check_eq(r2.turn, 1, "result turn")


func test_play_out() -> void:
	var gd: Node = autoload("GameData")
	for city in ["berlin", "london"]:
		var m := TacticalMap.generate(city, 20, gd.tactical.get("tiles", {}))
		var dep := TacticalDeployment.new(m)
		dep.attacker = "ussr"
		dep.defender = "germany"
		for i in 3:
			dep.add_division("attacker", "ussr", 10 + i, ["infantry", "armor", "artillery"], stats)
			dep.add_division("defender", "germany", 20 + i, ["infantry", "infantry", "artillery"], stats)
		dep.auto_deploy("attacker")
		dep.auto_deploy("defender")
		var b := TacticalBattle.new(dep, gd.tactical)
		b.start()
		var r: Dictionary = TacticalAI.play_out(b)
		check(r.finished, "%s: AI play-out finishes" % city)
		check(r.winner in ["attacker", "defender"], "%s: winner %s" % [city, r.winner])
		check(r.turn <= 20, "%s: within 20 turns (turn %d)" % [city, r.turn])
		check_eq(r.casualties.size(), 6, "%s: casualties for 6 divisions" % city)
		var any_loss := false
		for did in r.casualties:
			if float(r.casualties[did]) > 0.0:
				any_loss = true
		check(any_loss, "%s: the fight caused casualties" % city)
		print("  %s play-out: %s wins (%s) on turn %d, objectives %d" % [city, r.winner, r.reason, r.turn, r.objectives])
