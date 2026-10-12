extends "res://tests/test_base.gd"
## Step 16: tactical unit actions (TacticalBattle logic, no UI).

const NO_POS := Vector2i(-1, -1)
var stats: Dictionary = {}


func make_map(size: int, fill: String, overrides: Dictionary = {}) -> TacticalMap:
	var m := TacticalMap.new()
	m.city_id = "test"
	m.size = size
	var t := PackedStringArray()
	t.resize(size * size)
	t.fill(fill)
	m.tiles = t
	for p in overrides:
		m.tiles[p.y * size + p.x] = overrides[p]
	return m


func make_battle(m: TacticalMap) -> TacticalBattle:
	var dep := TacticalDeployment.new(m)
	dep.attacker = "germany"
	dep.defender = "ussr"
	return TacticalBattle.new(dep, {"damage_scale": 1.5})


func add(b: TacticalBattle, side: String, type: String, pos: Vector2i) -> TacticalUnit:
	var nation := "germany" if side == "attacker" else "ussr"
	var u: TacticalUnit = b.deployment.add_division(side, nation, 1 if side == "attacker" else 2, [type], stats)[0]
	u.pos = pos
	return u


func run_tests() -> void:
	var gd: Node = autoload("GameData")
	stats = gd.tactical.get("units", {})
	check_eq(float(gd.tactical.get("damage_scale", 0.0)), 1.5, "damage_scale in tactical.json")
	check_eq(stats.size(), 3, "3 tactical unit types")

	test_movement()
	test_terrain()
	test_attack()
	test_dig_in()
	test_overrun()
	test_barrage()
	test_overwatch()
	test_one_action()
	test_ai()
	await test_ui()


func free_adjacent(b: TacticalBattle, p: Vector2i, exclude: Array = []) -> Vector2i:
	for n in b.map.neighbors(p):
		if b.map.is_passable(n) and b.unit_at(n) == null and not exclude.has(n):
			return n
	return NO_POS


func click(view, t: Vector2i) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = view.grid.tile_center(t)
	view.grid._gui_input(ev)


