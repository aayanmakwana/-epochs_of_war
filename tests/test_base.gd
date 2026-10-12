extends SceneTree
## Minimal headless test harness.
##
## Usage: create tests/test_<name>.gd with
##     extends "res://tests/test_base.gd"
##     func run_tests() -> void:
##         check(1 + 1 == 2, "math works")
## and run it with
##     godot --headless --path . -s tests/test_<name>.gd
## Exit code is 0 when every check passed, 1 otherwise.
## run_tests() may use `await` (e.g. await process_frame).

var _passed: int = 0
var _failed: int = 0
var _failures: PackedStringArray = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	# Let autoloads finish _ready before tests start.
	await process_frame
	print("=== %s ===" % get_script().resource_path.get_file())
	await run_tests()
	print("--- %d passed, %d failed ---" % [_passed, _failed])
	for f in _failures:
		print("  FAILED: " + f)
	print("RESULT: " + ("PASS" if _failed == 0 else "FAIL"))
	quit(0 if _failed == 0 else 1)


## Override in the concrete test.
func run_tests() -> void:
	pass


func check(condition: bool, description: String) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		_failures.append(description)
		printerr("FAILED: " + description)


func check_eq(actual: Variant, expected: Variant, description: String) -> void:
	var ok: bool = typeof(actual) == typeof(expected) and actual == expected
	# Allow int/float comparisons.
	if not ok and (typeof(actual) in [TYPE_INT, TYPE_FLOAT]) and (typeof(expected) in [TYPE_INT, TYPE_FLOAT]):
		ok = is_equal_approx(float(actual), float(expected))
	check(ok, "%s (expected %s, got %s)" % [description, str(expected), str(actual)])


## Get an autoload singleton by name (safe in -s scripts).
func autoload(node_name: String) -> Node:
	return root.get_node_or_null("/root/" + node_name)
