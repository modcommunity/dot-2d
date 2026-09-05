@tool
class_name Dot2DSampler
extends Node

## Turns devices into a [Dot2DCommand]. The only place dot-2d reads input.
##
## [b]Sampling is separate from simulating on purpose.[/b] The motor never reads a
## device, so a bot, a demo playback and a replayed network command all drive the same
## code as a player. Subclass this — or ignore it entirely and build a
## [Dot2DCommand] yourself — and everything downstream is unchanged.
##
## The pointer is resolved to a **direction and a distance in world units** here rather
## than being sent as a screen position, because a screen position is meaningless on a
## server that has no window and no camera.

const CHANNEL := "dot2d.input"

@export_group("Actions")

@export var move_left: StringName = &"move_left"
@export var move_right: StringName = &"move_right"
@export var move_up: StringName = &"move_up"
@export var move_down: StringName = &"move_down"

@export var action_button: StringName = &"action"
@export var alt_button: StringName = &"alt_action"
@export var boost_button: StringName = &"boost"
@export var split_button: StringName = &"split"
@export var eject_button: StringName = &"eject"

@export_group("Pointer")

## Aim at the mouse. Off, aim comes from the movement stick.
@export var use_pointer: bool = true

## What the pointer distance is measured from. Usually the entity being controlled.
@export var origin_ref: DotNodeRef = null

## Largest pointer distance reported, in world units. Also the wire's range.
@export_range(1.0, 5000.0, 1.0) var max_reach: float = 1000.0

@export_group("Touch")

## Treat a drag as a pointer. What a phone needs, and the only device-specific branch
## in the class.
@export var touch_as_pointer: bool = true

@export_group("Safety")

## Ignore input entirely. Set while a menu is open, or while dead.
@export var suspended: bool = false

## Register the movement actions in [InputMap] if they are missing.
##
## Convenient for a prototype and wrong for a shipped game, where the actions are the
## project's. It only ever adds; it never rebinds one that exists.
@export var register_default_actions: bool = false

var _origin: Node2D = null
var _touch_position: Vector2 = Vector2.ZERO
var _touching: bool = false


func _ready() -> void:
	if Engine.is_editor_hint():
		return

	if register_default_actions:
		_register_defaults()

	if origin_ref != null:
		_origin = origin_ref.resolve_or_null(self, CHANNEL) as Node2D

	if _origin == null:
		_origin = get_parent() as Node2D


func _register_defaults() -> void:
	var table := {
		move_left: KEY_A,
		move_right: KEY_D,
		move_up: KEY_W,
		move_down: KEY_S,
		split_button: KEY_SPACE,
		eject_button: KEY_W,
		boost_button: KEY_SHIFT,
	}

	for action in table.keys():
		if InputMap.has_action(action):
			continue

		InputMap.add_action(action)
		var event := InputEventKey.new()
		event.physical_keycode = int(table[action])
		InputMap.action_add_event(action, event)


func _unhandled_input(event: InputEvent) -> void:
	if not touch_as_pointer:
		return

	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		_touching = touch.pressed
		_touch_position = touch.position
	elif event is InputEventScreenDrag:
		_touch_position = (event as InputEventScreenDrag).position


## Produces the command for this tick.
##
## Called by [Dot2DController] in [constant Dot2DController.Drive.LOCAL]. Safe to call
## outside the tree — it returns an empty command rather than failing, which is what a
## headless test wants.
func sample(_delta: float = 0.0) -> Dot2DCommand:
	var command := Dot2DCommand.new()

	if suspended or not is_inside_tree():
		return command

	command.move = Input.get_vector(
		move_left, move_right, move_up, move_down
	)

	command.set_button(
		Dot2DCommand.BUTTON_ACTION, _pressed(action_button)
	)
	command.set_button(Dot2DCommand.BUTTON_ALT, _pressed(alt_button))
	command.set_button(Dot2DCommand.BUTTON_BOOST, _pressed(boost_button))
	command.set_button(Dot2DCommand.BUTTON_SPLIT, _pressed(split_button))
	command.set_button(Dot2DCommand.BUTTON_EJECT, _pressed(eject_button))

	_apply_pointer(command)
	command.sanitise(max_reach)
	return command


func _pressed(action: StringName) -> bool:
	return action != &"" and InputMap.has_action(action) and Input.is_action_pressed(action)


func _apply_pointer(command: Dot2DCommand) -> void:
	if not use_pointer or _origin == null or not _origin.is_inside_tree():
		# Without a pointer the aim is the movement direction, so a game that switches
		# between the two does not have to special-case which one is live.
		command.aim = command.move.normalized() if command.move != Vector2.ZERO else Vector2.ZERO
		command.reach = max_reach if command.aim != Vector2.ZERO else 0.0
		return

	var target := _pointer_world_position()

	if target == null:
		command.aim = Vector2.ZERO
		command.reach = 0.0
		return

	var offset: Vector2 = (target as Vector2) - _origin.global_position

	command.aim = offset.normalized() if offset.length_squared() > 0.000001 else Vector2.ZERO
	command.reach = minf(offset.length(), max_reach)


## Where the pointer is, in world coordinates. Null when there is no pointer.
##
## The canvas transform is what turns a screen position into a world one, and it
## already accounts for the camera's position and zoom — which is why this works on a
## zoomed-out blob without any special case.
func _pointer_world_position() -> Variant:
	if _touching:
		return _origin.get_canvas_transform().affine_inverse() * _touch_position

	if DisplayServer.get_name() == "headless":
		return null

	var viewport := _origin.get_viewport()

	if viewport == null:
		return null

	return _origin.get_global_mouse_position()


func describe() -> Dictionary:
	return {
		"suspended": suspended,
		"pointer": use_pointer,
		"touching": _touching,
		"origin": _origin.name if _origin != null else "<none>",
	}
