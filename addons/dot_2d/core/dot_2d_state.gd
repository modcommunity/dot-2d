class_name Dot2DState
extends RefCounted

## Everything about a 2D entity that the simulation reads and writes.
##
## Kept apart from the node for the reason dot-fps-controller keeps
## [code]DotFpsState[/code] apart: a state that lives on a [Node2D] cannot be
## snapshotted, rewound or replayed without touching the scene tree, and
## reconciliation does all three several times a second.

## World position. The authoritative one; the node follows it, not the other way round.
var position: Vector2 = Vector2.ZERO

var velocity: Vector2 = Vector2.ZERO

## Which way the entity is facing, in radians. Not always the direction of travel.
var facing: float = 0.0

## How big it is. Drives collision, and in a mass-based game drives speed too.
var radius: float = 1.0

## How much it is worth. In a blob game this is the score, the size and the speed all
## at once, which is why it lives here rather than in a game's own component.
var mass: float = 1.0

## Whether the entity is being simulated at all. A dead or absorbed blob is not.
var active: bool = true

## Bitfield a game defines. Replicated, so it is where "boosting", "split cooldown" or
## "invulnerable" go.
var flags: int = 0

## Tick this state was produced on, for reconciliation.
var tick: int = 0


static func at(p_position: Vector2, p_radius: float = 1.0) -> Dot2DState:
	var state := Dot2DState.new()
	state.position = p_position
	state.radius = p_radius
	return state


func has_flag(flag: int) -> bool:
	return (flags & flag) != 0


func set_flag(flag: int, on: bool) -> void:
	if on:
		flags |= flag
	else:
		flags &= ~flag


func speed() -> float:
	return velocity.length()


func copy_from(other: Dot2DState) -> void:
	position = other.position
	velocity = other.velocity
	facing = other.facing
	radius = other.radius
	mass = other.mass
	active = other.active
	flags = other.flags
	tick = other.tick


func duplicate_state() -> Dot2DState:
	var copy := Dot2DState.new()
	copy.copy_from(self)
	return copy


## Whether two states are close enough that a client need not be corrected.
##
## [param tolerance] is in world units. A reconciliation that corrects on exact
## equality corrects on every tick — two machines doing the same float arithmetic in a
## different order do not produce bit-identical results — and a client that is
## corrected every tick is a client that rubber-bands permanently.
func matches(other: Dot2DState, tolerance: float = 0.05) -> bool:
	if other == null:
		return false

	if active != other.active or flags != other.flags:
		return false

	if position.distance_squared_to(other.position) > tolerance * tolerance:
		return false

	if not is_equal_approx(radius, other.radius):
		return false

	return absf(mass - other.mass) <= maxf(0.001, other.mass * 0.001)


func describe() -> Dictionary:
	return {
		"position": position,
		"velocity": velocity,
		"speed": speed(),
		"radius": radius,
		"mass": mass,
		"active": active,
		"flags": flags,
		"tick": tick,
	}


func _to_string() -> String:
	return "Dot2DState(%.1f,%.1f r%.1f m%.1f)" % [
		position.x, position.y, radius, mass
	]
