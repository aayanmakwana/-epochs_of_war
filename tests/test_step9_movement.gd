extends "res://tests/test_base.gd"
## Step 9: division movement. Movement autoload (BFS path through friendly
## territory, naval/foreign refusals, military access, hostile adjacent target,
## travel time from speed + terrain + infrastructure, daily progress, arrival,
## division_moved, reroute/halt when a province is lost, stop, save round trip)
## and the map/info panel UI (select division, click / right-click to move,
## arrows, ETA, stop button, unit icon click, Escape).
## (Untyped vars on purpose: see PROGRESS.md "Tests and autoload names".)

var moved: Array = []
var notes: Array = []
var order_changes: Array = []


func run_tests() -> void:
	var gs: Node = autoload("GameState")
	var gd: Node = autoload("GameData")
	var bus: Node = autoload("EventBus")
	var sim: Node = autoload("Simulation")
	var tm: Node = autoload("TimeManager")
	var mv: Node = autoload("Movement")
	check(mv != null, "Movement autoload present")
	if mv == null:
		return
	var daily: PackedStringArray = sim.daily_systems()
	check(daily.has("movement"), "movement registered as daily system")
	check(daily.find("recruitment") < daily.find("movement"), "movement runs after recruitment")
	bus.division_moved.connect(func(d: int, a: String, b: String) -> void: moved.append([d, a, b]))
	bus.notify.connect(func(t: String) -> void: notes.append(t))
	bus.division_order_changed.connect(func(d: int) -> void: order_changes.append(d))

	gs.new_game("germany")
	var de = gs.nation("germany")

	# --- Paths ---
	check_eq(mv.find_path("germany", "berlin", "east_prussia"), ["east_prussia"] as Array[String], "adjacent path")
	check_eq(mv.find_path("germany", "western_germany", "east_prussia"), ["berlin", "east_prussia"] as Array[String],
		"two-hop path through Berlin")
	check(mv.find_path("germany", "berlin", "poland").is_empty(), "no path into neutral Poland")
	check(mv.find_path("germany", "berlin", "north_sea").is_empty(), "no path into a UK naval zone")
	check(mv.find_path("germany", "berlin", "london").is_empty(), "no path to London")
	check(mv.find_path("germany", "berlin", "berlin").is_empty(), "no path to own province")
	check_eq(mv.find_path("uk", "london", "north_sea"), ["north_sea"] as Array[String], "UK may enter its own naval zone")

	var inf = gs.add_division("infantry", "germany", "western_germany")
	check(mv.move_error(inf.id, "north_sea").contains("Naval"), "naval refusal reason")
	check(mv.move_error(inf.id, "poland").contains("not friendly"), "foreign refusal reason")
	check(mv.move_error(inf.id, "western_germany") != "", "already there refused")
	check(not mv.order_move(inf.id, "poland"), "order into foreign province refused")
	check(not inf.is_moving(), "refused order changes nothing")

	# Military access opens land provinces, not seas.
	de.military_access.append("poland")
	check_eq(mv.find_path("germany", "berlin", "ukraine").size(), 0, "access to Poland does not open USSR")
	check_eq(mv.find_path("germany", "berlin", "poland"), ["poland"] as Array[String], "access opens Poland")
	check(mv.find_path("germany", "east_prussia", "hungary").is_empty(), "no access to Hungary yet")
	de.military_access.append("hungary")
	check_eq(mv.find_path("germany", "east_prussia", "hungary"), ["poland", "hungary"] as Array[String],
		"path through Poland with access")
	de.military_access.clear()
	# Hostile adjacent target allowed (step 10 combat), but no passing through enemies.
	de.at_war_with.append("poland")
	check_eq(mv.find_path("germany", "berlin", "poland"), ["poland"] as Array[String], "adjacent enemy province is a valid target")
	check_eq(mv.find_path("germany", "western_germany", "poland"), ["berlin", "poland"] as Array[String], "enemy target after friendly path")
	check(mv.find_path("germany", "berlin", "ukraine").is_empty(), "cannot path through enemy territory")
	de.at_war_with.clear()

	# --- Travel time ---
	var speed: float = mv.division_speed(inf)
	check_eq(speed, 4.0, "infantry speed 4")
	check_eq(mv.hop_days(inf, "east_prussia"), 16.0 / 4.0 * 1.5, "forest, infra 3: 6 days")
	check_eq(mv.hop_days(inf, "berlin"), 16.0 / 4.0 * 1.25 * 0.8, "urban, infra 5: 4 days")
	var arm = gs.add_division("armor", "germany", "berlin")
	check(mv.hop_days(arm, "east_prussia") < mv.hop_days(inf, "east_prussia"), "armor faster than infantry")
	var art = gs.add_division("artillery", "germany", "berlin")
	check(mv.hop_days(art, "east_prussia") > mv.hop_days(inf, "east_prussia"), "artillery slower than infantry")

	# --- Order + daily progress + arrival ---
	moved.clear()
	order_changes.clear()
	check(mv.order_move(inf.id, "east_prussia"), "order western_germany -> east_prussia")
	check_eq(inf.path, ["berlin", "east_prussia"] as Array[String], "path stored")
	check(order_changes.has(inf.id), "division_order_changed emitted")
	check_eq(mv.eta_days(inf), 10.0, "ETA 4 + 6 days")
	tm.advance_days(3)
	check_eq(inf.province, "western_germany", "still on the way after 3 days")
	check(absf(inf.move_progress - 0.75) < 0.001, "progress 75% after 3 of 4 days")
	tm.advance_days(1)
	check_eq(inf.province, "berlin", "arrived in Berlin on day 4")
	check_eq(inf.origin, "western_germany", "origin updated")
	check(moved.size() == 1 and moved[0] == [inf.id, "western_germany", "berlin"], "division_moved(id, from, to)")
	check_eq(inf.path, ["east_prussia"] as Array[String], "remaining path")
	check_eq(inf.move_progress, 0.0, "progress reset on arrival")

	# --- Save round trip mid-move ---
	tm.advance_days(2)
	var data: Dictionary = JSON.parse_string(JSON.stringify(gs.to_dict()))
	gs.load_from_dict(data)
	var inf2 = gs.division(inf.id)
	check(inf2 != null and inf2.path == (["east_prussia"] as Array[String]), "path survives save/load")
	check(absf(inf2.move_progress - 2.0 / 6.0) < 0.001, "progress survives save/load")
	tm.advance_days(3)
	check_eq(inf2.province, "berlin", "not there one day early")
	tm.advance_days(1)
	check_eq(inf2.province, "east_prussia", "arrived in East Prussia")
	check(not inf2.is_moving(), "order finished")

	# --- Stop ---
	order_changes.clear()
	check(mv.order_move(inf2.id, "western_germany"), "order back west")
	tm.advance_days(2)
	mv.stop(inf2.id)
	check(not inf2.is_moving() and inf2.move_progress == 0.0, "stop clears order")
	check_eq(inf2.province, "east_prussia", "stopped division stays put")
	check(order_changes.size() >= 2, "stop emits division_order_changed")

	# --- Province lost on the route: halt ---
	var d2 = gs.add_division("infantry", "germany", "western_germany")
	notes.clear()
	check(mv.order_move(d2.id, "east_prussia"), "order second division")
	gs.province("east_prussia").controller = "poland"
	tm.advance_days(4)
	check_eq(d2.province, "berlin", "first hop still completes")
	tm.advance_days(1)
	check(not d2.is_moving(), "halted when target is no longer friendly")
	check(notes.size() > 0 and String(notes[-1]).contains("halted"), "player notified of halt")
	gs.province("east_prussia").controller = "germany"

	# --- Reroute when an intermediate province is lost ---
	gs.new_game("ussr")
	var su = gs.add_division("infantry", "ussr", "leningrad")
	check(mv.order_move(su.id, "ukraine"), "Leningrad -> Ukraine")
	check_eq(su.path.size(), 2, "2 hops")
	var mid: String = su.path[0]
	gs.province(mid).controller = "germany"
	tm.advance_days(1)
	check(su.is_moving() and su.path[0] != mid, "rerouted around lost " + mid)
	check_eq(su.path[-1], "ukraine", "same destination after reroute")

	# --- Capitulated nations don't move ---
	gs.nation("ussr").capitulated = true
	var p0: float = su.move_progress
	tm.advance_days(2)
	check_eq(su.move_progress, p0, "capitulated nation frozen")
	gs.nation("ussr").capitulated = false

	# --- UI ---
	gs.new_game("germany")
	var game = (load("res://scenes/game/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await process_frame
	var map = game.map_view
	var info = game.hud.info_panel
	var div = gs.add_division("infantry", "germany", "western_germany")
	bus.division_created.emit(div.id)
	map.select_province("western_germany")
	await process_frame
	var btn = info.content.find_child("Division_%d" % div.id, true, false)
	check(btn != null, "garrison button for division")
	btn.emit_signal("pressed")
	await process_frame
	check_eq(info.mode, "division", "division view")
	check_eq(map.selected_divisions, [div.id] as Array[int], "garrison click selects division for orders")
	check(info.content.find_child("MoveHint", true, false) != null, "move hint shown")
	# Click a foreign province: refused, notify, selection kept.
	notes.clear()
	map.click_at(gd.geometry.anchors["poland"])
	check(not div.is_moving(), "click on Poland gives no order")
	check(notes.size() > 0, "refusal reason notified")
	check_eq(map.selected_divisions.size(), 1, "selection kept after refusal")
	# Click a valid destination: order, province selection unchanged.
	map.click_at(gd.geometry.anchors["east_prussia"])
	check(div.is_moving() and div.path[-1] == "east_prussia", "click on East Prussia orders the move")
	check_eq(map.selected_province, "western_germany", "move click does not change province selection")
	await process_frame
	check(info.content.find_child("StopButton", true, false) != null, "stop button shown")
	check(info.content.find_child("Eta", true, false).text.contains("10 days"), "ETA shown")
	check(info.content.find_child("Orders", true, false).text.contains("East Prussia"), "orders text shows target")
	var arrows: Array = map.move_arrows()
	check(arrows.size() == 1 and arrows[0].division == div.id and (arrows[0].points as PackedVector2Array).size() == 3,
		"movement arrow with 3 points")
	check(arrows[0].selected, "arrow highlighted for selected division")
	tm.advance_days(2)
	check(absf(float(map.move_arrows()[0].progress) - 0.5) < 0.001, "arrow progress follows division")
	info.content.find_child("StopButton", true, false).emit_signal("pressed")
	check(not div.is_moving(), "stop button stops the division")
	check(map.move_arrows().is_empty(), "no arrow after stop")
	# Right-click orders too.
	game.camera.focus_on(gd.geometry.anchors["berlin"])
	await process_frame
	await process_frame
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_RIGHT
	ev.pressed = true
	ev.position = game.get_viewport().get_canvas_transform() * gd.geometry.anchors["berlin"]
	ev.global_position = ev.position
	check_eq(map.province_at(map._event_world_pos(ev.position)), "berlin", "event position maps to Berlin")
	map._unhandled_input(ev)   # (headless window may be smaller than the viewport: call the handler directly)
	await process_frame
	check(div.is_moving() and div.path == (["berlin"] as Array[String]), "right-click orders the move")
	# Escape clears the unit selection; then clicks select provinces again.
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	root.push_input(esc)
	await process_frame
	check(map.selected_divisions.is_empty(), "Escape clears unit selection")
	map.click_at(gd.geometry.anchors["east_prussia"])
	check_eq(map.selected_province, "east_prussia", "click selects province again")
	check_eq(div.path, ["berlin"] as Array[String], "no new order without selection")
	# Unit icon click selects all player divisions in the province.
	var icon = null
	for i in map.unit_icons():
		if i.province == "berlin" and i.owner == "germany":
			icon = i
	check(icon != null, "Berlin unit icon")
	if icon:
		map.click_at((icon.rect as Rect2).get_center())
		var n_berlin := 0
		for d in gs.divisions_in("berlin"):
			if d.owner == "germany":
				n_berlin += 1
		check_eq(map.selected_divisions.size(), n_berlin, "icon click selects all Berlin divisions")
		check_eq(map.selected_province, "berlin", "icon click selects Berlin")
		await process_frame
		check_eq(info.mode, "division", "info panel shows selected division")
		check_eq(info.group_size, n_berlin, "group size shown")
		var count: int = map.order_selected_move("east_prussia")
		check_eq(count, n_berlin, "group move order")
	# Province selection clears unit selection.
	map.select_province("berlin")
	check(map.selected_divisions.is_empty(), "province selection clears unit selection")
	# Enemy division selection does not allow orders.
	var pol = gs.division(gs.divisions_in("poland")[0].id)
	bus.division_selected.emit(pol.id)
	check(map.selected_divisions.is_empty(), "foreign division cannot be selected for orders")
	game.queue_free()
	await process_frame
