extends "res://tests/test_base.gd"
## Step 13: diplomacy. Diplomacy autoload (war goal justification over time,
## war declaration gated by war goal + pact, symmetric war, non-aggression
## pacts, military access, scripted historical wars for AI Germany, save
## round trip) and the Diplomacy tab UI.
## (Untyped vars on purpose: see PROGRESS.md "Tests and autoload names".)

var wars: Array = []
var pacts: Array = []
var access: Array = []


func run_tests() -> void:
	var gs: Node = autoload("GameState")
	var gd: Node = autoload("GameData")
	var bus: Node = autoload("EventBus")
	var sim: Node = autoload("Simulation")
	var tm: Node = autoload("TimeManager")
	var mv: Node = autoload("Movement")
	var dp: Node = autoload("Diplomacy")
	check(dp != null, "Diplomacy autoload present")
	if dp == null:
		return
	check(sim.daily_systems().has("diplomacy"), "diplomacy daily system registered")
	bus.war_declared.connect(func(a: String, b: String) -> void: wars.append([a, b]))
	bus.pact_signed.connect(func(a: String, b: String) -> void: pacts.append([a, b]))
	bus.military_access_granted.connect(func(h: String, g: String) -> void: access.append([h, g]))
	var days: int = int(gd.rule("war_goal_days", 0))
	check_eq(days, 30, "war_goal_days rule = 30")

	# --- Start: nobody at war, France neutral ---
	gs.new_game("germany")
	for nid in gd.nation_ids:
		check(gs.nation(nid).at_war_with.is_empty(), nid + " starts at peace")
	check(dp.status_text("germany", "france").begins_with("Neutral"), "France neutral")

	# --- Justification ---
	check(dp.declare_war_error("germany", "poland") != "", "cannot declare without war goal")
	check(not dp.declare_war("germany", "poland"), "declare refused")
	check(gs.nation("germany").at_war_with.is_empty(), "refused declaration changes nothing")
	check(dp.justification_error("germany", "germany") != "", "cannot justify on self")
	check(dp.start_justification("germany", "poland"), "start justification")
	check(not dp.start_justification("germany", "poland"), "cannot justify twice")
	check(dp.is_justifying("germany", "poland"), "justifying")
	check_eq(dp.war_goal_days_left("germany", "poland"), days, "days left = rule")
	check(dp.declare_war_error("germany", "poland").contains("not ready"), "declare blocked while justifying")
	tm.advance_days(days - 1)
	check(not dp.has_war_goal("germany", "poland"), "not ready one day early")
	check_eq(dp.war_goal_days_left("germany", "poland"), 1, "1 day left")
	tm.advance_days(1)
	check(dp.has_war_goal("germany", "poland"), "war goal ready after %d days" % days)
	check(dp.can_declare_war("germany", "poland"), "can declare war")
	# Save round trip keeps the war goal.
	var saved: Dictionary = JSON.parse_string(JSON.stringify(gs.to_dict()))
	gs.load_from_dict(saved)
	check(dp.has_war_goal("germany", "poland"), "war goal survives save/load")
	wars.clear()
	check(dp.declare_war("germany", "poland"), "declare war")
	check(gs.nation("germany").is_at_war_with("poland") and gs.nation("poland").is_at_war_with("germany"), "war symmetric")
	check_eq(wars, [["germany", "poland"]], "war_declared emitted")
	check(not gs.nation("germany").war_goals.has("poland"), "war goal consumed")
	check(dp.declare_war_error("germany", "poland").contains("Already"), "cannot declare twice")
	check(mv.is_hostile("germany", "poland"), "Movement sees Poland hostile")
	check(dp.pact_error("germany", "poland") != "", "no pact while at war")
	check(not dp.request_access("germany", "poland"), "no access while at war")
	# Cancel justification.
	dp.start_justification("germany", "austria")
	check(dp.cancel_justification("germany", "austria"), "cancel justification")
	check_eq(dp.war_goal_days_left("germany", "austria"), -1, "war goal gone")

	# --- Pacts ---
	gs.new_game("germany")
	pacts.clear()
	dp.start_justification("germany", "ussr")
	check(dp.offer_pact("germany", "ussr"), "pact accepted at peace")
	check_eq(pacts, [["germany", "ussr"]], "pact_signed emitted")
	check(dp.has_pact("germany", "ussr") and dp.has_pact("ussr", "germany"), "pact both ways")
	check(not gs.nation("germany").war_goals.has("ussr"), "pact cancels war goal")
	check(dp.justification_error("germany", "ussr").contains("pact"), "pact blocks justification")
	check(dp.justification_error("ussr", "germany").contains("pact"), "pact blocks justification for partner")
	gs.nation("germany").war_goals["ussr"] = 0
	check(dp.declare_war_error("germany", "ussr").contains("pact"), "pact blocks war declaration")
	check(not dp.declare_war("germany", "ussr"), "declare refused under pact")
	check(not dp.offer_pact("germany", "ussr"), "no duplicate pact")
	check(dp.cancel_pact("germany", "ussr"), "break pact")
	check(not dp.has_pact("germany", "ussr"), "pact gone")
	check(dp.can_declare_war("germany", "ussr"), "declare possible after pact broken")
	var saved2: Dictionary = gs.to_dict()
	dp.offer_pact("germany", "uk")
	saved2 = JSON.parse_string(JSON.stringify(gs.to_dict()))
	gs.load_from_dict(saved2)
	check(dp.has_pact("germany", "uk"), "pact survives save/load")

	# --- Military access ---
	gs.new_game("germany")
	access.clear()
	check(not mv.is_passable("germany", "poland"), "Poland not passable without access")
	check(dp.request_access("germany", "poland"), "access granted at peace")
	check_eq(access, [["poland", "germany"]], "military_access_granted(host, guest)")
	check(dp.has_access("germany", "poland"), "has access")
	check(not dp.has_access("poland", "germany"), "access is one way")
	check(mv.is_passable("germany", "poland"), "Poland passable with access")
	check(dp.access_error("germany", "poland") != "", "no duplicate access request")
	var d = gs.add_division("infantry", "germany", "berlin")
	check(mv.order_move(d.id, "poland"), "move into access territory")
	for i in 10:
		tm.advance_days(1)
	check_eq(d.province, "poland", "division in Poland via access")
	# War with the host revokes access and sends the division home.
	gs.nation("germany").war_goals["poland"] = 0
	check(dp.declare_war("germany", "poland"), "declare war on host")
	check(not dp.has_access("germany", "poland"), "war revokes access")
	check_eq(d.province, "berlin", "division evacuated to the capital")
	check(not d.is_moving(), "evacuated division holds")
	check(dp.revoke_access("poland", "germany") == false, "revoke without access = false")
	dp.request_access("germany", "austria")
	check(dp.revoke_access("austria", "germany"), "revoke access")
	check(not mv.is_passable("germany", "austria"), "Austria impassable after revoke")

	# --- Capitulated targets refused ---
	gs.new_game("germany")
	gs.nation("hungary").capitulated = true
	check(dp.justification_error("germany", "hungary") != "", "cannot justify on capitulated")
	check(dp.pact_error("germany", "hungary") != "", "no pact with capitulated")

	# --- Scripted historical wars ---
	var sw: Array = dp.scripted_wars()
	check(sw.size() >= 2, "scripted wars in rules")
	gs.new_game("ussr")   # Germany is AI
	gs.day_index = GameDate.to_index(1939, 8, 31)
	tm.advance_days(1)
	check(gs.nation("germany").is_at_war_with("poland"), "AI Germany declares on Poland 1 Sep 1939")
	check(not gs.nation("germany").is_at_war_with("france"), "not yet on France")
	gs.day_index = GameDate.to_index(1940, 5, 9)
	tm.advance_days(1)
	check(gs.nation("germany").is_at_war_with("france"), "AI Germany declares on France 10 May 1940")
	check(gs.nation("france").is_at_war_with("germany"), "France at war (symmetric)")
	gs.new_game("ussr")
	gs.day_index = GameDate.to_index(1939, 8, 30)
	tm.advance_days(1)
	check(gs.nation("germany").at_war_with.is_empty(), "no war one day early")
	gs.new_game("germany")   # player Germany: no scripted war
	gs.day_index = GameDate.to_index(1940, 6, 1)
	tm.advance_days(1)
	check(gs.nation("germany").at_war_with.is_empty(), "player Germany not forced into war")

	# --- UI ---
	var main: Node = load("res://scenes/game/game.tscn").instantiate()
	root.add_child(main)
	await process_frame
	gs.new_game("germany")
	await process_frame
	await process_frame
	var hud = main.hud
	var tab = hud.side_panel.tab_content("Diplomacy")
	check(tab.get_node_or_null("Placeholder") == null, "diplomacy placeholder removed")
	var panel = hud.diplomacy_panel
	check(panel != null and panel.get_parent() == tab, "DiplomacyPanel in Diplomacy tab")
	if panel == null:
		return
	check(not panel.rows.has("germany"), "no row for the player")
	check_eq(panel.rows.size(), gd.nation_ids.size() - 1, "one row per other nation")
	var r: Dictionary = panel.rows["poland"]
	check(r.status.text.begins_with("Neutral"), "Poland status Neutral")
	check(r.declare.disabled and r.declare.tooltip_text != "", "declare disabled with reason")
	check(not r.justify.disabled, "justify enabled")
	r.justify.pressed.emit()
	await process_frame
	check(dp.is_justifying("germany", "poland"), "justify button starts justification")
	check(r.status.text.contains("justifying"), "status shows justification")
	check(r.justify.text == "Cancel" or r.justify.disabled == false, "justify button now cancels")
	tm.advance_days(days)
	await process_frame
	check(not r.declare.disabled, "declare enabled when war goal ready")
	r.declare.pressed.emit()
	await process_frame
	check(gs.nation("germany").is_at_war_with("poland"), "declare button declares war")
	check(r.status.text.begins_with("At war"), "status At war")
	check(r.pact.disabled and r.access.disabled, "pact/access disabled at war")
	var u: Dictionary = panel.rows["uk"]
	u.pact.pressed.emit()
	await process_frame
	check(dp.has_pact("germany", "uk"), "pact button signs pact")
	check(u.status.text.contains("pact"), "status shows pact")
	var h: Dictionary = panel.rows["hungary"]
	h.access.pressed.emit()
	await process_frame
	check(dp.has_access("germany", "hungary"), "access button grants access")
	check(h.status.text.contains("you have access"), "status shows access")
	check(h.access.disabled, "access button disabled once granted")
	main.queue_free()
	await process_frame
