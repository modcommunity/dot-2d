@tool
class_name Dot2DTunables
extends Resource

## How a 2D entity moves. Everything a designer touches, in one resource.
##
## Three feels, chosen by [member mode], because they are the three that cover almost
## every 2D game and they are genuinely different simulations rather than the same one
## with different numbers.

enum Mode {
	## Accelerate toward the wanted direction, with friction. A top-down shooter, a
	## roguelike, a brawler. The default.
	TOPDOWN,
	## Thrust along the facing, turn separately, no friction. Asteroids, a spaceship.
	THRUST,
	## Move toward the pointer at a speed that falls as mass rises. agar.io, and every
	## game where getting bigger is a trade against getting slower.
	BLOB,
}

@export var mode: Mode = Mode.TOPDOWN

@export_group("Speed")

## Top speed in world units per second, before any mass scaling.
@export_range(1.0, 5000.0, 1.0) var max_speed: float = 300.0

## Units per second per second while a direction is held.
##
## Above [member max_speed] this reaches top speed in under a second, which is what a
## responsive top-down game wants and what a physical one does not.
@export_range(1.0, 20000.0, 10.0) var acceleration: float = 2400.0

## Deceleration when nothing is held.
@export_range(0.0, 20000.0, 10.0) var friction: float = 1800.0

## Fraction of [member acceleration] available while already at top speed in another
## direction. Below 1 makes turning cost something.
@export_range(0.0, 1.0, 0.05) var turn_authority: float = 1.0

@export_group("Pointer")

## Move toward [member Dot2DCommand.aim] rather than [member Dot2DCommand.move].
##
## What agar.io and a twin-stick with mouse aim want. Forced on in
## [constant Mode.BLOB], because a blob game with WASD is a different game.
@export var follow_aim: bool = false

## Pointer distance at which the entity moves at full speed. Closer is proportionally
## slower, which is what makes fine positioning possible at all.
@export_range(1.0, 2000.0, 1.0) var full_speed_reach: float = 120.0

## Below this the entity stops entirely, so a cursor resting on it does not jitter.
@export_range(0.0, 500.0, 1.0) var dead_reach: float = 4.0

@export_group("Thrust")

## Radians per second the facing turns, for [constant Mode.THRUST].
@export_range(0.1, 40.0, 0.1) var turn_rate: float = 4.0

## Whether the facing follows the direction of travel in the other modes.
@export var face_velocity: bool = true

## Below this speed the facing is left alone, so a stopping entity does not spin.
@export_range(0.0, 200.0, 1.0) var face_min_speed: float = 5.0

@export_group("Boost")

## Multiplies speed while [constant Dot2DCommand.BUTTON_BOOST] is held.
@export_range(1.0, 6.0, 0.05) var boost_multiplier: float = 1.6

## Mass per second boosting costs. Zero is free.
@export_range(0.0, 100.0, 0.5) var boost_mass_cost: float = 0.0

@export_group("Mass")

## How radius, speed and eating are derived from mass. Required in
## [constant Mode.BLOB]; ignored otherwise.
@export var mass_rules: Dot2DMassRules = null

@export_group("Bounds")

## Bounce off the arena edge rather than sliding along it.
@export var bounce_off_walls: bool = false

## Fraction of speed kept in a bounce.
@export_range(0.0, 1.0, 0.05) var restitution: float = 0.5


static func topdown() -> Dot2DTunables:
	return Dot2DTunables.new()


static func blob() -> Dot2DTunables:
	var tunables := Dot2DTunables.new()
	tunables.mode = Mode.BLOB
	tunables.follow_aim = true
	tunables.max_speed = 420.0
	# Blobs do not accelerate. In agar.io the cell is exactly as fast as its mass
	# allows, immediately, and adding acceleration makes small cells feel sluggish
	# in precisely the situation they are supposed to be nimble.
	tunables.acceleration = 100000.0
	tunables.friction = 100000.0
	tunables.face_velocity = false
	tunables.mass_rules = Dot2DMassRules.agar()
	return tunables


static func thrust() -> Dot2DTunables:
	var tunables := Dot2DTunables.new()
	tunables.mode = Mode.THRUST
	tunables.max_speed = 400.0
	tunables.acceleration = 500.0
	tunables.friction = 60.0
	tunables.face_velocity = false
	return tunables


func uses_aim() -> bool:
	return follow_aim or mode == Mode.BLOB


func validate() -> DotResult:
	if mode == Mode.BLOB and mass_rules == null:
		return DotResult.fail(
			DotError.CODE_INVALID,
			"Blob mode needs mass rules; without them every blob is the same size "
			+ "and the same speed, which is not a game."
		)

	if dead_reach >= full_speed_reach:
		return DotResult.fail(
			DotError.CODE_INVALID,
			"dead_reach of %.1f is at or beyond full_speed_reach of %.1f, so the "
				% [dead_reach, full_speed_reach]
			+ "entity can only ever be stopped or at full speed."
		)

	if mass_rules != null:
		return mass_rules.validate()

	return DotResult.success(null)


func describe() -> Dictionary:
	return {
		"mode": Mode.keys()[mode],
		"max_speed": max_speed,
		"acceleration": acceleration,
		"friction": friction,
		"follow_aim": uses_aim(),
		"mass_rules": mass_rules.describe() if mass_rules != null else null,
	}
