extends "res://tests/test_base.gd"
## Step 6: production system. Production autoload (daily income, manpower,
## equipment output, resource shortages, factory allocation, factory
## construction) and the Production tab UI.
## (Untyped vars on purpose: see PROGRESS.md "Tests and autoload names".)

var completed: Array = []


func run_tests() -> void:
	var gd: Node = autoload("GameData")
	var gs: Node = autoload("GameState")
	var bus: Node = autoload("EventBus")
	var sim: Node = autoload("Simulation")
	var tm: Node = autoload("TimeManager")
	var prod: Node = autoload("Production")
	check(prod != null, "Production autoload present")
	if prod == null:
		return
	check(sim.daily_systems().has("production"), "production registered as daily system")
	bus.factory_completed.connect(func(p: String) -> void: completed.append(p))

	gs.new_game("germany")
	var de = gs.nation("germany")
	var total: int = prod.available_factories("germany")
	check_eq(total, 17, "Germany has 17 factories (6+1+10)")
	check_eq(prod.allocated_total("germany"), total, "default allocation uses all factories")
	check_eq(prod.allocation("germany", "armor"), 4, "default armor = floor(17*0.25)")
	check_eq(prod.allocation("germany", "artillery"), 4, "default artillery = floor(17*0.25)")
	check_eq(prod.allocation("germany", "infantry_equipment"), 9, "default infantry gets remainder")
	for nid in gd.nation_ids:
		check(prod.allocated_total(nid) <= prod.available_factories(nid), nid + " allocation fits factories")

	# --- Allocation API ---
	check_eq(prod.free_factories("germany"), 0, "no free factories after default split")
	check_eq(prod.change_allocation("germany", "armor", 3), 4, "+ with no free factories is clamped")
	check_eq(prod.set_allocation("germany", "armor", 0), 0, "set armor to 0")
	check_eq(prod.free_factories("germany"), 4, "4 factories freed")
	check_eq(prod.set_allocation("germany", "artillery", 100), 8, "set clamps to assigned + free")
	check_eq(prod.set_allocation("germany", "artillery", -3), 0, "set clamps at 0")
	check_eq(prod.set_allocation("germany", "nonsense", 3), 0, "unknown equipment ignored")

	# --- One day of production with exact numbers ---
	prod.set_allocation("germany", "infantry_equipment", 0)
	prod.set_allocation("germany", "infantry_equipment", 4)   # 4 pts/day -> 8 units/day, 2 steel
	prod.set_allocation("germany", "artillery", 3)            # 3 pts/day vs cost 3 -> 1 unit/day, 1 steel
	check_eq(prod.daily_output("germany", "infantry_equipment"), 8.0, "daily_output infantry")
	check_eq(prod.daily_output("germany", "artillery"), 1.0, "daily_output artillery")
	var inc: Dictionary = prod.resource_income("germany")
	check_eq(inc.steel, 8.0, "German steel income 2+0+6")
	check_eq(inc.oil, 0.0, "German oil income 0")
	check_eq(prod.daily_resource_use("germany").steel, 3.0, "expected steel use 2+1")
	check_eq(prod.daily_net("germany").steel, 5.0, "net steel per day")
	var steel0: float = de.stockpile.steel
	var inf0: float = de.stockpile.infantry_equipment
	var art0: float = de.stockpile.artillery
	var mp0: int = de.manpower
	var changed: Array = []
	bus.nation_changed.connect(func(n: String) -> void: changed.append(n))
	tm.advance_days(1)
	check_eq(de.stockpile.infantry_equipment - inf0, 8.0, "8 infantry equipment produced in a day")
	check_eq(de.stockpile.artillery - art0, 1.0, "1 artillery produced in a day")
	check_eq(de.stockpile.steel - steel0, 5.0, "steel: +8 income -3 used")
	check_eq(de.manpower - mp0, 800, "manpower +800/day")
	check(changed.has("germany"), "nation_changed emitted daily")

	# --- Fractional progress carries over ---
	prod.set_allocation("germany", "artillery", 0)
	prod.set_allocation("germany", "armor", 2)   # 2 pts/day, cost 8 -> 1 unit every 4 days
	var arm0: float = de.stockpile.armor
	de.stockpile.oil = 100.0
	tm.advance_days(3)
	check_eq(de.stockpile.armor - arm0, 0.0, "no armor after 3 days")
	check_eq(de.production_progress.armor, 6.0, "armor progress carried (6/8)")
	tm.advance_days(1)
	check_eq(de.stockpile.armor - arm0, 1.0, "1 armor after 4 days")
	check_eq(de.stockpile.oil, 99.0, "armor used 1 oil")

	# --- Shortage stalls production ---
	de.stockpile.oil = 0.0
	arm0 = de.stockpile.armor
	tm.advance_days(8)
	check_eq(de.stockpile.armor - arm0, 0.0, "no armor without oil")
	check(prod.is_short("germany", "armor"), "armor flagged short")
	check(de.production_progress.armor <= 8.0, "stalled progress capped at one unit")
	de.stockpile.oil = 10.0
	tm.advance_days(1)
	check_eq(de.stockpile.armor - arm0, 1.0, "stalled unit finishes once oil arrives")
	check(not prod.is_short("germany", "armor"), "shortage cleared")

	# --- Tech production multiplier ---
	var base_ppf: float = prod.points_per_factory("germany")
	var tech_id := ""
	for t in gd.techs:
		for e in gd.techs[t].get("effects", []):
			if e.get("type", "") == "production_mult":
				tech_id = t
	check(tech_id != "", "a tech with production_mult exists")
	de.researched.append(tech_id)
	check(prod.points_per_factory("germany") > base_ppf, "production_mult tech raises output")
	check(prod.manpower_growth("germany") >= 800, "manpower growth not reduced by tech")
	de.researched.erase(tech_id)

	# --- Factory construction ---
	de.stockpile.steel = 120.0
	check_eq(prod.build_factory_error("germany", "berlin"), "", "can build in Berlin")
	check(prod.build_factory_error("germany", "poland") != "", "cannot build in foreign province")
	check(prod.build_factory_error("uk", "north_sea") != "", "cannot build in naval zone")
	check(not prod.build_factory("germany", "france"), "build in France refused")
	var berlin = gs.province("berlin")
	var f0: int = berlin.factories
	check(prod.build_factory("germany", "berlin"), "build factory in Berlin")
	check_eq(de.stockpile.steel, 70.0, "factory cost 50 steel")
	check_eq(berlin.factory_queue.size(), 1, "factory queued")
	check_eq(prod.construction_list("germany").size(), 1, "construction_list has it")
	check(prod.build_factory("germany", "berlin"), "second factory in Berlin")
	check(not prod.build_factory("germany", "berlin"), "third refused: only 20 steel")
	check(prod.build_factory_error("germany", "berlin").contains("steel"), "reason mentions steel")
	de.stockpile.steel = 100000.0
	# Province cap
	var cap: int = prod.max_factories_per_province()
	var ep = gs.province("east_prussia")
	while ep.factories + ep.factory_queue.size() < cap:
		if not prod.build_factory("germany", "east_prussia"):
			break
	check(prod.build_factory_error("germany", "east_prussia").contains("full"), "province full at cap")
	ep.factory_queue.clear()
	# Occupation pauses construction
	var wg = gs.province("western_germany")
	prod.build_factory("germany", "western_germany")
	wg.controller = "france"
	check(prod.build_factory_error("germany", "western_germany") != "", "cannot build in occupied province")
	completed.clear()
	var days: int = prod.factory_build_days()
	tm.advance_days(days - 1)
	check_eq(berlin.factories, f0, "not finished one day early")
	tm.advance_days(1)
	check_eq(berlin.factories, f0 + 2, "both Berlin factories finished after build days")
	check(berlin.factory_queue.is_empty(), "Berlin queue empty")
	check_eq(completed.count("berlin"), 2, "factory_completed emitted twice for Berlin")
	check_eq(wg.factory_queue.size(), 1, "occupied province construction paused")
	check_eq(int(wg.factory_queue[0].days_left), days, "paused days unchanged")
	# Losing western germany (10 factories) shrinks allocation
	bus.province_changed.emit("western_germany")
	check(prod.allocated_total("germany") <= prod.available_factories("germany"), "allocation clamped after losing province")
	wg.controller = "germany"
	bus.province_changed.emit("western_germany")

	# --- Save round trip keeps production state ---
	prod.set_allocation("germany", "armor", 1)
	var d: Dictionary = JSON.parse_string(JSON.stringify(gs.to_dict()))
	var alloc_before: Dictionary = de.factory_allocation.duplicate()
	check(gs.load_from_dict(d), "load save dict")
	var de2 = gs.nation("germany")
	for eq in gd.equipment_ids:
		check_eq(de2.factory_allocation[eq], alloc_before[eq], "allocation saved: " + eq)
	check_eq(gs.province("western_germany").factory_queue.size(), 1, "factory queue saved")

	# --- Capitulated nations are skipped ---
	gs.new_game("germany")
	var pl = gs.nation("poland")
	pl.capitulated = true
	var pmp: int = pl.manpower
	tm.advance_days(2)
	check_eq(pl.manpower, pmp, "capitulated nation does not grow")

	# --- UI: Production tab ---
	gs.new_game("germany")
	root.size = Vector2i(1920, 1080)
	var game = (load("res://scenes/game/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	for i in 3:
		await process_frame
	var hud = game.get_node("UI/HUD")
	var panel = hud.production_panel
	check(panel != null and panel.get_parent() == hud.side_panel.tab_content("Production"), "panel in Production tab")
	check(hud.side_panel.tab_content("Production").get_node_or_null("Placeholder") == null, "placeholder removed")
	check_eq(panel.equip_rows.size(), 3, "3 equipment rows")
	de = gs.nation("germany")
	check(panel.summary_label.text.contains("17 factories"), "summary shows factory count")
	var row: Dictionary = panel.equip_rows["armor"]
	check_eq(row.assigned.text, "4", "armor row shows allocation")
	check(row.output.text.contains("/ day"), "output per day shown")
	check(row.stock.text.contains("120"), "stockpile shown")
	check(row.plus.disabled, "+ disabled with no free factories")
	row.minus.pressed.emit()
	check_eq(prod.allocation("germany", "armor"), 3, "- button removes a factory")
	check_eq(row.assigned.text, "3", "row updated after -")
	check(not row.plus.disabled, "+ enabled with a free factory")
	panel.equip_rows["artillery"].plus.pressed.emit()
	check_eq(prod.allocation("germany", "artillery"), 5, "+ button assigns a factory")
	check(panel.resource_labels["steel"].text.contains("income"), "steel balance shown")
	check(panel.build_buttons.has("berlin") and panel.build_buttons.has("western_germany"), "build buttons for owned provinces")
	check(not panel.build_buttons.has("poland"), "no build button for foreign provinces")
	var bb = panel.build_buttons["berlin"]
	check(not bb.disabled, "build button enabled with enough steel")
	var steel_before: float = de.stockpile.steel
	bb.pressed.emit()
	check_eq(gs.province("berlin").factory_queue.size(), 1, "build button queues a factory")
	check_eq(de.stockpile.steel, steel_before - 50.0, "build button spends steel")
	await process_frame
	check(panel.construction_box.get_child_count() == 1 and panel.construction_box.get_child(0).name == "Item",
		"construction list shows the factory")
	de.stockpile.steel = 0.0
	bus.nation_changed.emit("germany")
	await process_frame
	check(bb.disabled and bb.tooltip_text.contains("steel"), "build disabled without steel + reason tooltip")
	tm.advance_days(1)
	await process_frame
	check(panel.equip_rows["artillery"].stock.text.contains("Stockpile"), "UI refreshes after a day")
	game.queue_free()
	await process_frame
