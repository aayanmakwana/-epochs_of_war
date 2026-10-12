extends "res://tests/test_base.gd"
## Step 10: strategic combat. Combat autoload (battle on entry into a defended
## enemy province, daily damage from attack vs defense with terrain,
## entrenchment and artillery support, retreat / destruction, capture of the
## province, undefended capture on arrival, attacker withdrawal, recovery,
## save round trip mid-battle) and the map / info panel battle display.
## (Untyped vars on purpose: see PROGRESS.md "Tests and autoload names".)

var started: Array = []
var ended: Array = []
var captured: Array = []
var destroyed: Array = []


func war(gs: Node, a: String, b: String) -> void:
	gs.nation(a).at_war_with.append(b)
	gs.nation(b).at_war_with.append(a)


func run_until_end(tm: Node, max_days: int) -> int:
	var n0 := ended.size()
	for i in max_days:
		tm.advance_days(1)
		if ended.size() > n0:
			return i + 1
	return -1


func run_tests() -> void:
	var gs: Node = autoload("GameState")
	var gd: Node = autoload("GameData")
	var bus: Node = autoload("EventBus")
	var sim: Node = autoload("Simulation")
	var tm: Node = autoload("TimeManager")
	var mv: Node = autoload("Movement")
	var cb: Node = autoload("Combat")
	check(cb != null, "Combat autoload present")
	if cb == null:
		return
	var daily: PackedStringArray = sim.daily_systems()
	check(daily.has("combat") and daily.find("movement") < daily.find("combat"), "combat daily system after movement")
	check(daily.has("combat_recovery"), "recovery daily system")
	check(mv.hostile_entry.is_valid(), "Movement.hostile_entry hook set")
	bus.battle_started.connect(func(p: String) -> void: started.append(p))
	bus.battle_ended.connect(func(p: String, w: bool) -> void: ended.append([p, w]))
	bus.province_captured.connect(func(p: String, n: String, o: String) -> void: captured.append([p, n, o]))
	bus.division_destroyed.connect(func(d: int) -> void: destroyed.append(d))

	# --- Combat math ---
	gs.new_game("germany")
	var inf = gs.add_division("infantry", "germany", "berlin")
	var art = gs.add_division("artillery", "germany", "berlin")
	var pinf = gs.add_division("infantry", "poland", "poland")
	var a1: Array[DivisionState] = [inf]
	var a2: Array[DivisionState] = [inf, art]
	var d1: Array[DivisionState] = [pinf]
	var p_plain: Dictionary = cb.powers("poland", a1, d1)
	check_eq(p_plain.att_attack, 8.0, "infantry attack 8 on plains")
	var p_art: Dictionary = cb.powers("poland", a2, d1)
	check_eq(p_art.att_attack, (8.0 + 14.0) * 1.2, "artillery adds attack + 20% support")
	var p_mtn: Dictionary = cb.powers("austria", a1, d1)
	check_eq(p_mtn.att_attack, 8.0 * 0.75, "mountain attack modifier -25%")
	check(p_mtn.def_defense > p_plain.def_defense, "mountain raises defender defense")
	pinf.entrenchment = 1.0
	var p_ent: Dictionary = cb.powers("poland", a1, d1)
	check_eq(p_ent.def_defense, p_plain.def_defense * 1.25, "full entrenchment +25% defense")
	pinf.entrenchment = 0.0
	pinf.hp = 50.0
	check_eq(cb.strength(pinf), 0.75, "half HP -> 75% strength")
	check_eq(cb.damage(10.0, 10.0), 18.0, "damage = scale x attack x ratio")
	check_eq(cb.damage(100.0, 1.0), 1.8 * 100.0 * 4.0, "ratio clamped at 4")

	# --- Recovery and entrenchment ---
	gs.new_game("germany")
	var r = gs.add_division("infantry", "germany", "berlin")
	r.organization = 10.0
	r.hp = 50.0
	tm.advance_days(1)
	check(absf(r.entrenchment - 0.1) < 0.001, "entrenchment +0.1/day when holding")
	check(absf(r.organization - 15.0) < 0.01, "org recovers 10%/day out of battle")
	check(absf(r.hp - 52.0) < 0.01, "HP recovers 2%/day in own territory")
	mv.order_move(r.id, "east_prussia")
	tm.advance_days(1)
	check_eq(r.entrenchment, 0.0, "no entrenchment while moving")

	# --- Attack on Poland: battle, save mid-battle, capture, destruction ---
	gs.new_game("germany")
	war(gs, "germany", "poland")
	var ids: Array = []
	for i in 4:
		ids.append(gs.add_division("infantry", "germany", "berlin").id)
	var weak = gs.add_division("infantry", "germany", "berlin")
	ids.append(weak.id)
	var polish: Array = []
	for d in gs.divisions_in("poland"):
		polish.append(d.id)
	check_eq(polish.size(), 2, "Poland starts with 2 divisions")
	check_eq(mv.order_move_group(ids, "poland"), 5, "5 divisions ordered into enemy Poland")
	started.clear()
	for i in 10:
		tm.advance_days(1)
		if not started.is_empty():
			break
	check_eq(started, ["poland"], "battle_started(poland) on arrival")
	check(cb.has_battle("poland"), "battle registered")
	check_eq(gs.division(ids[0]).province, "berlin", "attackers wait in Berlin during battle")
	check_eq(gs.province("poland").controller, "poland", "Poland not captured yet")
	weak.hp = 0.1   # dies on the next combat tick
	if cb.has_battle("poland"):
		check_eq(int(cb.battle_at("poland").days), 1, "first combat tick on arrival day")
		var data: Dictionary = JSON.parse_string(JSON.stringify(gs.to_dict()))
		gs.load_from_dict(data)
		check(cb.has_battle("poland") and cb.attackers("poland").size() == 5, "battle survives save/load")
	captured.clear()
	var days: int = run_until_end(tm, 10)
	check(days > 0, "battle ended")
	check(ended.size() > 0 and ended[-1] == ["poland", true], "battle_ended(poland, attacker won)")
	check(gs.division(weak.id) == null and destroyed.has(weak.id), "division at 0 HP destroyed")
	check(gs.nation("germany").stats.divisions_lost >= 1, "divisions_lost stat")
	check(not cb.has_battle("poland"), "battle removed")
	check_eq(gs.province("poland").controller, "germany", "Poland captured by Germany")
	check_eq(gs.province("poland").owner, "poland", "owner keeps the claim (occupied)")
	check(captured.has(["poland", "germany", "poland"]), "province_captured emitted")
	check_eq(gs.division(ids[0]).province, "poland", "attackers entered Poland")
	check(gs.division(polish[0]) == null and gs.division(polish[1]) == null, "Polish divisions destroyed (no retreat)")
	check_eq(gs.nation("germany").stats.battles_won, 1, "battles_won stat")
	check_eq(gs.nation("poland").stats.battles_lost, 1, "battles_lost stat")
	check_eq(gs.nation("germany").stats.provinces_conquered, 1, "provinces_conquered stat")

	# --- Undefended province captured on arrival ---
	gs.new_game("germany")
	war(gs, "germany", "czechoslovakia")
	for d in gs.divisions_in("czechoslovakia"):
		gs.remove_division(d.id)
	var u = gs.add_division("infantry", "germany", "berlin")
	started.clear()
	captured.clear()
	mv.order_move(u.id, "czechoslovakia")
	tm.advance_days(ceili(mv.hop_days(u, "czechoslovakia")))
	check_eq(u.province, "czechoslovakia", "entered undefended province")
	check_eq(gs.province("czechoslovakia").controller, "germany", "undefended province captured on arrival")
	check(started.is_empty(), "no battle for an undefended province")
	check_eq(captured.size(), 1, "one capture event")

	# --- Defender holds: lone artillery vs entrenched mountain infantry ---
	gs.new_game("germany")
	war(gs, "germany", "austria")
	var aus = gs.divisions_in("austria")[0]
	aus.entrenchment = 1.0
	var gart = gs.add_division("artillery", "germany", "western_germany")
	mv.order_move(gart.id, "austria")
	var d2: int = run_until_end(tm, 25)
	check(d2 > 0 and ended[-1] == ["austria", false], "battle_ended(austria, defender won)")
	check_eq(gs.province("austria").controller, "austria", "Austria holds")
	check(gs.division(aus.id) != null and gs.division(aus.id).province == "austria", "defender still in Austria")
	check(gart.province == "western_germany" and not gart.is_moving(), "attacker falls back / stops in its province")
	check(gart.organization < 5.0, "attacker disorganised")

	# --- Defender retreats to an adjacent friendly province ---
	gs.new_game("germany")
	war(gs, "germany", "ussr")
	gs.province("poland").controller = "germany"
	var sov = gs.divisions_in("belarus")[0]
	var gids: Array = []
	for i in 5:
		gids.append(gs.add_division("infantry", "germany", "poland").id)
	mv.order_move_group(gids, "belarus")
	var d3: int = run_until_end(tm, 20)
	check(d3 > 0 and ended[-1] == ["belarus", true], "Germany wins in Belarus")
	check(gs.division(sov.id) != null, "Soviet division survived (retreated)")
	if gs.division(sov.id):
		check(gd.are_adjacent("belarus", sov.province) and gs.province(sov.province).controller == "ussr",
			"retreated into adjacent Soviet province (" + sov.province + ")")
	check_eq(gs.province("belarus").controller, "germany", "Belarus captured")

	# --- Attacker stops -> defender wins ---
	gs.new_game("germany")
	war(gs, "germany", "poland")
	var s = gs.add_division("infantry", "germany", "berlin")
	s.move_progress = 0.0
	s.path.assign(["poland"])
	s.move_progress = 1.0
	check(not cb._on_hostile_entry(s, "poland"), "hook holds the attacker")
	check(cb.has_battle("poland"), "battle started via hook")
	mv.stop(s.id)
	tm.advance_days(1)
	check(not cb.has_battle("poland") and ended[-1] == ["poland", false], "battle ends when attackers leave")

	# --- UI: fronts, battle marker, info panel ---
	gs.new_game("germany")
	var game = (load("res://scenes/game/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await process_frame
	var map = game.map_view
	var info = game.hud.info_panel
	check(map.front_borders().is_empty(), "no front lines at peace")
	war(gs, "germany", "poland")
	check(map.front_borders().has("berlin|poland") or map.front_borders().has("poland|berlin"), "front line Berlin-Poland at war")
	var att = gs.add_division("infantry", "germany", "berlin")
	att.path.assign(["poland"])
	att.move_progress = 1.0
	cb._on_hostile_entry(att, "poland")
	var markers: Array = map.battle_markers()
	check(markers.size() == 1 and markers[0].province == "poland", "battle marker on Poland")
	map.select_province("poland")
	await process_frame
	var bi = info.content.find_child("BattleInfo", true, false)
	check(bi != null and bi.text.contains("Germany"), "info panel shows battle")
	check(info.content.find_child("Bar_Battle", true, false) != null, "battle progress bar")
	map.select_province("berlin")
	await process_frame
	check(info.content.find_child("BattleInfo", true, false) == null, "no battle section elsewhere")
	game.queue_free()
	await process_frame
