extends "res://tests/test_base.gd"
## Step 19: game flow tests.
## - new_game sets the correct player nation.
## - game_over fires (with 'victory') when the player's enemy capital is captured.
## - game_over fires (with 'defeat') when the player's own capital is captured.


func run_tests() -> void:
	var gs: Node = autoload("GameState")
	var eb: Node = autoload("EventBus")
	var gd: Node = autoload("GameData")
	var main: Node = autoload("Main")
	autoload("AI").enabled = false

	# ---- new_game sets player nation -----------------------------------------
	gs.new_game("germany")
	check_eq(gs.player_nation, "germany", "new_game('germany') sets player_nation to germany")

	gs.new_game("ussr")
	check_eq(gs.player_nation, "ussr", "new_game('ussr') sets player_nation to ussr")

	gs.new_game("uk")
	check_eq(gs.player_nation, "uk", "new_game('uk') sets player_nation to uk")

	# ---- game_over fires 'victory' when enemy capital is captured ------------
	gs.new_game("germany")
	gs.game_over = false

	var results_received: Array = []
	var conn := func(r: String) -> void: results_received.append(r)
	eb.game_over.connect(conn)

	# Simulate capturing Moscow (USSR capital) by Germany.
	# Set Moscow controller to germany so the check sees no USSR capital remaining.
	var moscow_ps: Object = gs.province("moscow")
	if moscow_ps != null:
		moscow_ps.controller = "germany"

	# Emit province_captured: moscow captured by germany, was ussr.
	eb.province_captured.emit("moscow", "germany", "ussr")
	await process_frame

	check(results_received.size() > 0, "game_over emitted after enemy capital captured")
	if results_received.size() > 0:
		check_eq(results_received[0], "victory", "result is 'victory' when enemy capital falls")

	eb.game_over.disconnect(conn)

	# ---- game_over fires 'defeat' when player capital is captured ------------
	gs.new_game("germany")
	gs.game_over = false

	var results2: Array = []
	var conn2 := func(r: String) -> void: results2.append(r)
	eb.game_over.connect(conn2)

	# Simulate capturing Berlin (Germany capital) by USSR.
	var berlin_ps: Object = gs.province("berlin")
	if berlin_ps != null:
		berlin_ps.controller = "ussr"

	eb.province_captured.emit("berlin", "ussr", "germany")
	await process_frame

	check(results2.size() > 0, "game_over emitted after player capital captured")
	if results2.size() > 0:
		check_eq(results2[0], "defeat", "result is 'defeat' when player capital falls")

	eb.game_over.disconnect(conn2)

	# ---- no game_over when a non-capital province is captured ----------------
	gs.new_game("germany")
	gs.game_over = false

	var results3: Array = []
	var conn3 := func(r: String) -> void: results3.append(r)
	eb.game_over.connect(conn3)

	# western_germany is not a capital.
	eb.province_captured.emit("western_germany", "ussr", "germany")
	await process_frame

	check(results3.size() == 0, "no game_over when non-capital province captured")
	eb.game_over.disconnect(conn3)

	# ---- Main autoload has required screen methods ---------------------------
	check(main != null, "Main autoload exists")
	if main:
		check(main.has_method("show_start_screen"), "Main.show_start_screen exists")
		check(main.has_method("show_nation_select"), "Main.show_nation_select exists")
		check(main.has_method("start_game_screen"), "Main.start_game_screen exists")
		check(main.has_method("show_end_screen"), "Main.show_end_screen exists")

	# ---- start_screen scene loads and has expected nodes --------------------
	var ss_packed: PackedScene = load("res://scenes/start_screen.tscn")
	check(ss_packed != null, "start_screen.tscn loads")
	if ss_packed:
		var ss: Node = ss_packed.instantiate()
		root.add_child(ss)
		await process_frame
		check(ss.get_node_or_null("VBox/NewGameButton") != null, "start_screen has NewGameButton")
		check(ss.get_node_or_null("VBox/LoadGameButton") != null, "start_screen has LoadGameButton")
		ss.queue_free()
		await process_frame

	# ---- nation_select scene loads and has expected nodes -------------------
	var ns_packed: PackedScene = load("res://scenes/nation_select.tscn")
	check(ns_packed != null, "nation_select.tscn loads")
	if ns_packed:
		var ns: Node = ns_packed.instantiate()
		root.add_child(ns)
		await process_frame
		check(ns.get_node_or_null("VBox/Title") != null, "nation_select has Title")
		check(ns.get_node_or_null("VBox/Buttons") != null, "nation_select has Buttons")
		check(ns.get_node_or_null("VBox/StartButton") != null, "nation_select has StartButton")
		ns.queue_free()
		await process_frame

	# ---- end_screen scene loads and has expected nodes ----------------------
	var es_packed: PackedScene = load("res://scenes/end_screen.tscn")
	check(es_packed != null, "end_screen.tscn loads")
	if es_packed:
		var es: Node = es_packed.instantiate()
		root.add_child(es)
		await process_frame
		check(es.get_node_or_null("VBox/ResultLabel") != null, "end_screen has ResultLabel")
		check(es.get_node_or_null("VBox/StatsLabel") != null, "end_screen has StatsLabel")
		check(es.get_node_or_null("VBox/MainMenuButton") != null, "end_screen has MainMenuButton")
		# Test show_result without crashing.
		gs.new_game("germany")
		if es.has_method("show_result"):
			es.show_result("victory")
		es.queue_free()
		await process_frame