func test_ui() -> void:
	var gs: Node = autoload("GameState")
	var bus: Node = autoload("EventBus")
	autoload("AI").enabled = false
	gs.new_game("germany")
	var game: Node = (load("res://scenes/game/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await process_frame
	gs.nation("germany").at_war_with.append("ussr")
	gs.nation("ussr").at_war_with.append("germany")
	var defenders: Array = gs.divisions_in("berlin").filter(func(d): return d.owner == "germany")
	gs.add_division("artillery", "germany", "berlin")
	var att1 = gs.add_division("armor", "ussr", "poland")
	var att2 = gs.add_division("infantry", "ussr", "poland")
	var cb: Node = autoload("Combat")
	for d in [att1, att2]:
		d.path.assign(["berlin"])
		d.move_progress = 1.0
		cb._on_hostile_entry(d, "berlin")
	bus.tactical_battle_requested.emit("berlin")
	await process_frame
	var view = game.tactical_view
	check(view != null, "tactical view open")
	if view == null:
		return
	check_eq(view.player_side, "defender", "player defends Berlin")
	for a in ["Move", "Attack", "Dig in", "Overrun", "Barrage", "Overwatch", "End phase"]:
		check(view.action_buttons.has(a), "action button " + a)
	check(view.action_buttons["End phase"].disabled, "actions disabled during deployment")
	check(view.start_button.visible, "Start battle button shown during deployment")
	view.start_button.pressed.emit()
	var b: TacticalBattle = view.battle
	check(b != null and view.phase == "battle", "Start battle creates the battle")
	check(view.is_player_phase(), "AI attacker played its phase, now the player's (defender) phase")
	check_eq(b.turn, 1, "still turn 1")
	check(b.events.any(func(e): return e.kind == "phase" and e.side == "attacker"), "attacker phase logged")
	check(not view.start_button.visible and not view.auto_deploy_button.visible, "deployment controls hidden")
	check(not view.action_buttons["End phase"].disabled, "End phase enabled")
	check(view.action_buttons["Move"].disabled, "Move disabled without a selection")
	check(view.log_label.text != "", "battle log shown")
	# Pick an infantry squad that can move.
	var inf: TacticalUnit = null
	for u in b.active_units("defender"):
		if u.type == "infantry" and not b.reachable(u.id).is_empty():
			inf = u
			break
	check(inf != null, "a player infantry squad can move")
	if inf == null:
		return
	click(view, inf.pos)
	check_eq(view.selected_unit, inf.id, "clicking a unit selects it")
	var green: Array = view.grid.valid_tiles()
	check(green.size() > 0 and green.size() == b.reachable(inf.id).size(), "reachable tiles highlighted")
	check(not view.action_buttons["Move"].disabled, "Move enabled")
	check(view.action_buttons["Overrun"].disabled and view.action_buttons["Overrun"].tooltip_text.contains("armor"), "Overrun only for armor")
	check(view.action_buttons["Barrage"].disabled, "Barrage only for artillery")
	var dest: Vector2i = green[0]
	var cost: int = b.reachable(inf.id)[dest]
	click(view, dest)
	check_eq(inf.pos, dest, "click on a green tile moves the unit")
	check_eq(inf.moves_left, 3 - cost, "movement points spent")
	check(view.unit_buttons[inf.id].text.contains("MP %d" % inf.moves_left), "unit list shows MP")
	# Attack: bring an enemy next to the squad.
	var enemy: TacticalUnit = b.active_units("attacker")[0]
	var adj := free_adjacent(b, inf.pos)
	enemy.pos = adj
	view.select_unit(inf.id)
	check(view.grid.target_tiles().has(adj), "attackable enemy highlighted red")
	check(not view.action_buttons["Attack"].disabled, "Attack enabled with an enemy in range")
	view.action_buttons["Attack"].pressed.emit()
	check_eq(view.action_mode, "attack", "Attack button sets attack mode")
	var hp0 := enemy.hp
	click(view, adj)
	check(enemy.hp < hp0 or enemy.destroyed, "clicking the enemy attacks it")
	check(inf.acted, "action used")
	check(view.action_buttons["Attack"].disabled and view.action_buttons["Dig in"].disabled and view.action_buttons["Overwatch"].disabled,
		"no second action this turn")
	# Dig in on another infantry squad.
	var inf2: TacticalUnit = null
	for u in b.active_units("defender"):
		if u.type == "infantry" and u != inf:
			inf2 = u
			break
	if inf2 != null:
		view.select_unit(inf2.id)
		check(not view.action_buttons["Dig in"].disabled, "Dig in enabled for infantry")
		view.action_buttons["Dig in"].pressed.emit()
		check(inf2.dug_in and inf2.acted, "Dig in button digs in")
	# Barrage with the artillery.
	var art: TacticalUnit = null
	for u in b.active_units("defender"):
		if u.type == "artillery":
			art = u
			break
	check(art != null, "player artillery present")
	if art != null:
		var foe2: TacticalUnit = null
		for u in b.active_units("attacker"):
			if u != enemy:
				foe2 = u
				break
		var spot := NO_POS
		for y in b.map.size:
			for x in b.map.size:
				var p := Vector2i(x, y)
				if spot == NO_POS and p != art.pos and TacticalBattle.distance(p, art.pos) <= 3 and b.map.is_passable(p) and b.unit_at(p) == null:
					spot = p
		foe2.pos = spot
		view.select_unit(art.id)
		check(not view.action_buttons["Barrage"].disabled, "Barrage enabled for artillery")
		view.action_buttons["Barrage"].pressed.emit()
		check(view.grid.target_tiles().has(spot), "barrage tiles highlighted")
		var hp1 := foe2.hp
		click(view, spot)
		check(foe2.hp < hp1 or foe2.destroyed, "barrage click damages the enemy")
		check(art.acted, "barrage used the action")
	# Overwatch on any unit that has not acted.
	var idle: TacticalUnit = null
	for u in b.active_units("defender"):
		if not u.acted:
			idle = u
			break
	if idle != null:
		view.select_unit(idle.id)
		view.action_buttons["Overwatch"].pressed.emit()
		check(idle.overwatch, "Overwatch button sets overwatch")
	# End phase: AI attacker plays, then the player again.
	view.action_buttons["End phase"].pressed.emit()
	check_eq(b.turn, 2, "End phase -> enemy phase -> turn 2")
	check(view.is_player_phase(), "control returns to the player")
	check_eq(view.turn_label.text, "Turn 2 / 20", "turn counter updated")
	check(b.active_units("defender").all(func(u): return not u.acted and u.moves_left == u.movement), "player units refreshed")
	# Overrun as attacker with armor.
	var tank_div = gs.add_division("armor", "germany", "berlin")
	var foe_div = gs.add_division("infantry", "ussr", "poland")
	view.open_with("berlin", "germany", "ussr", [tank_div], [foe_div])
	check_eq(view.player_side, "attacker", "player attacks")
	view.start_battle()
	var b2: TacticalBattle = view.battle
	check(view.is_player_phase(), "attacker moves first")
	var tank: TacticalUnit = null
	for u in b2.active_units("attacker"):
		if u.type == "armor" and b2.reachable(u.id).size() > 3:
			tank = u
			break
	check(tank != null, "armor platoon present")
	if tank != null:
		var foe: TacticalUnit = b2.active_units("defender")[0]
		# Put the enemy 3 tiles away along a reachable tile.
		var target_tile := NO_POS
		var reach := b2.reachable(tank.id)
		for p in reach:
			if reach[p] >= 2 and TacticalBattle.distance(p, tank.pos) >= 2:
				var n := free_adjacent(b2, p, [tank.pos])
				if n != NO_POS and TacticalBattle.distance(n, tank.pos) > 1:
					target_tile = n
					break
		foe.pos = target_tile
		view.select_unit(tank.id)
		check(not view.action_buttons["Overrun"].disabled, "Overrun enabled for armor")
		view.action_buttons["Overrun"].pressed.emit()
		check(view.grid.target_tiles().has(target_tile), "overrun target highlighted")
		var hp2 := foe.hp
		var start := tank.pos
		click(view, target_tile)
		check(tank.pos != start and TacticalBattle.distance(tank.pos, target_tile) == 1, "overrun moved the armor next to the enemy")
		check(foe.hp < hp2 or foe.destroyed, "and attacked it")
		check(tank.acted, "one action")
	view.close()
	await process_frame
	check(game.tactical_view == null, "view closes")
	game.queue_free()
	await process_frame


func test_movement() -> void:
	var b := make_battle(make_map(10, "street"))
	var inf := add(b, "attacker", "infantry", Vector2i(0, 5))
	var enemy := add(b, "defender", "infantry", Vector2i(9, 9))
	check(not b.can_move(inf.id, Vector2i(1, 5)), "no moves before the battle starts")
	b.start()
	check_eq(b.turn, 1, "turn 1")
	check_eq(b.active_side, "attacker", "attacker phase first")
	check_eq(inf.moves_left, 3, "infantry has 3 movement points")
	var reach := b.reachable(inf.id)
	check(reach.has(Vector2i(3, 5)) and not reach.has(Vector2i(4, 5)), "street: 3 tiles within 3 MP, not 4")
	check(reach.has(Vector2i(1, 7)) and not reach.has(Vector2i(2, 7)), "Manhattan budget (no diagonals)")
	check(not b.can_move(enemy.id, Vector2i(9, 8)), "defender cannot move in the attacker phase")
	check(b.move_error(enemy.id, Vector2i(9, 8)) != "", "refusal reason for wrong phase")
	check(b.move_unit(inf.id, Vector2i(2, 5)), "move 2 tiles")
	check_eq(inf.pos, Vector2i(2, 5), "unit moved")
	check_eq(inf.moves_left, 1, "2 MP spent")
	check_eq(inf.facing, Vector2i(1, 0), "facing = direction of the last step")
	check(not b.can_move(inf.id, Vector2i(4, 5)), "cannot spend more than the remaining MP")
	check(b.move_unit(inf.id, Vector2i(2, 4)), "remaining MP can still be used")
	check_eq(inf.facing, Vector2i(0, -1), "facing follows the move")
	check_eq(inf.moves_left, 0, "all MP spent")
	check(b.reachable(inf.id).is_empty(), "nothing reachable without MP")
	check(b.events.any(func(e): return e.kind == "move"), "move logged")
	# Blocking: enemies block, own units can be passed but not occupied.
	var b2 := make_battle(make_map(10, "river", {Vector2i(0, 5): "street", Vector2i(1, 5): "street",
		Vector2i(2, 5): "street", Vector2i(3, 5): "street"}))
	var a := add(b2, "attacker", "infantry", Vector2i(0, 5))
	var friend := add(b2, "attacker", "artillery", Vector2i(1, 5))
	b2.start()
	check(b2.reachable(a.id).has(Vector2i(2, 5)), "can pass through an own unit")
	check(not b2.can_move(a.id, friend.pos), "cannot end on an own unit")
	friend.pos = Vector2i(9, 0)
	var foe := add(b2, "defender", "infantry", Vector2i(1, 5))
	check(not b2.reachable(a.id).has(Vector2i(2, 5)), "enemy units block movement")
	check(not b2.can_move(a.id, foe.pos), "cannot move onto an enemy")


func test_terrain() -> void:
	# Corridor along row 5, everything else river.
	var corridor := {Vector2i(0, 5): "street", Vector2i(1, 5): "rubble", Vector2i(2, 5): "street",
		Vector2i(3, 5): "street", Vector2i(4, 5): "street"}
	var b := make_battle(make_map(10, "river", corridor))
	var inf := add(b, "attacker", "infantry", Vector2i(0, 5))
	b.start()
	var reach := b.reachable(inf.id)
	check_eq(int(reach.get(Vector2i(1, 5), -1)), 2, "rubble costs 2 MP")
	check_eq(int(reach.get(Vector2i(2, 5), -1)), 3, "tile behind rubble costs 3")
	check(not reach.has(Vector2i(3, 5)), "rubble slows: 3rd tile out of reach")
	check(not reach.has(Vector2i(0, 4)), "river impassable")
	check(b.move_error(inf.id, Vector2i(0, 4)).contains("impassable"), "river refusal reason")
	# River column x=5 with a bridge at (5,2).
	var b2 := make_battle(make_map(10, "street", {Vector2i(5, 0): "river", Vector2i(5, 1): "river",
		Vector2i(5, 2): "bridge", Vector2i(5, 3): "river", Vector2i(5, 4): "river", Vector2i(5, 5): "river",
		Vector2i(5, 6): "river", Vector2i(5, 7): "river", Vector2i(5, 8): "river", Vector2i(5, 9): "river"}))
	var near := add(b2, "attacker", "infantry", Vector2i(4, 2))
	var far := add(b2, "attacker", "infantry", Vector2i(4, 7))
	var tank := add(b2, "attacker", "armor", Vector2i(4, 4))
	b2.start()
	check(b2.reachable(near.id).has(Vector2i(6, 2)), "bridge crossing reachable")
	check(not b2.reachable(far.id).has(Vector2i(6, 7)), "no crossing without a bridge")
	var tr := b2.reachable(tank.id)
	check_eq(int(tr.get(Vector2i(6, 2), -1)), 4, "armor (4 MP) crosses via the bridge")
	check(not tr.has(Vector2i(6, 4)), "straight across the river is impossible")
	var path := b2.path_to(tank.id, Vector2i(6, 2))
	check(path.has(Vector2i(5, 2)), "path uses the bridge")
	check(b2.move_unit(tank.id, Vector2i(6, 2)) and tank.pos == Vector2i(6, 2), "armor crossed")


func test_attack() -> void:
	var b := make_battle(make_map(10, "street", {Vector2i(5, 1): "building"}))
	var inf := add(b, "attacker", "infantry", Vector2i(2, 2))
	var art := add(b, "attacker", "artillery", Vector2i(0, 5))
	var tank := add(b, "attacker", "armor", Vector2i(8, 8))
	var e1 := add(b, "defender", "infantry", Vector2i(3, 2))
	var e2 := add(b, "defender", "infantry", Vector2i(3, 5))
	var e3 := add(b, "defender", "infantry", Vector2i(5, 1))
	var e4 := add(b, "defender", "infantry", Vector2i(8, 9))
	b.start()
	# Damage formula: 1.5 x A^2 / (A + D).
	check_eq(b.damage(inf, e1), 3, "infantry vs infantry on street = 3")
	check_eq(b.damage(tank, e4), 6, "armor vs infantry = 6")
	check_eq(b.damage(art, e2), 5, "artillery vs infantry = 5")
	check_eq(b.effective_defense(e3), 6.5, "building +30% defense")
	check_eq(b.damage(inf, e3), 2, "building cover reduces damage")
	check(b.attack_targets(inf.id).has(e1) and not b.attack_targets(inf.id).has(e2), "range 1 targets")
	check(b.attack_error(inf.id, e2.id).contains("range"), "out of range refused")
	check(not b.can_attack(inf.id, tank.id), "cannot attack own unit")
	check_eq(b.attack(inf.id, e1.id), 3, "attack deals 3")
	check_eq(e1.hp, 7, "target HP 10 -> 7")
	check(inf.acted and inf.moves_left == 0, "attack uses the action and ends movement")
	check_eq(b.attack(inf.id, e1.id), -1, "second attack refused")
	check(b.can_attack(art.id, e2.id), "artillery attacks at range 3")
	var e5 := add(b, "defender", "infantry", Vector2i(4, 5))
	check(not b.can_attack(art.id, e5.id), "artillery cannot reach range 4")
	# Weakened attacker hits softer.
	tank.hp = 5
	check(b.damage(tank, e4) < 6, "damaged attacker deals less damage")
	# Destruction.
	e4.hp = 2
	tank.hp = tank.max_hp
	b.attack(tank.id, e4.id)
	check(e4.destroyed and e4.hp == 0 and e4.pos == NO_POS, "0 HP -> destroyed and off the map")
	check(b.unit_at(Vector2i(8, 9)) == null, "tile freed")
	check(not b.active_units("defender").has(e4), "destroyed unit inactive")
	check(not b.deployment.reserve("defender").has(e4), "destroyed unit not in reserve")
	check(b.events.any(func(e): return e.kind == "destroyed" and e.unit == e4.id), "destruction logged")
	# Phase rule for actions.
	check(not b.can_attack(e1.id, inf.id), "defender cannot attack in the attacker phase")


func test_dig_in() -> void:
	var b := make_battle(make_map(10, "street"))
	var atk := add(b, "attacker", "infantry", Vector2i(4, 6))
	var dfn := add(b, "defender", "infantry", Vector2i(4, 5))
	var tank := add(b, "defender", "armor", Vector2i(0, 0))
	b.start()
	check(not b.dig_in(dfn.id), "cannot dig in during the enemy phase")
	b.end_phase()
	check_eq(b.active_side, "defender", "defender phase")
	check(not b.dig_in(tank.id), "armor cannot dig in")
	check_eq(b.ability_error(dfn.id), "", "infantry may dig in")
	check(b.use_ability(dfn.id), "dig in via use_ability")
	check(dfn.dug_in and dfn.acted, "dug in, action used")
	check_eq(dfn.base_defense(), 7, "dig in: defense 5 -> 7")
	check_eq(b.effective_defense(dfn), 7.0, "effective defense +2")
	b.end_phase()
	check_eq(b.turn, 2, "turn 2 after the defender phase")
	check_eq(b.damage(atk, dfn), 2, "dug-in infantry takes 2 instead of 3")
	check(dfn.dug_in, "dig in lasts through the enemy phase")
	b.end_phase()
	check(dfn.dug_in, "dig in kept while not moving")
	check(b.move_unit(dfn.id, Vector2i(5, 5)), "dug-in unit moves")
	check(not dfn.dug_in and dfn.base_defense() == 5, "moving ends dig in")


func test_overrun() -> void:
	var b := make_battle(make_map(12, "street"))
	var tank := add(b, "attacker", "armor", Vector2i(0, 0))
	var inf := add(b, "attacker", "infantry", Vector2i(0, 11))
	var near := add(b, "defender", "infantry", Vector2i(3, 0))
	var far := add(b, "defender", "infantry", Vector2i(11, 11))
	b.start()
	check(not b.use_ability(inf.id, near.pos) or inf.dug_in, "infantry ability is dig in, not overrun")
	check(b.overrun_targets(tank.id).has(near) and not b.overrun_targets(tank.id).has(far), "overrun targets within reach")
	check(b.ability_error(tank.id, far.pos) != "", "far enemy refused")
	check_eq(b.overrun_tile(tank.id, near.id), Vector2i(2, 0), "attack tile = cheapest tile in range")
	var expected := b.damage(tank, near)
	check(b.use_ability(tank.id, near.pos), "overrun")
	check_eq(tank.pos, Vector2i(2, 0), "armor moved next to the target")
	check_eq(near.hp, 10 - expected, "and attacked in the same action")
	check(tank.acted, "overrun uses the action")
	check_eq(tank.moves_left, 2, "leftover movement is kept")
	check(b.events.any(func(e): return e.kind == "overrun"), "overrun logged")
	check(b.move_unit(tank.id, Vector2i(2, 2)), "armor can still move after overrunning")
	check_eq(b.attack(tank.id, near.id), -1, "no second action after overrun")
	check(not b.overrun(tank.id, near.id), "no second overrun")


func test_barrage() -> void:
	var b := make_battle(make_map(10, "street"))
	var art := add(b, "attacker", "artillery", Vector2i(0, 5))
	var own := add(b, "attacker", "infantry", Vector2i(2, 5))
	var center := add(b, "defender", "infantry", Vector2i(3, 5))
	var north := add(b, "defender", "infantry", Vector2i(3, 4))
	var east := add(b, "defender", "armor", Vector2i(4, 5))
	var diag := add(b, "defender", "infantry", Vector2i(4, 4))
	b.start()
	check(b.ability_error(art.id, Vector2i(4, 5)) != "", "barrage beyond range 3 refused")
	check(b.ability_error(art.id, art.pos) != "", "cannot barrage own tile")
	check(b.barrage_tiles(art.id).has(Vector2i(3, 5)), "target tile in barrage range")
	var full := b.damage(art, center)
	var half_n := maxi(1, int(round(b.damage(art, north) * 0.5)))
	var half_e := maxi(1, int(round(b.damage(art, east) * 0.5)))
	check(half_n < full, "splash smaller than full damage")
	check(b.use_ability(art.id, Vector2i(3, 5)), "barrage")
	check_eq(center.hp, 10 - full, "target tile takes full damage")
	check_eq(north.hp, 10 - half_n, "adjacent tile takes half damage")
	check_eq(east.hp, 15 - half_e, "adjacent armor takes half damage")
	check_eq(diag.hp, 10, "diagonal tile not hit")
	check_eq(own.hp, 10, "own units are not hit")
	check(art.acted and art.moves_left == 0, "barrage uses the action and ends movement")
	check(not b.barrage(art.id, Vector2i(3, 5)), "one barrage per turn")
	var ev: Array = b.events.filter(func(e): return e.kind == "barrage")
	check(ev.size() == 1 and ev[0].hits.size() == 3, "barrage logged with 3 hits")


func test_overwatch() -> void:
	var b := make_battle(make_map(12, "street"))
	var mover := add(b, "attacker", "infantry", Vector2i(5, 9))
	var mover2 := add(b, "attacker", "infantry", Vector2i(6, 8))
	var watcher := add(b, "defender", "infantry", Vector2i(5, 5))
	var gun := add(b, "defender", "artillery", Vector2i(0, 0))
	b.start()
	b.end_phase()
	check(b.set_overwatch(watcher.id), "defender goes on overwatch")
	check(watcher.overwatch and watcher.acted and watcher.moves_left == 0, "overwatch uses the action")
	b.end_phase()
	check(watcher.overwatch, "overwatch active during the enemy phase")
	var expected := b.damage(watcher, mover)
	b.move_unit(mover.id, Vector2i(5, 8))
	check_eq(mover.hp, 10, "no fire while the enemy is out of range")
	b.move_unit(mover.id, Vector2i(5, 6))
	check_eq(mover.hp, 10 - expected, "fires when the enemy moves within range")
	check(not watcher.overwatch, "overwatch spent after firing")
	check(b.events.any(func(e): return e.kind == "overwatch_fire" and e.unit == watcher.id and e.target == mover.id), "overwatch fire logged")
	check(b.move_unit(mover2.id, Vector2i(6, 5)), "second enemy moves next to the watcher")
	check_eq(mover2.hp, 10, "only the first enemy is fired upon")
	check(not gun.overwatch, "units not on overwatch never fire")
	# Overwatch fires mid-path, at the first tile within range, and can destroy the mover.
	var b2 := make_battle(make_map(12, "street"))
	var runner := add(b2, "attacker", "infantry", Vector2i(2, 4))
	var w2 := add(b2, "defender", "artillery", Vector2i(2, 0))
	b2.start()
	b2.end_phase()
	b2.set_overwatch(w2.id)
	b2.end_phase()
	runner.hp = 1
	check(b2.move_unit(runner.id, Vector2i(2, 1)), "move into a watched area")
	check(runner.destroyed, "overwatch fire at range 3 destroyed the mover")
	check(b2.unit_at(Vector2i(2, 3)) == null and b2.unit_at(Vector2i(2, 1)) == null, "destroyed mover left the map mid-path")
	# Overwatch expires at the start of the watcher's own phase.
	var b3 := make_battle(make_map(12, "street"))
	add(b3, "attacker", "infantry", Vector2i(0, 11))
	var w3 := add(b3, "defender", "infantry", Vector2i(5, 5))
	b3.start()
	b3.end_phase()
	b3.set_overwatch(w3.id)
	b3.end_phase()
	b3.end_phase()
	check(not w3.overwatch, "unused overwatch expires in the watcher's next phase")


func test_one_action() -> void:
	var b := make_battle(make_map(10, "street"))
	var inf := add(b, "attacker", "infantry", Vector2i(4, 5))
	var art := add(b, "attacker", "artillery", Vector2i(0, 0))
	var foe := add(b, "defender", "infantry", Vector2i(4, 4))
	b.start()
	check(b.attack(inf.id, foe.id) > 0, "attack")
	check(not b.dig_in(inf.id), "no dig in after attacking")
	check(not b.set_overwatch(inf.id), "no overwatch after attacking")
	check(b.overwatch_error(inf.id).contains("acted"), "reason: already acted")
	check(b.set_overwatch(art.id), "other units still have their action")
	check(not b.barrage(art.id, Vector2i(1, 1)), "overwatch used the action")
	b.end_phase()
	check(not b.attack(inf.id, foe.id) > 0, "attacker cannot act in the defender phase")
	b.end_phase()
	check(not inf.acted and inf.moves_left == 3, "fresh action and movement next turn")
	check(not art.overwatch and not art.acted, "overwatch flag reset in own phase")
	check(b.dig_in(inf.id), "can act again next turn")
	check(b.move_unit(inf.id, Vector2i(5, 5)), "movement is separate from the action")
	check(not b.dig_in(inf.id), "still only one action")


func test_ai() -> void:
	var m := TacticalMap.generate("berlin", 20, autoload("GameData").tactical.get("tiles", {}))
	var dep := TacticalDeployment.new(m)
	dep.attacker = "ussr"
	dep.defender = "germany"
	for i in 3:
		dep.add_division("attacker", "ussr", 10 + i, ["armor", "armor", "infantry"], stats)
		dep.add_division("defender", "germany", 20 + i, ["infantry", "infantry", "artillery"], stats)
	dep.auto_deploy("attacker")
	dep.auto_deploy("defender")
	var b := TacticalBattle.new(dep, {"damage_scale": 1.5})
	b.start()
	var start_pos := {}
	for u in dep.units:
		start_pos[u.id] = u.pos
	for i in 16:
		TacticalAI.run_phase(b, b.active_side)
		b.end_phase()
	check_eq(b.turn, 9, "8 full turns played")
	var moved := dep.units_of("attacker").filter(func(u): return u.destroyed or u.pos != start_pos[u.id])
	check(moved.size() > 0, "AI attackers advance")
	check(b.events.any(func(e): return e.kind in ["attack", "overrun", "barrage", "overwatch_fire"]), "AI fights")
	var occupied := {}
	var ok := true
	for u in dep.units:
		if u.is_active():
			if occupied.has(u.pos) or not m.is_passable(u.pos):
				ok = false
			occupied[u.pos] = true
	check(ok, "no stacked units or units on impassable tiles")
	var any_loss := false
	for i in 3:
		if b.casualty_fraction(10 + i) > 0.0 or b.casualty_fraction(20 + i) > 0.0:
			any_loss = true
	check(any_loss, "casualty_fraction reflects losses")
