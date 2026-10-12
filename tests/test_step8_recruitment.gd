extends "res://tests/test_base.gd"
## Step 8: military recruitment. Recruitment autoload (costs, refusals, training
## time, deployment, fallback, cancel refund, save round trip), the recruit
## section of the Production tab and unit icons on the map.
## (Untyped vars on purpose: see PROGRESS.md "Tests and autoload names".)

var created: Array = []
var notes: Array = []


func run_tests() -> void:
	var gs: Node = autoload("GameState")
	var bus: Node = autoload("EventBus")
	var sim: Node = autoload("Simulation")
	var tm: Node = autoload("TimeManager")
	var rec: Node = autoload("Recruitment")
	check(rec != null, "Recruitment autoload present")
	if rec == null:
		return
	# Exact world state below: AI nations must not recruit on their own (step 14).
	var ai: Node = autoload("AI")
	if ai:
		ai.enabled = false
	var daily: PackedStringArray = sim.daily_systems()
	check(daily.has("recruitment"), "recruitment registered as daily system")
	check(daily.find("research") < daily.find("recruitment"), "recruitment runs after research")
	bus.division_created.connect(func(d: int) -> void: created.append(d))
	bus.notify.connect(func(t: String) -> void: notes.append(t))

	# --- Refusals ---
	gs.new_game("uk")
	check(rec.recruit_error("uk", "armor", "london").contains("Light Tanks"), "armor needs light tanks (UK)")
	check(rec.recruit_error("uk", "infantry", "north_sea").contains("naval"), "cannot deploy at sea")
	check(rec.recruit_error("uk", "infantry", "berlin") != "", "cannot deploy in foreign province")
	check(rec.recruit_error("uk", "nonsense", "london") != "", "unknown template refused")
	check_eq(rec.recruit_error("uk", "infantry", "london"), "", "UK can recruit infantry in London")

	gs.new_game("germany")
	var de = gs.nation("germany")
	check_eq(rec.default_deploy_province("germany"), "berlin", "default deploy = capital")
	check_eq(rec.deploy_provinces("germany"), PackedStringArray(["berlin", "east_prussia", "western_germany"]),
		"deploy provinces = owned land provinces")
	var mp0: int = de.manpower
	var ie0: float = de.stockpile.infantry_equipment
	var ar0: float = de.stockpile.armor
	var divs0: int = gs.divisions_of("germany").size()

	# --- Costs paid up front ---
	check(rec.recruit("germany", "infantry", "western_germany"), "recruit infantry")
	check_eq(de.manpower, mp0 - 10000, "infantry costs 10,000 manpower")
	check_eq(de.stockpile.infantry_equipment, ie0 - 100.0, "infantry costs 100 infantry equipment")
	check_eq(de.recruit_queue.size(), 1, "queued")
	check_eq(int(de.recruit_queue[0].days_left), 30, "30 days of training")
	check(rec.recruit("germany", "armor", "berlin"), "recruit armor (Germany has light tanks)")
	check_eq(de.stockpile.armor, ar0 - 50.0, "armor costs 50 armor")
	check_eq(de.stockpile.infantry_equipment, ie0 - 120.0, "armor costs 20 infantry equipment")
	check_eq(gs.divisions_of("germany").size(), divs0, "no division before training ends")

	# --- Cancel refunds ---
	check(rec.cancel_recruit("germany", 1), "cancel armor")
	check_eq(de.stockpile.armor, ar0, "armor refunded")
	check_eq(de.manpower, mp0 - 10000, "manpower refunded")
	check(not rec.cancel_recruit("germany", 5), "bad index refused")

	# --- Not enough resources ---
	var saved_mp: int = de.manpower
	de.manpower = 5000
	check(rec.recruit_error("germany", "infantry", "berlin").contains("manpower"), "manpower shortage reason")
	check(not rec.recruit("germany", "infantry", "berlin"), "refused without manpower")
	check_eq(de.manpower, 5000, "refused recruit changes nothing")
	de.manpower = saved_mp
	var saved_art: float = de.stockpile.artillery
	de.stockpile.artillery = 10.0
	check(rec.recruit_error("germany", "artillery", "berlin").contains("Artillery"), "equipment shortage reason")
	check_eq(rec.affordable_count("germany", "artillery"), 0, "affordable count 0")
	de.stockpile.artillery = saved_art

	# --- Training time ---
	created.clear()
	notes.clear()
	tm.advance_days(29)
	check(created.is_empty(), "not ready one day early")
	check_eq(int(de.recruit_queue[0].days_left), 1, "1 day left")
	tm.advance_days(1)
	check_eq(created.size(), 1, "division_created after 30 days")
	check(de.recruit_queue.is_empty(), "queue empty")
	var d = gs.division(created[0])
	check(d != null and d.template == "infantry" and d.owner == "germany" and d.province == "western_germany",
		"division deployed in chosen province")
	check(d != null and d.hp > 0.0, "division at full strength")
	check(notes.size() > 0 and String(notes.back()).contains("Western Germany"), "player notified")

	# --- Fallback when the deploy province is lost ---
	check(rec.recruit("germany", "infantry", "east_prussia"), "recruit in East Prussia")
	gs.province("east_prussia").controller = "poland"
	check(rec.recruit_error("germany", "infantry", "east_prussia") != "", "cannot recruit in occupied province")
	created.clear()
	tm.advance_days(30)
	check_eq(created.size(), 1, "division still created")
	check_eq(gs.division(created[0]).province, "berlin", "falls back to capital")
	gs.province("east_prussia").controller = "germany"

	# --- Save round trip ---
	check(rec.recruit("germany", "artillery", "berlin"), "recruit artillery")
	tm.advance_days(5)
	var data: Dictionary = JSON.parse_string(JSON.stringify(gs.to_dict()))
	gs.load_from_dict(data)
	var de2 = gs.nation("germany")
	check_eq(de2.recruit_queue.size(), 1, "queue survives save")
	check_eq(int(de2.recruit_queue[0].days_left), 30, "days left survive save")
	check_eq(String(de2.recruit_queue[0].province), "berlin", "province survives save")

	# --- AI nations train too ---
	created.clear()
	check(rec.recruit("france", "infantry", "france"), "France recruits")
	tm.advance_days(30)
	var fr_ok := false
	for did in created:
		if gs.division(did).owner == "france":
			fr_ok = true
	check(fr_ok, "France division created")

	# --- UI + map ---
	gs.new_game("germany")
	de = gs.nation("germany")
	root.size = Vector2i(1920, 1080)
	var game = (load("res://scenes/game/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	for i in 3:
		await process_frame
	var hud = game.get_node("UI/HUD")
	var panel = hud.recruit_panel
	check(panel != null and panel.get_parent() == hud.side_panel.tab_content("Production"), "recruit panel in Production tab")
	check_eq(panel.recruit_buttons.size(), 3, "3 recruit buttons")
	check_eq(panel.deploy_province, "berlin", "UI default deploy = capital")
	var inf_b = panel.recruit_buttons["infantry"]
	check(inf_b.text.contains("10,000") and inf_b.text.contains("30 days"), "button shows cost")
	check(not inf_b.disabled, "infantry button enabled")
	bus.province_selected.emit("western_germany")
	await process_frame
	check_eq(panel.deploy_province, "western_germany", "selecting an owned province sets deploy")
	check_eq(panel.deploy_option.selected, 2, "dropdown follows selection")
	bus.province_selected.emit("moscow")
	await process_frame
	check_eq(panel.deploy_province, "western_germany", "foreign selection ignored")
	panel.deploy_option.select(1)
	panel.deploy_option.item_selected.emit(1)
	check_eq(panel.deploy_province, "east_prussia", "dropdown changes deploy")
	var q0: int = de.recruit_queue.size()
	inf_b.pressed.emit()
	check_eq(de.recruit_queue.size(), q0 + 1, "button recruits")
	check_eq(String(de.recruit_queue.back().province), "east_prussia", "button uses chosen province")
	await process_frame
	check(panel.queue_box.get_node_or_null("Item0/Cancel") != null, "queue row with cancel")
	panel.queue_box.get_node("Item0/Cancel").pressed.emit()
	check_eq(de.recruit_queue.size(), q0, "cancel button refunds/removes")
	de.manpower = 0
	panel.refresh()
	check(inf_b.disabled and inf_b.tooltip_text.contains("manpower"), "disabled with reason")

	var mv = game.get_node("World/MapView")
	var icons: Array = mv.unit_icons()
	var berlin_icon = null
	for ic in icons:
		if ic.province == "berlin" and ic.owner == "germany":
			berlin_icon = ic
	check(berlin_icon != null, "icon for Berlin garrison")
	if berlin_icon:
		check_eq(int(berlin_icon.count), 2, "Berlin icon counts 2 divisions")
		check_eq(String(berlin_icon.letters), "IA", "Berlin icon letters IA")
	var poland_icon = null
	for ic in icons:
		if ic.province == "poland":
			poland_icon = ic
	check(poland_icon != null and poland_icon.owner == "poland", "minor nation icons drawn")
	var n_before := icons.size()
	gs.add_division("infantry", "germany", "east_prussia")
	var ep = null
	for ic in mv.unit_icons():
		if ic.province == "east_prussia":
			ep = ic
	check(ep != null and int(ep.count) == 2, "icon count follows new division")
	check(mv.unit_icons().size() == n_before, "same number of icon boxes")
	game.queue_free()
	await process_frame
