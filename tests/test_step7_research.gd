extends "res://tests/test_base.gd"
## Step 7: research system. Research autoload (one tech at a time, daily
## progress, completion, prerequisites, switching keeps progress, effects via
## TechEffects, save round trip) and the Research tab UI.
## (Untyped vars on purpose: see PROGRESS.md "Tests and autoload names".)

var started: Array = []
var completed: Array = []
var notes: Array = []


func run_tests() -> void:
	var gd: Node = autoload("GameData")
	var gs: Node = autoload("GameState")
	var bus: Node = autoload("EventBus")
	var sim: Node = autoload("Simulation")
	var tm: Node = autoload("TimeManager")
	var res: Node = autoload("Research")
	var TE: GDScript = load("res://scripts/core/tech_effects.gd")
	check(res != null, "Research autoload present")
	if res == null:
		return
	check(sim.daily_systems().has("research"), "research registered as daily system")
	check(sim.daily_systems().find("production") < sim.daily_systems().find("research"), "research runs after production")
	bus.research_started.connect(func(n: String, t: String) -> void: started.append([n, t]))
	bus.research_completed.connect(func(n: String, t: String) -> void: completed.append([n, t]))
	bus.notify.connect(func(t: String) -> void: notes.append(t))

	gs.new_game("uk")
	var uk = gs.nation("uk")
	check_eq(uk.current_research, "", "new game: nothing being researched")
	check(uk.researched.has("basic_infantry") and not uk.researched.has("light_tanks"), "UK starting techs")

	# --- Status / errors ---
	check_eq(res.status("uk", "basic_infantry"), "researched", "status researched")
	check_eq(res.status("uk", "improved_infantry"), "available", "status available")
	check_eq(res.status("uk", "medium_tanks"), "locked", "status locked")
	check(res.research_error("uk", "medium_tanks").contains("Light Tanks"), "locked reason names prerequisite")
	check(res.research_error("uk", "basic_infantry") != "", "cannot research a done tech")
	check(res.research_error("uk", "nonsense") != "", "unknown tech refused")
	check(not res.start_research("uk", "medium_tanks"), "start refused without prerequisite")
	check_eq(uk.current_research, "", "refused start changes nothing")
	var avail: PackedStringArray = res.available_techs("uk")
	check_eq(avail, PackedStringArray(["improved_infantry", "light_tanks", "mass_assault"]), "available techs")
	check_eq(res.branch_progress("uk", "infantry"), {"done": 1, "total": 5}, "branch progress")

	# --- Research light tanks: exact days, unlock effect ---
	check(not TE.is_division_unlocked("armor", uk.researched), "armor locked before light tanks")
	check(res.start_research("uk", "light_tanks"), "start light tanks")
	check_eq(started.back(), ["uk", "light_tanks"], "research_started emitted")
	check_eq(res.current("uk"), "light_tanks", "current research set")
	check(res.research_error("uk", "light_tanks").contains("Already"), "cannot start the same tech twice")
	check_eq(res.days_left("uk"), 30, "30 days left at start")
	tm.advance_days(10)
	check_eq(uk.research_progress, 10.0, "10 days of progress after 10 days")
	check_eq(res.progress_fraction("uk"), 10.0 / 30.0, "progress fraction")
	check_eq(res.days_left("uk"), 20, "20 days left")
	completed.clear()
	tm.advance_days(19)
	check(completed.is_empty(), "not finished one day early")
	tm.advance_days(1)
	check_eq(completed, [["uk", "light_tanks"]], "research_completed after 30 days")
	check(uk.researched.has("light_tanks"), "light tanks researched")
	check_eq(uk.current_research, "", "current research cleared")
	check_eq(uk.research_progress, 0.0, "progress reset")
	check(TE.is_division_unlocked("armor", uk.researched), "armor unlocked by light tanks")
	check(notes.size() > 0 and String(notes.back()).contains("Light Tanks"), "player notified")
	check_eq(res.status("uk", "medium_tanks"), "available", "next tier now available")

	# --- Stat effect ---
	var atk0: float = TE.division_stats("armor", uk.researched).attack
	res.start_research("uk", "medium_tanks")
	tm.advance_days(45)
	check(uk.researched.has("medium_tanks"), "medium tanks done after 45 days")
	check_eq(TE.division_stats("armor", uk.researched).attack, atk0 * 1.15, "medium tanks: armor attack +15%")

	# --- Switching keeps progress; stop keeps progress ---
	check(res.start_research("uk", "improved_infantry"), "start improved infantry")
	tm.advance_days(5)
	check(res.start_research("uk", "mass_assault"), "switch to mass assault")
	check_eq(res.current("uk"), "mass_assault", "switched")
	check_eq(uk.research_saved.get("improved_infantry", 0.0), 5.0, "old tech progress saved")
	check_eq(res.progress_days("uk", "improved_infantry"), 5.0, "progress_days reads saved progress")
	tm.advance_days(3)
	check(res.cancel_research("uk"), "stop research")
	check_eq(res.current("uk"), "", "nothing researched after stop")
	check(not res.cancel_research("uk"), "stop with nothing running returns false")
	tm.advance_days(4)
	check_eq(res.progress_days("uk", "mass_assault"), 3.0, "no progress while idle")
	res.start_research("uk", "improved_infantry")
	check_eq(uk.research_progress, 5.0, "resumes saved progress")
	check(not uk.research_saved.has("improved_infantry"), "resumed entry removed from saved")
	check_eq(res.days_left("uk"), 40, "45-5 days left")

	# --- Save round trip ---
	var d: Dictionary = JSON.parse_string(JSON.stringify(gs.to_dict()))
	check(gs.load_from_dict(d), "load save dict")
	var uk2 = gs.nation("uk")
	check_eq(uk2.current_research, "improved_infantry", "current research saved")
	check_eq(uk2.research_progress, 5.0, "research progress saved")
	check_eq(uk2.research_saved.get("mass_assault", 0.0), 3.0, "saved partial progress saved")
	check(uk2.researched.has("medium_tanks"), "researched list saved")
	tm.advance_days(40)
	check(uk2.researched.has("improved_infantry"), "loaded research completes")

	# --- Other nations research in parallel; capitulated skipped ---
	gs.new_game("germany")
	check(res.start_research("ussr", "mass_assault"), "AI nation can research")
	check(res.start_research("poland", "basic_infantry"), "minor can research")
	gs.nation("poland").capitulated = true
	check(res.research_error("poland", "light_tanks") != "", "capitulated nation cannot start research")
	notes.clear()
	tm.advance_days(30)
	check(gs.nation("ussr").researched.has("mass_assault"), "USSR finished mass assault")
	check_eq(gs.nation("poland").research_progress, 0.0, "capitulated nation makes no progress")
	check(notes.is_empty(), "no notification for AI research")

	# --- Total war multipliers flow into production ---
	var de = gs.nation("germany")
	var prod: Node = autoload("Production")
	var ppf0: float = prod.points_per_factory("germany")
	for t in ["mass_assault", "deep_battle", "combined_arms", "blitzkrieg"]:
		de.researched.append(t)
	check(res.start_research("germany", "total_war"), "total war available after doctrine chain")
	tm.advance_days(90)
	check(de.researched.has("total_war"), "total war researched")
	check_eq(prod.points_per_factory("germany"), ppf0 * 1.15, "total war: production +15%")

	# --- UI: Research tab ---
	gs.new_game("germany")
	root.size = Vector2i(1920, 1080)
	var game = (load("res://scenes/game/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	for i in 3:
		await process_frame
	var hud = game.get_node("UI/HUD")
	var panel = hud.research_panel
	check(panel != null and panel.get_parent() == hud.side_panel.tab_content("Research"), "panel in Research tab")
	check(hud.side_panel.tab_content("Research").get_node_or_null("Placeholder") == null, "placeholder removed")
	var grid = panel.get_node_or_null("TechGrid")
	check(grid != null and grid.columns == 3, "tech grid has 3 columns")
	check_eq(panel.tech_cards.size(), 15, "15 tech buttons")
	check(grid.get_child(0).name == "Branch_infantry" and grid.get_child(1).name == "Branch_armor"
		and grid.get_child(2).name == "Branch_doctrine", "branch headers on top of the columns")
	check(grid.get_child(3).name == "Tech_basic_infantry" and grid.get_child(4).name == "Tech_light_tanks"
		and grid.get_child(5).name == "Tech_mass_assault" and grid.get_child(17).name == "Tech_total_war",
		"techs laid out by tier in branch columns")
	check(panel.current_name.text.contains("Nothing"), "idle research shown")
	check(panel.stop_button.disabled, "stop disabled when idle")
	var bi = panel.tech_cards["basic_infantry"].button
	check(bi.disabled and bi.text.contains("Done"), "researched tech button disabled + Done")
	var mt = panel.tech_cards["medium_tanks"].button
	check(not mt.disabled, "medium tanks available for Germany")
	var sf = panel.tech_cards["special_forces"].button
	check(sf.disabled and sf.tooltip_text.contains("Requires"), "locked tech disabled with reason")
	mt.pressed.emit()
	check_eq(res.current("germany"), "medium_tanks", "clicking a tech starts research")
	await process_frame
	check(panel.current_name.text.contains("Medium Tanks"), "current tech shown")
	check(mt.disabled and mt.text.contains("days left"), "researching button shows days left")
	check(not panel.stop_button.disabled, "stop enabled while researching")
	tm.advance_days(9)
	await process_frame
	check_eq(panel.current_bar.value, 9.0 / 45.0, "progress bar follows research")
	check_eq(panel.tech_cards["medium_tanks"].bar.value, 9.0 / 45.0, "tech button bar follows research")
	check(panel.current_days.text.contains("36 left"), "days left label")
	var arm_label = panel.template_labels["armor"]
	var before: String = arm_label.text
	tm.advance_days(36)
	await process_frame
	check(mt.text.contains("Done"), "button shows Done after completion")
	check(arm_label.text != before, "template stats refresh after completion")
	panel.tech_cards["heavy_tanks"].button.pressed.emit()
	panel.stop_button.pressed.emit()
	check_eq(res.current("germany"), "", "stop button stops research")
	game.queue_free()
	await process_frame
