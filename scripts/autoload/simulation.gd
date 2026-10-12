extends Node
## Simulation tick dispatcher (autoload "Simulation").
##
## TimeManager calls run_hour() after every in-game hour and run_day() after
## every new day, BEFORE emitting EventBus.hour_passed / day_passed. Game
## systems (production, research, movement, combat, AI ...) register here so
## they run in a fixed, deterministic order:
##
##     Simulation.register_daily("production", _daily_production, 10)
##     Simulation.register_hourly("movement", _hourly_movement, 10)
##
## Lower order runs first; equal order keeps registration order. Registering
## an existing name replaces it. Systems read/write GameState and emit their
## own EventBus signals.

var _hourly: Array[Dictionary] = []   # {name, callable, order, seq}
var _daily: Array[Dictionary] = []
var _seq: int = 0
## Counters (tests / debugging).
var hours_run: int = 0
var days_run: int = 0


func register_hourly(system_name: String, callable: Callable, order: int = 100) -> void:
	_register(_hourly, system_name, callable, order)


func register_daily(system_name: String, callable: Callable, order: int = 100) -> void:
	_register(_daily, system_name, callable, order)


func unregister(system_name: String) -> void:
	for list: Array[Dictionary] in [_hourly, _daily]:
		for i in range(list.size() - 1, -1, -1):
			if list[i].name == system_name:
				list.remove_at(i)


func hourly_systems() -> PackedStringArray:
	return _names(_hourly)


func daily_systems() -> PackedStringArray:
	return _names(_daily)


func run_hour() -> void:
	hours_run += 1
	_run(_hourly)


func run_day() -> void:
	days_run += 1
	_run(_daily)


func _register(list: Array[Dictionary], system_name: String, callable: Callable, order: int) -> void:
	for i in range(list.size() - 1, -1, -1):
		if list[i].name == system_name:
			list.remove_at(i)
	_seq += 1
	list.append({"name": system_name, "callable": callable, "order": order, "seq": _seq})
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.order < b.order if a.order != b.order else a.seq < b.seq)


func _run(list: Array[Dictionary]) -> void:
	# Iterate over a copy: a system may (un)register others while running.
	for entry: Dictionary in list.duplicate():
		var c: Callable = entry.callable
		if c.is_valid():
			c.call()


func _names(list: Array[Dictionary]) -> PackedStringArray:
	var out: PackedStringArray = []
	for e in list:
		out.append(e.name)
	return out
