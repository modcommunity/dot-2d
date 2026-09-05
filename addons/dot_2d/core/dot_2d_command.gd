class_name Dot2DCommand
extends RefCounted

## What a 2D player asked for on one tick.
##
## The 2D counterpart of dot-fps-controller's [code]DotFpsCommand[/code], and separate
## from input sampling for the same reason: the simulation must be a pure function of
## these, so a client predicting a move and a server re-running it reach the same
## answer. Nothing in [Dot2DMotor] reads a device, a clock or a node.
##
## [b][member aim] is a direction, not a screen position.[/b] A mouse position is
## meaningless on the server — it depends on a window size and a camera zoom the server
## does not have — so the client resolves it to a unit vector before it goes on the
## wire. That is the whole reason an agar.io-like game is predictable at all.

const BUTTON_ACTION := 1 << 0
const BUTTON_ALT := 1 << 1
const BUTTON_BOOST := 1 << 2
const BUTTON_SPLIT := 1 << 3
const BUTTON_EJECT := 1 << 4

const BUTTON_USER_0 := 1 << 5
const BUTTON_USER_1 := 1 << 6
const BUTTON_USER_2 := 1 << 7

const BUTTON_BITS := 8

## Movement intent, at most unit length. What a stick or WASD produces.
##
## In a point-and-move game — agar.io, a twin-stick — this is unused and [member aim]
## drives movement instead; see [member Dot2DTunables.follow_aim].
var move: Vector2 = Vector2.ZERO

## Where the player is pointing, unit length. Zero means "nowhere in particular".
var aim: Vector2 = Vector2.ZERO

## How far the pointer is from the player, in world units, clamped by the sampler.
##
## Needed by a follow-the-cursor game: a cursor a few pixels away should move the blob
## slowly and one across the screen should move it at full speed, and the direction
## alone cannot express that.
var reach: float = 0.0

var buttons: int = 0


func is_pressed(button: int) -> bool:
	return (buttons & button) != 0


func set_button(button: int, pressed: bool) -> void:
	if pressed:
		buttons |= button
	else:
		buttons &= ~button


## Buttons pressed on this command that were not pressed on [param previous].
##
## Splitting and ejecting are edge-triggered. Reading the level instead is a blob that
## splits sixty times a second for as long as the key is held.
func pressed_since(previous: Dot2DCommand) -> int:
	if previous == null:
		return buttons
	return buttons & ~previous.buttons


func just_pressed(button: int, previous: Dot2DCommand) -> bool:
	return (pressed_since(previous) & button) != 0


func duplicate_command() -> Dot2DCommand:
	var copy := Dot2DCommand.new()
	copy.move = move
	copy.aim = aim
	copy.reach = reach
	copy.buttons = buttons
	return copy


func equals(other: Dot2DCommand) -> bool:
	if other == null:
		return false
	return (
		buttons == other.buttons
		and move.is_equal_approx(other.move)
		and aim.is_equal_approx(other.aim)
		and is_equal_approx(reach, other.reach)
	)


## Clamps everything a hostile client could send out of range.
##
## Called on the server for every received command. A move vector of length 40 is not a
## crash, it is a player moving forty times as fast as everyone else — the single most
## common cheat in a game where movement is client-driven, and the one thing a server
## that trusts its clients cannot detect afterwards.
func sanitise(max_reach: float = 1000.0) -> void:
	if is_nan(move.x) or is_nan(move.y):
		move = Vector2.ZERO
	elif move.length_squared() > 1.0:
		move = move.normalized()

	if is_nan(aim.x) or is_nan(aim.y):
		aim = Vector2.ZERO
	elif aim.length_squared() > 0.000001:
		aim = aim.normalized()
	else:
		aim = Vector2.ZERO

	reach = 0.0 if is_nan(reach) else clampf(reach, 0.0, max_reach)
	buttons &= (1 << BUTTON_BITS) - 1


## Writes to a [code]DotNetWriter[/code].
##
## [param writer] is [Variant] so this file never mentions a dot-net class name — a
## script that does fails to parse in a project without dot-net installed.
##
## The move and aim vectors go as two quantised components rather than as an angle and
## a magnitude: an angle needs a special case for the zero vector, and "not moving" is
## the most common command in the stream.
func write(writer: Variant, max_reach: float = 1000.0) -> void:
	writer.write_vector2_range(move, -1.0, 1.0, 9)
	writer.write_vector2_range(aim, -1.0, 1.0, 10)
	writer.write_float_range(reach, 0.0, max_reach, 10)
	writer.write_uint(buttons, BUTTON_BITS)


func read(reader: Variant, max_reach: float = 1000.0) -> void:
	move = reader.read_vector2_range(-1.0, 1.0, 9)
	aim = reader.read_vector2_range(-1.0, 1.0, 10)
	reach = reader.read_float_range(0.0, max_reach, 10)
	buttons = reader.read_uint(BUTTON_BITS)


static func estimated_bits() -> int:
	return 9 * 2 + 10 * 2 + 10 + BUTTON_BITS


static func button_names(mask: int) -> PackedStringArray:
	var names := PackedStringArray()
	var table := {
		BUTTON_ACTION: "action",
		BUTTON_ALT: "alt",
		BUTTON_BOOST: "boost",
		BUTTON_SPLIT: "split",
		BUTTON_EJECT: "eject",
	}
	for bit in table.keys():
		if (mask & int(bit)) != 0:
			names.append(str(table[bit]))
	return names


func describe() -> Dictionary:
	return {
		"move": move,
		"aim": aim,
		"reach": reach,
		"buttons": Array(button_names(buttons)),
	}


func _to_string() -> String:
	return "Dot2DCommand(%s, %s)" % [
		move, "+".join(button_names(buttons)) if buttons != 0 else "-"
	]
