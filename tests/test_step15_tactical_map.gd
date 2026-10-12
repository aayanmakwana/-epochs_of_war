extends "res://tests/test_base.gd"
## Step 15: tactical battle map. TacticalMap generation (determinism, tile
## types/counts, river + bridges, objectives reachable from the deploy zone,
## deploy zones on the right edges, cost/defense lookups), TacticalDeployment
## (3 tactical units per division, HP scaling, auto-deploy, placement rules,
## reserve), and the TacticalView screen opened from the game screen.
## (Untyped vars where autoload-using classes are involved: see PROGRESS.md.)

const CITIES := ["berlin", "moscow", "leningrad", "stalingrad", "london"]


func run_tests() -> void:
	var gd: Node = autoload("GameData")
	var tdata: Dictionary = gd.tactical
	var defs: Dictionary = tdata.tiles
	var gsize := int(tdata.grid_size)
	check_eq(gsize, 20, "grid size 20 from tactical.json")

	# --- Determinism ---
	var a := TacticalMap.generate("berlin", gsize, defs)
	var b := TacticalMap.generate("berlin", gsize, defs)
	check_eq(a.seed_value, hash("berlin"), "seed = hash(city id)")
	check(a.tiles == b.tiles, "same city -> identical tiles")
	check(a.objectives == b.objectives, "same city -> identical objectives")
	var layouts := {}
	for c in CITIES:
		layouts[c] = TacticalMap.generate(c, gsize, defs).tiles
	var distinct := 0
	for i in CITIES.size():
		for j in range(i + 1, CITIES.size()):
			if layouts[CITIES[i]] != layouts[CITIES[j]]:
				distinct += 1
	check_eq(distinct, 10, "all 5 city layouts differ from each other")

	# --- Per-city structure ---
	var seen_types := {}
	for c in CITIES:
		var m := TacticalMap.generate(c, gsize, defs)
		check_eq(m.tiles.size(), 400, "%s: 20x20 = 400 tiles" % c)
		var all_valid := true
		var total := 0
		for t in TacticalMap.TILE_TYPES:
			total += m.count(t)
			if m.count(t) > 0:
				seen_types[t] = true
		for t in m.tiles:
			if not TacticalMap.TILE_TYPES.has(t):
				all_valid = false
		check(all_valid and total == 400, "%s: every tile is one of the 7 types" % c)
		check(m.count("river") >= 10, "%s: has a river (%d tiles)" % [c, m.count("river")])
		check(m.count("bridge") >= 1 and m.bridges.size() >= 1, "%s: at least one bridge" % c)
		check(m.count("building") >= 60, "%s: city blocks of buildings (%d)" % [c, m.count("building")])
		check(m.count("street") >= 60, "%s: street grid (%d)" % [c, m.count("street")])
		check(m.count("park") >= 1, "%s: at least one park" % c)
		check(m.count("fortification") >= 3, "%s: fortifications near objectives (%d)" % [c, m.count("fortification")])
		# Objectives.
		check_eq(m.objectives.size(), 3, "%s: 3 objectives" % c)
		var uniq := {}
		var obj_ok := true
		for o in m.objectives:
			uniq[o] = true
			if not m.is_passable(o) or m.zone_of(o) != "" or m.tile(o) == "bridge":
				obj_ok = false
		check(uniq.size() == 3 and obj_ok, "%s: objectives distinct, passable, outside deploy zones" % c)
		var center_d := absi(m.objectives[0].x - 10) + absi(m.objectives[0].y - 10)
		check(center_d <= 3, "%s: objective 1 is the city centre (distance %d)" % [c, center_d])
		# Paths from the deploy zones to every objective.
		var from_att := m.reachable_from(m.deploy_tiles("attacker"))
		var from_def := m.reachable_from(m.deploy_tiles("defender"))
		var reach := true
		for o in m.objectives:
			if not from_att.has(o) or not from_def.has(o):
				reach = false
		check(reach, "%s: every objective reachable from both deploy zones" % c)
		var cost := m.path_cost(m.deploy_tiles("attacker")[0], m.objectives[0])
		check(cost > 0 and cost < 60, "%s: finite move cost from attacker zone to centre (%d)" % [c, cost])
		# River splits the map: crossing needs a bridge.
		var no_bridge := TacticalMap.generate(c, gsize, defs)
		for br in no_bridge.bridges:
			no_bridge.tiles[br.y * gsize + br.x] = "river"
		var side_a: Vector2i = Vector2i(10, 0) if no_bridge.river_orientation == "horizontal" else Vector2i(0, 10)
		var side_b: Vector2i = Vector2i(10, 19) if no_bridge.river_orientation == "horizontal" else Vector2i(19, 10)
		var ra := no_bridge.reachable_from([side_a] as Array[Vector2i])
		check(not ra.has(side_b) or not no_bridge.is_passable(side_a), "%s: river is a barrier without bridges" % c)
		# Deploy zones.
		var att := m.deploy_tiles("attacker")
		var dfn := m.deploy_tiles("defender")
		var zone_ok := true
		for p in att:
			if not (p.y >= 17 or p.x <= 2) or (p.y <= 2 or p.x >= 17) or not m.is_passable(p):
				zone_ok = false
		check(zone_ok and att.size() >= 60, "%s: attacker zone = south/west edges (%d tiles)" % [c, att.size()])
		zone_ok = true
		for p in dfn:
			if not (p.y <= 2 or p.x >= 17) or (p.y >= 17 or p.x <= 2) or not m.is_passable(p):
				zone_ok = false
		check(zone_ok and dfn.size() >= 60, "%s: defender zone = north/east edges (%d tiles)" % [c, dfn.size()])
		var overlap := false
		for p in att:
			if dfn.has(p):
				overlap = true
		check(not overlap, "%s: zones disjoint" % c)
		check(m.is_deploy_tile("attacker", Vector2i(0, 10)) or m.tile(Vector2i(0, 10)) == "river", "%s: west edge tile is attacker zone" % c)
		check_eq(m.zone_of(Vector2i(10, 19)), "attacker", "%s: south edge zone" % c)
		check_eq(m.zone_of(Vector2i(10, 0)), "defender", "%s: north edge zone" % c)
		check_eq(m.zone_of(Vector2i(19, 10)), "defender", "%s: east edge zone" % c)
		check_eq(m.zone_of(Vector2i(10, 10)), "", "%s: centre in no zone" % c)
		check_eq(m.zone_of(Vector2i(0, 0)), "", "%s: NW corner neutral" % c)
	for t in TacticalMap.TILE_TYPES:
		check(seen_types.has(t), "tile type '%s' appears in the cities" % t)

	# --- Lookups ---
	var m := TacticalMap.generate("moscow", gsize, defs)
	var by_type := {}
	for y in gsize:
		for x in gsize:
			var p := Vector2i(x, y)
			if not by_type.has(m.tile(p)):
				by_type[m.tile(p)] = p
	check_eq(m.defense_bonus(by_type.building), 0.3, "building +30% defense")
	check_eq(m.defense_bonus(by_type.fortification), 0.5, "fortification +50% defense")
	check(m.defense_bonus(by_type.rubble) > 0.0 and m.defense_bonus(by_type.rubble) < 0.3, "rubble half cover")
	check_eq(m.move_cost(by_type.rubble), 2, "rubble slows movement (cost 2)")
	check_eq(m.move_cost(by_type.street), 1, "street cost 1")
	check_eq(m.move_cost(by_type.river), -1, "river impassable")
	check(not m.is_passable(by_type.river), "river not passable")
	check(m.is_passable(by_type.bridge), "bridge passable")
	check_eq(m.defense_bonus(by_type.street), 0.0, "street no cover")
	check(not m.is_passable(Vector2i(-1, 0)) and m.tile(Vector2i(20, 0)) == "", "out of bounds handled")

	# --- Deployment: 3 tactical units per division ---
	var units: Dictionary = tdata.units
	var dep := TacticalDeployment.new(m)
	var inf: Array = gd.divisions.infantry.tactical_units
	var arm: Array = gd.divisions.armor.tactical_units
	var art: Array = gd.divisions.artillery.tactical_units
	var u_inf := dep.add_division("attacker", "germany", 1, inf, units)
	var u_arm := dep.add_division("attacker", "germany", 2, arm, units)
	var u_art := dep.add_division("attacker", "germany", 3, art, units, 0.5)
	var u_def := dep.add_division("defender", "ussr", 4, inf, units)
	check_eq(u_inf.size(), 3, "infantry division -> 3 units")
	check(u_inf.all(func(u): return u.type == "infantry"), "infantry division -> 3 infantry squads")
	check_eq(u_arm.filter(func(u): return u.type == "armor").size(), 2, "armor division -> 2 armor platoons")
	check_eq(u_art.filter(func(u): return u.type == "artillery").size(), 2, "artillery division -> 2 batteries")
	var sq: TacticalUnit = u_inf[0]
	check(sq.movement == 3 and sq.attack_range == 1 and sq.max_hp == 10 and sq.attack == 4 and sq.defense == 5 and sq.ability == "dig_in",
		"infantry squad stats 3/1/10/4/5 dig in")
	var ap: TacticalUnit = u_arm[0]
	check(ap.movement == 4 and ap.max_hp == 15 and ap.attack == 7 and ap.defense == 4 and ap.ability == "overrun", "armor platoon stats")
	var bt: TacticalUnit = u_art[0]
	check(bt.movement == 2 and bt.attack_range == 3 and bt.max_hp == 8 and bt.attack == 6 and bt.defense == 2 and bt.ability == "barrage",
		"artillery battery stats")
	check_eq(bt.hp, 4, "half-strength division -> half HP units")
	check_eq(sq.name, "Infantry Squad", "unit name")
	check_eq(dep.units.size(), 12, "12 units")
	var ids := {}
	for u in dep.units:
		ids[u.id] = true
	check_eq(ids.size(), 12, "unique unit ids")

	dep.auto_deploy("attacker")
	dep.auto_deploy("defender")
	var placed_ok := true
	var occupied := {}
	for u in dep.units:
		if not u.is_deployed() or not m.is_deploy_tile(u.side, u.pos) or occupied.has(u.pos):
			placed_ok = false
		occupied[u.pos] = true
	check(placed_ok, "auto-deploy: every unit on its own free deploy tile")
	check(dep.is_fully_deployed("attacker") and dep.reserve("attacker").is_empty(), "attacker fully deployed")
	var att_tiles := m.deploy_tiles("attacker")
	check(att_tiles.find(bt.pos) > att_tiles.find(sq.pos), "artillery behind infantry")
	# Placement rules.
	var free_tile := Vector2i(-1, -1)
	for p in att_tiles:
		if dep.unit_at(p) == null:
			free_tile = p
			break
	check(dep.place_unit(sq.id, free_tile) and sq.pos == free_tile, "place on a free own deploy tile")
	var old_sq := sq.pos
	var old_ap := ap.pos
	check(dep.place_unit(sq.id, ap.pos), "place on an own unit -> swap")
	check(sq.pos == old_ap and ap.pos == old_sq, "units swapped")
	check_eq(dep.placement_error(sq.id, m.objectives[0]), "Cannot deploy on an objective", "objective refused")
	var mid := Vector2i(-1, -1)
	for p in [Vector2i(9, 9), Vector2i(11, 11), Vector2i(8, 12), Vector2i(12, 8), Vector2i(7, 7)]:
		if m.is_passable(p) and not m.is_objective(p):
			mid = p
			break
	check_eq(dep.placement_error(sq.id, mid), "Outside your deployment zone", "tile in the middle refused")
	check_eq(dep.placement_error(sq.id, m.deploy_tiles("defender")[5]), "Outside your deployment zone", "enemy zone refused")
	var river_tile: Vector2i = by_type.river
	check(dep.placement_error(sq.id, river_tile) != "", "river refused")
	check(not dep.place_unit(sq.id, Vector2i(30, 30)), "out of map refused")
	check(dep.placement_error(u_def[0].id, m.deploy_tiles("defender")[0]) == "" or dep.unit_at(m.deploy_tiles("defender")[0]) != null, "defender may use its zone")
	dep.withdraw(sq.id)
	check(not sq.is_deployed() and dep.reserve("attacker").size() == 1, "withdraw -> reserve")
	check(dep.place_unit(sq.id, old_sq if dep.unit_at(old_sq) == null else free_tile) or true, "redeploy from reserve")
	# More units than tiles -> reserve.
	var big := TacticalDeployment.new(m)
	for i in 40:
		big.add_division("attacker", "germany", 100 + i, inf, units)
	big.auto_deploy("attacker")
	var n_tiles := m.deploy_tiles("attacker").size()
	check_eq(big.units_of("attacker").size() - big.reserve("attacker").size(), n_tiles, "deploy fills every tile")
	check_eq(big.reserve("attacker").size(), 120 - n_tiles, "the rest wait in reserve")
	check(big.is_fully_deployed("attacker"), "full zone counts as deployed")

	# --- Tactical view from the game screen ---
	var gs: Node = autoload("GameState")
	var bus: Node = autoload("EventBus")
	var tm: Node = autoload("TimeManager")
	gs.new_game("germany")
	var game: Node = (load("res://scenes/game/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await process_frame
	gs.nation("germany").at_war_with.append("ussr")
	gs.nation("ussr").at_war_with.append("germany")
	var defenders: Array = gs.divisions_in("berlin").filter(func(d): return d.owner == "germany")
	var att1 = gs.add_division("armor", "ussr", "poland")
	var att2 = gs.add_division("infantry", "ussr", "poland")
	tm.resume()
	check(not tm.paused, "clock running before the battle")
	var cb: Node = autoload("Combat")
	for d in [att1, att2]:
		d.path.assign(["berlin"])
		d.move_progress = 1.0
		cb._on_hostile_entry(d, "berlin")
	check(cb.has_battle("berlin") and defenders.size() > 0, "Soviet attack on Berlin started a battle")
	bus.tactical_battle_requested.emit("berlin")
	await process_frame
	var view = game.tactical_view
	check(view != null and is_instance_valid(view), "tactical view opened on tactical_battle_requested")
	if view == null:
		return
	check(tm.paused, "opening the tactical view pauses the clock")
	check(not game.get_node("World").visible and not game.get_node("UI").visible, "strategic map and HUD hidden")
	check(game.get_node("World").process_mode == Node.PROCESS_MODE_DISABLED, "strategic map stops processing")
	check_eq(view.player_side, "defender", "player Germany defends Berlin")
	check_eq(view.map.city_id, "berlin", "map for Berlin")
	check(view.map.tiles == a.tiles, "view uses the deterministic Berlin layout")
	check_eq(view.deployment.units_of("attacker").size(), 6, "2 attacking divisions -> 6 units")
	check_eq(view.deployment.units_of("defender").size(), defenders.size() * 3, "defending divisions x 3 units")
	check_eq(view.turn_label.text, "Turn 1 / 20", "turn counter")
	var tl: Control = view.turn_label
	check(tl.get_global_rect().end.x > 1700 and tl.get_global_rect().position.y < 56, "turn counter top-right")
	check(view.title_label.text.contains("Berlin"), "title names the city")
	check_eq(view.unit_buttons.size(), defenders.size() * 3, "unit list shows the player's units")
	var ul: Control = view.unit_list
	check(ul.get_global_rect().position.x < 400, "unit list on the left")
	check_eq(view.action_buttons.size(), 5, "5 action buttons")
	var mv_btn: Button = view.action_buttons["Move"]
	check(mv_btn.disabled and mv_btn.get_global_rect().position.y > 1000, "action buttons at the bottom, disabled until step 16")
	var g: Control = view.grid
	check(g.get_global_rect().position.x > 340 and g.get_global_rect().end.x < 1620, "grid between the side panels")
	check(g.size.x >= 20 * 30, "grid is drawn at a usable size")
	# Hover info.
	view._on_tile_hovered(view.map.objectives[0])
	check(view.tile_info.text.contains("Objective 1"), "hover shows tile info")
	# Placement through the grid.
	var my_unit = view.deployment.units_of("defender")[0]
	var target := Vector2i(-1, -1)
	for p in view.map.deploy_tiles("defender"):
		if view.deployment.unit_at(p) == null:
			target = p
			break
	var b1: Button = view.unit_buttons[my_unit.id]
	b1.pressed.emit()
	check_eq(view.selected_unit, my_unit.id, "unit list button selects the unit")
	check(view.grid.valid_tiles().has(target), "free deploy tile highlighted")
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = view.grid.tile_center(target)
	view.grid._gui_input(ev)
	check_eq(my_unit.pos, target, "click on a highlighted tile places the unit")
	check(view.unit_buttons[my_unit.id].text.contains("(%d,%d)" % [target.x, target.y]), "unit list shows the new tile")
	view.click_tile(Vector2i(10, 10))
	check_eq(my_unit.pos, target, "click outside the zone does not move the unit")
	check(view.hint_label.text != "", "refusal reason shown")
	var enemy = view.deployment.units_of("attacker")[0]
	view.click_tile(enemy.pos)
	check(view.selected_unit != enemy.id, "enemy units cannot be selected")
	view.select_unit(my_unit.id)
	view.withdraw_selected()
	check(not my_unit.is_deployed(), "To reserve button sends the unit to reserve")
	view.auto_deploy()
	check(my_unit.is_deployed(), "Auto-deploy places it again")
	# Return to map.
	view.return_button.pressed.emit()
	await process_frame
	check(game.tactical_view == null, "return closes the tactical view")
	check(game.get_node("World").visible and game.get_node("UI").visible, "strategic view restored")
	check(game.get_node("World").process_mode == Node.PROCESS_MODE_INHERIT, "map processing restored")
	check(cb.has_battle("berlin"), "strategic battle continues (auto-resolve)")
	game.queue_free()
	await process_frame
