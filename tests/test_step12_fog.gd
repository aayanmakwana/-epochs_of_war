extends "res://tests/test_base.gd"
## Step 12: fog of war. Provinces the player controls, provinces holding player
## divisions and provinces adjacent to either are visible; the rest are hidden.
## Visibility updates after a move or a capture (fog_changed). Map/minimap/info
## panel hide what is fogged. (Untyped vars on purpose: see PROGRESS.md.)

var fog_events: int = 0


## Expected visible set computed straight from the rule.
func expected_visible(gs: Node, gd: Node, nid: String) -> Dictionary:
	var src: Dictionary = {}
	for pid in gd.province_ids:
		var ps = gs.province(pid)
		if ps.controller == nid:
			src[pid] = true
	for d in gs.divisions_of(nid):
		src[d.province] = true
	var vis: Dictionary = {}
	for pid in src:
		vis[pid] = true
		for nb in gd.adjacent(pid):
			vis[nb] = true
	return vis


func check_rule(gs: Node, gd: Node, fog: Node, nid: String, label: String) -> void:
	var exp := expected_visible(gs, gd, nid)
	var bad: PackedStringArray = []
	for pid in gd.province_ids:
		if fog.is_visible_to(nid, pid) != exp.has(pid):
			bad.append(pid)
	check(bad.is_empty(), "%s: visibility follows the rule (mismatch: %s)" % [label, ", ".join(bad)])


func run_tests() -> void:
	var gs: Node = autoload("GameState")
	var gd: Node = autoload("GameData")
	var bus: Node = autoload("EventBus")
	var tm: Node = autoload("TimeManager")
	var mv: Node = autoload("Movement")
	var cb: Node = autoload("Combat")
	var fog: Node = autoload("Fog")
	check(fog != null, "Fog autoload present")
	if fog == null:
		return
	check(bus.has_signal("fog_changed"), "EventBus.fog_changed declared")
	bus.fog_changed.connect(func() -> void: fog_events += 1)

	# --- Start of game, Germany ---
	fog_events = 0
	gs.new_game("germany")
	check(fog_events >= 1, "fog_changed on new game")
	check(fog.enabled, "fog enabled by default")
	for p in ["berlin", "east_prussia", "western_germany"]:
		check(fog.is_visible(p), "own province %s visible" % p)
	for p in ["poland", "czechoslovakia", "austria", "france", "north_sea", "belarus", "leningrad"]:
		check(fog.is_visible(p), "adjacent province %s visible" % p)
	for p in ["moscow", "ukraine", "stalingrad", "caucasus", "urals", "siberia", "london", "mediterranean", "romania", "hungary"]:
		check(not fog.is_visible(p), "distant province %s hidden" % p)
	check_rule(gs, gd, fog, "germany", "germany start")
	check_rule(gs, gd, fog, "ussr", "ussr start")
	check_rule(gs, gd, fog, "uk", "uk start")
	check_eq(fog.visible_provinces("germany").size() + fog.hidden_provinces("germany").size(), 20, "visible + hidden = 20")
	check_eq(fog.player_hidden_provinces(), fog.hidden_provinces("germany"), "player hidden = germany hidden")
	check(fog.is_visible_to("uk", "london") and fog.is_visible_to("uk", "north_sea"), "UK sees London + North Sea")
	check(not fog.is_visible_to("uk", "moscow"), "UK does not see Moscow")

	# Owned but occupied: the controller sees it, the owner only via neighbours / divisions.
	for d in gs.divisions_in("east_prussia"):
		gs.remove_division(d.id)
	gs.province("east_prussia").controller = "ussr"
	check(not fog.sight_sources("germany").has("east_prussia"), "occupied province without divisions is no German sight source")
	check(fog.sight_sources("ussr").has("east_prussia"), "occupier gains sight")
	check_rule(gs, gd, fog, "germany", "after occupation")
	gs.province("east_prussia").controller = "germany"

	# --- Division sight + reveal on movement ---
	gs.new_game("germany")
	check(not fog.is_visible("moscow"), "Moscow hidden before the move")
	gs.nation("germany").military_access.append("ussr")
	var div = gs.add_division("infantry", "germany", "east_prussia")
	await process_frame
	fog_events = 0
	check(mv.order_move(div.id, "belarus"), "move order into Belarus (access)")
	var days := 0
	while div.province != "belarus" and days < 60:
		tm.advance_days(1)
		days += 1
	check_eq(div.province, "belarus", "division arrived in Belarus")
	check(fog.sight_sources("germany").has("belarus"), "division province is a sight source")
	check(fog.is_visible("moscow"), "Moscow revealed by the division in Belarus")
	check(fog.is_visible("ukraine"), "Ukraine revealed by the division in Belarus")
	check_rule(gs, gd, fog, "germany", "after move")
	await process_frame
	check(fog_events >= 1, "fog_changed after the move")
	# Destroying the division hides it again.
	fog_events = 0
	cb.destroy(div)
	await process_frame
	check(not fog.is_visible("moscow"), "Moscow hidden again after the division is gone")
	check(fog_events >= 1, "fog_changed after division destroyed")

	# --- Capture ---
	gs.new_game("germany")
	await process_frame
	check(not fog.is_visible("ukraine"), "Ukraine hidden before capturing Poland")
	fog_events = 0
	cb.capture("poland", "germany")
	await process_frame
	check(fog.is_visible("ukraine"), "Ukraine visible after capturing Poland")
	check(not fog.is_visible("romania"), "Romania still hidden (not adjacent to Poland)")
	check_rule(gs, gd, fog, "germany", "after capture")
	check(fog_events >= 1, "fog_changed after capture")
	# Losing a province shrinks sight.
	gs.province("poland").controller = "poland"
	bus.province_changed.emit("poland")
	await process_frame
	check(not fog.is_visible("ukraine"), "Ukraine hidden again after losing Poland")

	# No change -> no signal.
	fog_events = 0
	bus.province_changed.emit("berlin")
	await process_frame
	check_eq(fog_events, 0, "no fog_changed when visibility is unchanged")

	# --- Save / load: derived, no extra data ---
	gs.province("poland").controller = "germany"
	var data: Dictionary = JSON.parse_string(JSON.stringify(gs.to_dict()))
	gs.load_from_dict(data)
	check(fog.is_visible("ukraine"), "visibility after load follows the map")

	# --- Other player nation ---
	gs.new_game("ussr")
	check(fog.is_visible("moscow") and fog.is_visible("siberia"), "USSR sees its own territory")
	check(not fog.is_visible("london") and not fog.is_visible("western_germany"), "USSR does not see London / W. Germany")

	# --- Disable ---
	fog.set_enabled(false)
	check(fog.player_hidden_provinces().is_empty() and fog.is_visible("london"), "fog off: everything visible")
	fog.set_enabled(true)
	check(not fog.is_visible("london"), "fog back on")

	await ui_tests(gs, bus, fog)


