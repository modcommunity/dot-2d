extends Node

## Shared fixtures and assertions for the dot-2d self-test. The tests sit in layers above
## this file ([code]dot_2d_selftest_mid.gd[/code] and up) and the runner is [code]dot_2d_selftest.gd[/code].

const TICK_RATE := 60
const STEP := 1.0 / 60.0

var _passed := 0
var _failed := 0
var _failures := PackedStringArray()
var _entered := 0
var _completed := 0


# --- Assertions ------------------------------------------------------------

func _section(title: String) -> void:
	_entered += 1
	_group(title)


## A section reached its last line. See SECTIONS in the runner.
func _done() -> void:
	_completed += 1


func _check(condition: bool, what: String, detail: String = "") -> bool:
	if condition:
		_passed += 1
		print("  ok    %s" % what)
	else:
		_failed += 1
		_failures.append(what if detail == "" else "%s — %s" % [what, detail])
		print("  FAIL  %s%s" % [what, "" if detail == "" else " — " + detail])
	return condition


func _close(a: float, b: float, what: String, epsilon: float = 0.01) -> bool:
	return _check(absf(a - b) <= epsilon, what, "%.4f vs %.4f" % [a, b])


func _group(title: String) -> void:
	print("")
	print("%s" % title)


# --- Fixtures --------------------------------------------------------------

func _aim_command(direction: Vector2, reach: float = 1000.0) -> Dot2DCommand:
	var command := Dot2DCommand.new()
	command.aim = direction.normalized()
	command.reach = reach
	return command


func _move_command(direction: Vector2) -> Dot2DCommand:
	var command := Dot2DCommand.new()
	command.move = direction.limit_length(1.0)
	return command


func _run_ticks(
	motor: Dot2DMotor,
	state: Dot2DState,
	command: Dot2DCommand,
	count: int
) -> void:
	for tick in range(count):
		motor.simulate(state, command, STEP, tick)


# --- Command ---------------------------------------------------------------
