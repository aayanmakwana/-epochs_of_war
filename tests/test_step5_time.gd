extends "res://tests/test_base.gd"
## Step 5: time system. TimeManager clock (pause, 4 speeds, hour/day/month
## signals, frame cap, game over), Simulation tick dispatcher, top bar
## controls + date display, keyboard shortcuts.
## (Untyped vars on purpose: see PROGRESS.md "Tests and autoload names".)

var speed_events: Array = []
var log: Array = []


func run_tests() -> void:
	var gs: Node = autoload("GameState")
	var bus: Node = autoload("EventBus")
	var tm: Node = autoload("TimeManager")
	var sim: Node = autoload("Simulation")
	check(tm != null, "TimeManager autoload present")
	check(sim != null, "Simulation autoload present")
	if tm == null or sim == null:
		return
	var names: Array = []
	for c in root.get_children():
		names.append(String(c.name))
	check(names.find("Simulation") > names.find("GameState") and names.find("TimeManager") > names.find("Simulation"),
		"autoload order GameState < Simulation < TimeManager")
	check_eq(tm.speeds.map(func(x) -> float: return float(x)), [1.0, 2.0, 3.0, 5.0], "speeds 1x 2x 3x 5x from rules")
	check(tm.paused and tm.speed_index == 0, "starts paused at speed 1")

	bus.speed_changed.connect(func(i: int, p: bool) -> void: speed_events.append([i, p]))
	bus.hour_passed.connect(func(h: int) -> void: log.append("hour:%d" % h))
	bus.day_passed.connect(func(d: int) -> void: log.append("day:%d" % d))
	bus.month_passed.connect(func(y: int, m: int) -> void: log.append("month:%d-%d" % [y, m]))

	# --- New game resets the clock state ---
	tm.set_speed(3, true)
	speed_events.clear()
	gs.new_game("germany")
	check(tm.paused and tm.speed_index == 0, "new game -> paused, speed 1")
	check(speed_events.size() >= 1 and speed_events[-1] == [0, true], "speed_changed emitted on new game")
	check_eq(gs.day_index, 0, "starts day 0")
	check_eq(gs.hour, 0, "starts hour 0")

	# --- Paused: nothing moves ---
	tm._process(5.0)
	for i in 5:
		await process_frame
	check(gs.day_index == 0 and gs.hour == 0, "paused clock does not advance")

	# --- Pause / speed API ---
	speed_events.clear()
	tm.toggle_pause()
	check(not tm.paused and speed_events[-1] == [0, false], "toggle_pause resumes + emits")
	tm.toggle_pause()
	check(tm.paused and speed_events[-1] == [0, true], "toggle_pause pauses + emits")
	tm.set_speed(2)
	check(tm.speed_index == 2 and tm.paused and speed_events[-1] == [2, true], "set_speed keeps pause")
	tm.set_speed(99)
	check_eq(tm.speed_index, 3, "set_speed clamps high")
	tm.set_speed(-5)
	check_eq(tm.speed_index, 0, "set_speed clamps low")
	tm.faster()
	tm.faster()
	check_eq(tm.speed_index, 2, "faster")
	tm.slower()
	check_eq(tm.speed_index, 1, "slower")
	tm.set_speed(0, true)
	check(not tm.paused and tm.speed_index == 0, "set_speed(unpause=true) resumes")
	tm.pause()
	check(tm.paused, "pause()")
	tm.resume()
	check(not tm.paused, "resume()")
	tm.pause()

	# --- Clock rate: 1x = 1 real second per day (rules.seconds_per_day_at_1x) ---
	check_eq(tm.hours_per_second(), 24.0, "1x = 24 hours per second")
	tm.set_speed(0, true)
	log.clear()
	tm._process(0.125)
	check_eq(gs.hour, 3, "0.125 s at 1x = 3 hours")
	check_eq(log, ["hour:1", "hour:2", "hour:3"], "hour_passed each hour")
	for i in 7:
		tm._process(0.125)
	check(gs.day_index == 1 and gs.hour == 0, "1 s at 1x = 1 day")
	check(log.count("day:1") == 1 and log.find("day:1") == log.find("hour:0") + 1, "day_passed once, after hour_passed(0)")
	check_eq(gs.date_string(), "2 January 1936", "date advanced")
	# fractional hours carry over
	tm._process(0.02)   # 0.48 h
	check_eq(gs.hour, 0, "partial hour not applied yet")
	tm._process(0.02)   # 0.96 h
	tm._process(0.002)  # 1.008 h
	check_eq(gs.hour, 1, "partial hours accumulate")

	# Relative speeds: same real time, hours proportional to 1:2:3:5
	var mults := [1, 2, 3, 5]
	for si in 4:
		tm.set_speed(si, true)
		var before: int = gs.day_index * 24 + gs.hour
		for i in 8:
			tm._process(0.125)
		var after: int = gs.day_index * 24 + gs.hour
		check_eq(after - before, 24 * mults[si], "1 s at speed %d = %d days" % [si + 1, mults[si]])

	# Frame cap: a huge frame simulates at most max_hours_per_frame
	tm.set_speed(3, true)
	var b2: int = gs.day_index * 24 + gs.hour
	tm._process(10.0)
	check_eq(gs.day_index * 24 + gs.hour - b2, tm.max_hours_per_frame, "long frame capped at max_hours_per_frame")
	tm.pause()

	# --- Month / leap year ---
	gs.new_game("germany")
	log.clear()
	tm.advance_days(31)
	check_eq(gs.date_string(), "1 February 1936", "advance_days(31)")
	check(log.has("month:1936-2"), "month_passed(1936, 2) on 1 February")
	check_eq(log.count("day:%d" % 31), 1, "day_passed(31)")
	var day_count := 0
	for e in log:
		if String(e).begins_with("day:"):
			day_count += 1
	check_eq(day_count, 31, "31 day_passed signals")
	tm.advance_days(29)
	check_eq(gs.date_string(), "1 March 1936", "1936 is a leap year (29 Feb)")
	tm.advance_hours(5)
	check_eq(gs.hour, 5, "advance_hours")
	check(tm.paused, "advance_* does not unpause")

	# --- Simulation dispatcher ---
	var order: Array = []
	sim.register_daily("t_late", func() -> void: order.append("late"), 50)
	sim.register_daily("t_early", func() -> void: order.append("early"), 5)
	sim.register_daily("t_mid", func() -> void: order.append("mid:%d" % gs.day_index), 20)
	sim.register_hourly("t_hour", func() -> void: order.append("h"), 1)
	check(Array(sim.daily_systems()).slice(-3) == ["t_early", "t_mid", "t_late"] or
		(sim.daily_systems().find("t_early") < sim.daily_systems().find("t_mid")
		and sim.daily_systems().find("t_mid") < sim.daily_systems().find("t_late")), "daily systems sorted by order")
	var seen_in_signal: Array = []
	var cb := func(_d: int) -> void: seen_in_signal.append(order.duplicate())
	bus.day_passed.connect(cb)
	gs.hour = 23
	var days_before: int = sim.days_run
	tm.advance_hours(1)
	bus.day_passed.disconnect(cb)
	check_eq(order, ["h", "early", "mid:%d" % gs.day_index, "late"], "hourly then daily systems in order, with new date")
	check(seen_in_signal.size() == 1 and seen_in_signal[0].size() == 4, "systems ran before day_passed was emitted")
	check_eq(sim.days_run - days_before, 1, "days_run counter")
	sim.register_daily("t_mid", func() -> void: order.append("mid2"), 1)
	check_eq(sim.daily_systems().count("t_mid"), 1, "re-register replaces")
	order.clear()
	tm.advance_hours(24)
	check_eq(order.filter(func(x) -> bool: return x != "h"), ["mid2", "early", "late"], "replaced system uses new order")
	check_eq(order.count("h"), 24, "hourly system 24x per day")
	for n in ["t_late", "t_early", "t_mid", "t_hour"]:
		sim.unregister(n)
	check(not sim.daily_systems().has("t_late") and not sim.hourly_systems().has("t_hour"), "unregister")
	order.clear()
	tm.advance_hours(24)
	check(order.is_empty(), "unregistered systems no longer run")

	# --- Game over stops the clock ---
	tm.set_speed(0, true)
	gs.game_over = true
	var b3: int = gs.day_index * 24 + gs.hour
	tm._process(1.0)
	tm.advance_hours(10)
	check_eq(gs.day_index * 24 + gs.hour, b3, "clock frozen when game over")
	bus.game_over.emit("victory")
	check(tm.paused, "game_over signal pauses")
	gs.game_over = false

	# --- time_played counts real time while active ---
	var tp: float = gs.time_played
	tm._process(0.5)
	check(gs.time_played >= tp + 0.5 - 0.0001, "time_played accumulates (paused too)")

	# --- Top bar wired to the TimeManager ---
	root.size = Vector2i(1920, 1080)
	gs.new_game("germany")
	tm.set_speed(1)   # before the HUD exists: bar must sync on _ready
	var game = (load("res://scenes/game/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	for i in 3:
		await process_frame
	tm.pause()
	var top = game.hud.top_bar
	tm.set_speed(1)
	check(top.speed_buttons[1].button_pressed and top.paused, "top bar mirrors TimeManager state")
	check_eq(top.pause_button.text, "PLAY", "pause button shows PLAY when paused")
	top.pause_button.pressed.emit()
	check(not tm.paused and not top.paused, "pause button resumes clock")
	check_eq(top.pause_button.text, "PAUSE", "pause button shows PAUSE when running")
	top.speed_buttons[3].pressed.emit()
	check(tm.speed_index == 3 and top.speed_buttons[3].button_pressed and not top.speed_buttons[1].button_pressed,
		"speed button sets TimeManager speed")
	top.pause_button.pressed.emit()
	check(tm.paused and top.paused, "pause button pauses clock")
	tm.advance_hours(7)
	check_eq(top.time_label.text, "07:00", "time label follows hour_passed")
	tm.advance_hours(17)
	check_eq(top.date_label.text, "2 January 1936", "date label follows day_passed")

	# Real frames: running clock advances on its own
	tm.set_speed(3, true)
	var b4: int = gs.day_index * 24 + gs.hour
	await create_timer(0.5).timeout
	var adv: int = gs.day_index * 24 + gs.hour - b4
	check(adv >= 24 and adv <= 5 * 24 * 2, "clock advances in real time at 5x (%d hours in ~0.5 s)" % adv)
	check_eq(top.date_label.text, gs.date_string(), "date label up to date while running")
	tm.pause()
	var b5: int = gs.day_index * 24 + gs.hour
	for i in 10:
		await process_frame
	check_eq(gs.day_index * 24 + gs.hour, b5, "pause stops the real-time clock")

	# --- Keyboard shortcuts ---
	tm.set_speed(0)
	_key(KEY_SPACE)
	check(not tm.paused, "Space resumes")
	_key(KEY_SPACE)
	check(tm.paused, "Space pauses")
	_key(KEY_3)
	check_eq(tm.speed_index, 2, "key 3 -> speed 3")
	_key(KEY_EQUAL)
	check_eq(tm.speed_index, 3, "+ -> faster")
	_key(KEY_MINUS)
	_key(KEY_MINUS)
	check_eq(tm.speed_index, 1, "- -> slower")
	check(top.speed_buttons[1].button_pressed, "top bar follows keyboard speed")
	_key(KEY_P)
	check(not tm.paused, "P toggles pause")
	tm.pause()

	game.queue_free()
	await process_frame


func _key(code: Key) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = true
	root.push_input(e)
	var up := InputEventKey.new()
	up.keycode = code
	up.physical_keycode = code
	up.pressed = false
	root.push_input(up)
