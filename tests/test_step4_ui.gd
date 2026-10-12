extends "res://tests/test_base.gd"
## Step 4: UI shell. Top bar, left info panel, right tabbed panel, minimap,
## HUD mouse handling, camera drag release over UI.
## (Untyped vars on purpose: see PROGRESS.md "Tests and autoload names".)


func run_tests() -> void:
	var gd: Node = autoload("GameData")
	var gs: Node = autoload("GameState")
	var bus: Node = autoload("EventBus")
	root.size = Vector2i(1920, 1080)
	gs.new_game("germany")

	var game = (load("res://scenes/game/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	for i in 3:
		await process_frame
	var hud = game.get_node_or_null("UI/HUD")
	check(hud != null, "HUD node under UI")
	check(hud.mouse_filter == Control.MOUSE_FILTER_IGNORE, "HUD root ignores mouse")
	check(hud.theme != null, "HUD theme set")
	var top = hud.top_bar
	var info = hud.info_panel
	var side = hud.side_panel
	var mini = hud.minimap
	check(top != null and info != null and side != null and mini != null, "all four HUD parts exist")
	for c in [top, info, side, mini]:
		check(c.mouse_filter == Control.MOUSE_FILTER_STOP, c.name + " blocks mouse from the map")

	# --- Top bar ---
	var vp: Vector2 = hud.get_viewport_rect().size
	check_eq(vp, Vector2(1920, 1080), "viewport 1920x1080")
	var tr: Rect2 = top.get_global_rect()
	check(tr.position.y == 0 and absf(tr.size.x - vp.x) < 1.0, "top bar spans the top edge")
	check(tr.size.y >= 50 and tr.size.y <= 70, "top bar height ~56 (got %s)" % tr.size.y)
	check_eq(top.date_label.text, "1 January 1936", "top bar date")
	check_eq(top.nation_label.text, "Germany", "nation name")
	check_eq(top.flag_view.flag.get("layout", ""), "horizontal", "German flag passed to flag view")
	var p = gs.player()
	check_eq(top.resource_text("manpower"), "900.0K", "manpower shown")
	check_eq(top.resource_text("oil"), "200", "oil shown")
	check_eq(top.resource_text("steel"), "300", "steel shown")
	check_eq(top.resource_text("factories"), str(gs.factory_count("germany")), "factories shown")
	p.stockpile["oil"] = 1234.0
	bus.nation_changed.emit("germany")
	check_eq(top.resource_text("oil"), "1,234", "oil refresh on nation_changed")
	gs.province("poland").controller = "germany"
	bus.province_changed.emit("poland")
	check_eq(top.resource_text("factories"), str(gs.factory_count("germany")), "factories refresh on province_changed")
	gs.province("poland").controller = "poland"
	bus.province_changed.emit("poland")
	gs.day_index += 31
	bus.day_passed.emit(gs.day_index)
	check_eq(top.date_label.text, "1 February 1936", "date refresh on day_passed")
	gs.day_index -= 31
	bus.day_passed.emit(gs.day_index)
	check_eq(top.speed_buttons.size(), 4, "4 speed buttons")
	check(top.paused and top.pause_button.text == "PLAY", "starts paused")
	bus.speed_changed.emit(2, false)
	check(not top.paused and top.speed_buttons[2].button_pressed and not top.speed_buttons[0].button_pressed, "speed_changed mirrored")
	bus.speed_changed.emit(0, true)

	# --- Left info panel ---
	check(not info.visible, "info panel hidden at start")
	game.map_view.select_province("berlin")
	await process_frame
	check(info.visible and info.mode == "province", "province click opens info panel")
	var title = info.content.find_child("Title", true, false)
	check(title != null and title.text == "Berlin", "province title")
	check_eq(info.value_text("Type"), "Urban", "terrain shown")
	check_eq(info.value_text("Factories"), str(gs.province("berlin").factories), "factories shown")
	check_eq(info.value_text("Steel"), "2", "resources shown")
	check(info.content.find_child("Owner", true, false).text == "Germany", "owner shown")
	var garrison = info.content.find_child("Garrison", true, false)
	var n_divs: int = gs.divisions_in("berlin").size()
	check(n_divs > 0 and garrison.get_child_count() == n_divs, "garrison lists %d divisions" % n_divs)
	var gr: Rect2 = info.get_global_rect()
	check(gr.position.x < 20 and gr.position.y >= tr.end.y, "info panel at left under the top bar")
	# Division view via garrison button
	var btn = garrison.get_child(0)
	btn.emit_signal("pressed")
	await process_frame
	check_eq(info.mode, "division", "garrison button opens division view")
	check(info.value_text("Attack") != "" and info.value_text("HP") != "", "division stats shown")
	check(info.content.find_child("Orders", true, false).text.begins_with("Holding"), "orders shown")
	info.content.find_child("BackToProvince", true, false).emit_signal("pressed")
	check_eq(info.mode, "province", "back button returns to province")
	# Naval zone: no buildings section
	game.map_view.select_province("north_sea")
	check(info.content.find_child("BuildingGrid", true, false) == null, "naval zone has no buildings")
	# Occupied
	gs.province("poland").controller = "germany"
	game.map_view.select_province("poland")
	check(info.content.find_child("Occupied", true, false) != null, "occupied note")
	gs.province("poland").controller = "poland"
	bus.province_changed.emit("poland")
	await process_frame
	check(info.content.find_child("Occupied", true, false) == null, "panel rebuilds on province_changed")
	# Close button clears map selection too
	info.content.find_child("Close", true, false).emit_signal("pressed")
	check(not info.visible, "close hides panel")
	check_eq(game.map_view.selected_province, "", "close clears map selection")
	game.map_view.select_province("moscow")
	game.map_view.click_at(Vector2(-500, -500))
	check(not info.visible, "off-map click hides panel")
	# Destroyed division falls back to province view
	var d = gs.add_division("infantry", "germany", "berlin")
	bus.division_selected.emit(d.id)
	check_eq(info.mode, "division", "division_selected opens division view")
	gs.remove_division(d.id)
	bus.division_destroyed.emit(d.id)
	await process_frame
	check_eq(info.mode, "province", "destroyed division -> province view")
	info.close()

	# --- Right tabbed panel ---
	check_eq(side.tabs.get_tab_count(), 3, "3 tabs")
	for i in 3:
		check_eq(side.tabs.get_tab_title(i), ["Production", "Research", "Diplomacy"][i], "tab %d title" % i)
	check(side.tab_content("Production").get_node_or_null("ProductionPanel") != null, "Production tab filled (step 6)")
	for t in ["Diplomacy"]:   # Production (step 6) and Research (step 7) are filled
		check(side.tab_content(t) != null and side.tab_content(t).get_node_or_null("Placeholder") != null, t + " tab has placeholder")
	side.select_tab("Research")
	check_eq(side.current_tab_name(), "Research", "select_tab")
	side.clear_tab("Diplomacy")
	await process_frame
	check_eq(side.tab_content("Diplomacy").get_child_count(), 0, "clear_tab empties tab")
	var sr: Rect2 = side.get_global_rect()
	check(absf(sr.end.x - (vp.x - 8)) < 2.0 and sr.position.y >= tr.end.y, "side panel at right under the top bar")
	side.set_collapsed(true)
	await process_frame
	check(not side.tabs.visible and side.get_global_rect().size.y < 120, "collapse hides tabs")
	side.set_collapsed(false)
	await process_frame
	check(side.tabs.visible, "expand shows tabs")

	# --- Minimap ---
	var mr: Rect2 = mini.get_global_rect()
	check(absf(mr.end.x - (vp.x - 8)) < 2.0 and absf(mr.end.y - (vp.y - 8)) < 2.0, "minimap bottom-right")
	check(mr.position.y >= side.get_global_rect().end.y, "minimap below side panel (no overlap)")
	var b: Rect2 = gd.geometry.bounds()
	var c_local: Vector2 = mini.to_local_point(b.get_center())
	check(Rect2(Vector2.ZERO, mini.canvas.size).has_point(c_local), "map centre inside minimap")
	check(mini.to_world(c_local).distance_to(b.get_center()) < 0.5, "minimap transform round-trips")
	var corner: Vector2 = mini.to_local_point(b.end)
	check(corner.x <= mini.canvas.size.x + 0.5 and corner.y <= mini.canvas.size.y + 0.5, "whole map fits")
	var target: Vector2 = gd.geometry.anchors["moscow"]
	mini.focus_local(mini.to_local_point(target))
	check(game.camera.position.distance_to(target) < 101.0, "minimap click focuses camera")
	var vr: Rect2 = mini.viewport_rect_local()
	check(vr.has_point(mini.to_local_point(game.camera.position)), "viewport rect contains camera centre")
	game.camera.set_zoom_level(game.camera.max_zoom)
	var vr2: Rect2 = mini.viewport_rect_local()
	check(vr2.size.x < vr.size.x, "viewport rect shrinks when zooming in")
	# Click via GUI input event on the canvas
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = mini.to_local_point(gd.geometry.anchors["london"])
	mini.canvas._gui_input(ev)
	check(game.camera.position.distance_to(gd.geometry.anchors["london"]) < 101.0, "minimap mouse press moves camera")

	# --- Mouse routing: clicks on panels don't reach the map ---
	game.map_view.clear_selection()
	game.camera.focus_on(b.get_center())
	game.camera.set_zoom_level(1.0)
	await process_frame
	var click_pos: Vector2 = mr.get_center()
	_click(click_pos)
	await process_frame
	check_eq(game.map_view.selected_province, "", "click on minimap does not select a province")
	# Click in the middle of the screen (map area) does reach the map.
	var mid: Vector2 = vp * 0.5
	var world_mid: Vector2 = game.camera.position
	var expected: String = game.map_view.province_at(world_mid)
	_click(mid)
	await process_frame
	check(expected != "" and game.map_view.selected_province == expected, "click on map area selects " + expected)

	# --- Camera drag released over a panel ends the drag ---
	var cam = game.camera
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = mid
	root.push_input(press)
	var mv := InputEventMouseMotion.new()
	mv.position = mr.get_center()
	mv.relative = Vector2(40, 0)
	root.push_input(mv)
	var rel := InputEventMouseButton.new()
	rel.button_index = MOUSE_BUTTON_LEFT
	rel.pressed = false
	rel.position = mr.get_center()
	root.push_input(rel)
	await process_frame
	check_eq(cam._drag_button, 0, "drag ended even though release was over the minimap")
	var before: Vector2 = cam.position
	var mv2 := InputEventMouseMotion.new()
	mv2.position = mid
	mv2.relative = Vector2(50, 0)
	root.push_input(mv2)
	await process_frame
	check(cam.position.distance_to(before) < 0.01, "no panning after drag ended")

	# Fresh game refresh
	gs.new_game("ussr")
	await process_frame
	check_eq(top.nation_label.text, "Soviet Union", "game_state_ready refreshes nation")
	check(not info.visible, "info panel closed on new game")

	game.queue_free()
	await process_frame


func _click(pos: Vector2) -> void:
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = pos
		ev.global_position = pos
		root.push_input(ev)