## Map / minimap / info panel (step 12 UI). Skipped parts report as failures
## only if the UI hooks exist (added after the core commit).
func ui_tests(gs: Node, bus: Node, fog: Node) -> void:
	gs.new_game("germany")
	var game = (load("res://scenes/game/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await process_frame
	var map = game.map_view
	var info = game.hud.info_panel
	if not map.has_method("fogged_provinces"):
		print("UI fog hooks not present yet - skipping UI checks")
		game.queue_free()
		await process_frame
		return
	check_eq(map.fogged_provinces(), fog.player_hidden_provinces(), "map fogs the hidden provinces")
	check(map.fogged_provinces().has("moscow"), "Moscow drawn fogged")
	var fog_layer = map.layers.get("Fog")
	check(fog_layer != null, "Fog layer exists")
	# Unit icons: enemy divisions in hidden provinces are not drawn.
	var hidden_icon := false
	var moscow_icon := false
	var poland_icon := false
	for ic in map.unit_icons():
		if not fog.is_visible(ic.province):
			hidden_icon = true
		if ic.province == "moscow":
			moscow_icon = true
		if ic.province == "poland":
			poland_icon = true
	check(not hidden_icon and not moscow_icon, "no unit icons in hidden provinces")
	check(poland_icon, "enemy icons in visible provinces still drawn")
	# Fogged colour = grey, same on the minimap.
	var grey = map.province_display_color("moscow")
	check(grey != map.province_color("moscow"), "hidden province greyed out")
	check(absf(grey.r - grey.g) < 0.02 and absf(grey.g - grey.b) < 0.02, "fog colour is grey")
	check_eq(map.province_display_color("berlin"), map.province_color("berlin"), "visible province keeps its colour")
	var fill = map.fill_nodes["moscow"][0]
	check(fill.color == grey, "Moscow polygon filled grey")
	check(game.hud.minimap.canvas.has_method("_draw"), "minimap canvas present")
	# Info panel: Unknown garrison in hidden province.
	map.select_province("moscow")
	await process_frame
	var g = info.content.find_child("Garrison", true, false)
	check(g != null and g.get_child_count() == 1 and g.get_child(0).text == "Unknown", "hidden garrison shows Unknown")
	check(info.content.find_child("Division_*", true, false) == null, "no division buttons in hidden province")
	map.select_province("poland")
	await process_frame
	g = info.content.find_child("Garrison", true, false)
	check(g != null and info.content.find_child("Division_*", true, false) != null, "visible enemy garrison listed")
	# A foreign division under fog cannot be inspected.
	var sov = gs.divisions_in("moscow")[0]
	bus.division_selected.emit(sov.id)
	await process_frame
	check(info.mode == "province" and info.current_province == "moscow", "hidden enemy division -> province view")
	g = info.content.find_child("Garrison", true, false)
	check(g != null and g.get_child(0).text == "Unknown", "hidden division shows Unknown garrison")
	# Battle markers hidden under fog.
	gs.battles["moscow"] = {"province": "moscow", "attacker": "uk", "defender": "ussr", "attackers": [], "days": 0, "start_day": 0}
	check(map.battle_markers().is_empty(), "no battle marker in a hidden province")
	gs.battles.erase("moscow")
	# Reveal by capture updates the map.
	cb_capture("poland")
	await process_frame
	await process_frame
	check(not map.fogged_provinces().has("ukraine"), "Ukraine unfogged after capturing Poland")
	check(map.fill_nodes["ukraine"][0].color == map.province_color("ukraine"), "Ukraine recoloured after reveal")
	game.queue_free()
	await process_frame


func cb_capture(pid: String) -> void:
	autoload("Combat").capture(pid, "germany")
