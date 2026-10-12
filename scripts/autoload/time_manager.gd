extends Node
## Game clock (autoload "TimeManager").
##
## Real time with pause. While a game is active and not paused, the clock
## advances in whole in-game hours. At speed multiplier 1 one in-game day takes
## rules.seconds_per_day_at_1x real seconds; speeds come from rules.speeds
## (default [1, 2, 3, 5] = the doc's 1x / 2x / 3x / 5x).
##
## Every hour: GameState.hour/day_index advance, Simulation.run_hour() runs,
## then EventBus.hour_passed. On a new day: Simulation.run_day(), then
## EventBus.day_passed (and EventBus.month_passed on the 1st of a month).
## Simulation runs before the signal so UI listeners see updated state.
##
## Any change to speed or pause emits EventBus.speed_changed(index, paused).
## A new game / load resets to paused at speed 0 (game_state_ready).
##
## Keyboard (only while a game is active): Space / P = pause toggle,
## 1-4 = speed, + / - (also numpad) = faster / slower.

var speeds: Array = [1, 2, 3, 5]
var speed_index: int = 0
var paused: bool = true
## Real seconds per in-game day at multiplier 1.
var seconds_per_day: float = 1.0
## Upper bound on hours simulated in one frame (protects against frame spikes).
var max_hours_per_frame: int = 48
## Fraction of an in-game hour carried over between frames.
var _accum_hours: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var s: Array = GameData.rule("speeds", speeds)
	if not s.is_empty():
		speeds = s.duplicate()
	seconds_per_day = maxf(0.001, float(GameData.rule("seconds_per_day_at_1x", 1.0)))
	max_hours_per_frame = maxi(1, int(GameData.rule("max_hours_per_frame", 48)))
	EventBus.game_state_ready.connect(_on_game_state_ready)
	EventBus.game_over.connect(func(_r: String) -> void: set_paused(true))
	_emit()


func _on_game_state_ready() -> void:
	paused = true
	speed_index = 0
	_accum_hours = 0.0
	_emit()


# --- Public API ---------------------------------------------------------------

func is_running() -> bool:
	return GameState.active and not GameState.game_over and not paused


func speed_multiplier() -> float:
	return float(speeds[speed_index])


## In-game hours per real second at the current speed (ignores pause).
func hours_per_second() -> float:
	return 24.0 / seconds_per_day * speed_multiplier()


func set_paused(value: bool) -> void:
	paused = value
	_emit()


func toggle_pause() -> void:
	set_paused(not paused)


func pause() -> void:
	set_paused(true)


func resume() -> void:
	set_paused(false)


## Select speed [param index] (0-based into speeds). Does not change pause
## unless [param unpause] is true.
func set_speed(index: int, unpause: bool = false) -> void:
	speed_index = clampi(index, 0, speeds.size() - 1)
	if unpause:
		paused = false
	_emit()


func faster() -> void:
	set_speed(speed_index + 1)


func slower() -> void:
	set_speed(speed_index - 1)


## Advance the clock by [param hours] whole hours immediately (ignores pause;
## used by tests, AI fast-forward and debugging). Stops early on game over.
func advance_hours(hours: int) -> void:
	for i in hours:
		if not GameState.active or GameState.game_over:
			return
		_step_hour()


func advance_days(days: int) -> void:
	advance_hours(days * 24)


# --- Clock -------------------------------------------------------------------

func _process(delta: float) -> void:
	if not GameState.active or GameState.game_over:
		return
	GameState.time_played += delta
	if paused:
		return
	_accum_hours += delta * hours_per_second()
	var whole := int(floor(_accum_hours))
	if whole <= 0:
		return
	if whole > max_hours_per_frame:
		# Drop the excess instead of spiralling after a long frame.
		whole = max_hours_per_frame
		_accum_hours = 0.0
	else:
		_accum_hours -= whole
	for i in whole:
		if paused or not GameState.active or GameState.game_over:
			break
		_step_hour()


func _step_hour() -> void:
	GameState.hour += 1
	var new_day := false
	if GameState.hour >= 24:
		GameState.hour = 0
		GameState.day_index += 1
		new_day = true
	Simulation.run_hour()
	EventBus.hour_passed.emit(GameState.hour)
	if new_day:
		Simulation.run_day()
		EventBus.day_passed.emit(GameState.day_index)
		var d := GameDate.from_index(GameState.day_index)
		if d.day == 1:
			EventBus.month_passed.emit(d.year, d.month)


func _emit() -> void:
	EventBus.speed_changed.emit(speed_index, paused)


# --- Keyboard ------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not GameState.active:
		return
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	var handled := true
	match k.keycode:
		KEY_SPACE, KEY_P, KEY_PAUSE:
			toggle_pause()
		KEY_1, KEY_KP_1:
			set_speed(0)
		KEY_2, KEY_KP_2:
			set_speed(1)
		KEY_3, KEY_KP_3:
			set_speed(2)
		KEY_4, KEY_KP_4:
			set_speed(3)
		KEY_EQUAL, KEY_PLUS, KEY_KP_ADD:
			faster()
		KEY_MINUS, KEY_KP_SUBTRACT:
			slower()
		_:
			handled = false
	if handled:
		get_viewport().set_input_as_handled()
