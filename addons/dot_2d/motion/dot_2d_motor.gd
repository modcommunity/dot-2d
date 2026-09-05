class_name Dot2DMotor
extends RefCounted

## Turns a [Dot2DCommand] into a change in a [Dot2DState]. The simulation itself.
##
## [b]A pure function of its arguments.[/b] No device, no clock, no node, no
## randomness. Called with the same state, command and delta it produces the same
## result on every machine and on every replay — which is what makes a 2D game
## predictable, and is the same contract dot-fps-controller's motor holds.
##
## The mode is on the tunables rather than in three motor classes because a game
## switching feels — a top-down character that boards a ship — should not swap the
## object that owns the state.

const CHANNEL := "dot2d.motor"

var tunables: Dot2DTunables = null

## What the entity collides against. Null means nothing does.
var body: Dot2DBody = null


static func with_tunables(p_tunables: Dot2DTunables) -> Dot2DMotor:
	var motor := Dot2DMotor.new()
	motor.tunables = p_tunables
	return motor


## Advances [param state] by [param delta] seconds under [param command].
##
## [param delta] is the fixed simulation step, not a frame time. A variable step makes
## the result depend on the frame rate, which two machines do not share.
func simulate(
	state: Dot2DState,
	command: Dot2DCommand,
	delta: float,
	tick: int = 0
) -> void:
	if state == null or not state.active or tunables == null:
		return

	if command == null:
		command = Dot2DCommand.new()

	state.tick = tick

	_apply_mass(state, delta)

	match tunables.mode:
		Dot2DTunables.Mode.THRUST:
			_simulate_thrust(state, command, delta)
		Dot2DTunables.Mode.BLOB:
			_simulate_blob(state, command, delta)
		_:
			_simulate_topdown(state, command, delta)

	_integrate(state, delta)
	_apply_facing(state, command, delta)


## Recomputes radius from mass, and applies decay.
##
## Before the move rather than after: speed depends on mass, and a tick that moved at
## last tick's speed and then changed mass is a tick where the two disagree by exactly
## one frame — which is invisible until a client and a server disagree about which side
## of an eat threshold a blob was on.
func _apply_mass(state: Dot2DState, delta: float) -> void:
	var rules := tunables.mass_rules

	if rules == null:
		return

	state.mass = rules.decay(state.mass, delta)
	state.radius = rules.radius_for(state.mass)


func _speed_limit(state: Dot2DState, command: Dot2DCommand) -> float:
	var limit := tunables.max_speed

	if tunables.mass_rules != null:
		limit *= tunables.mass_rules.speed_scale(state.mass)

	if command.is_pressed(Dot2DCommand.BUTTON_BOOST):
		limit *= tunables.boost_multiplier

	return limit


## The direction the player wants to go, and how hard, from 0 to 1.
##
## In pointer mode the magnitude comes from how far the cursor is, which is what makes
## fine positioning possible; in stick mode it is the stick's own magnitude.
func wish_vector(command: Dot2DCommand) -> Vector2:
	if not tunables.uses_aim():
		return command.move.limit_length(1.0)

	if command.aim == Vector2.ZERO:
		return Vector2.ZERO

	if command.reach <= tunables.dead_reach:
		return Vector2.ZERO

	var strength := clampf(
		(command.reach - tunables.dead_reach)
			/ maxf(0.001, tunables.full_speed_reach - tunables.dead_reach),
		0.0,
		1.0
	)

	return command.aim.normalized() * strength


func _simulate_topdown(
	state: Dot2DState,
	command: Dot2DCommand,
	delta: float
) -> void:
	var wish := wish_vector(command)
	var limit := _speed_limit(state, command)

	if wish == Vector2.ZERO:
		_apply_friction(state, delta)
		return

	var target := wish * limit
	var difference := target - state.velocity

	# Turn authority: accelerating across the current velocity costs more than
	# accelerating along it. Below 1 this is what makes momentum readable.
	var rate := tunables.acceleration

	if tunables.turn_authority < 1.0 and state.velocity.length_squared() > 0.001:
		var alignment := state.velocity.normalized().dot(wish.normalized())
		rate *= lerpf(tunables.turn_authority, 1.0, clampf(alignment, 0.0, 1.0))

	var step := rate * delta

	if difference.length() <= step:
		state.velocity = target
	else:
		state.velocity += difference.normalized() * step

	state.velocity = state.velocity.limit_length(limit)


func _simulate_thrust(
	state: Dot2DState,
	command: Dot2DCommand,
	delta: float
) -> void:
	# Turning is separate from thrusting, which is the whole feel of the mode.
	if tunables.uses_aim() and command.aim != Vector2.ZERO:
		var wanted := command.aim.angle()
		var difference := wrapf(wanted - state.facing, -PI, PI)
		var step := tunables.turn_rate * delta
		state.facing += clampf(difference, -step, step)
	else:
		state.facing += command.move.x * tunables.turn_rate * delta

	state.facing = wrapf(state.facing, -PI, PI)

	var throttle := maxf(0.0, command.move.y)

	if command.is_pressed(Dot2DCommand.BUTTON_ACTION):
		throttle = 1.0

	if throttle > 0.0:
		state.velocity += Vector2.from_angle(state.facing) \
			* tunables.acceleration * throttle * delta
	else:
		_apply_friction(state, delta)

	state.velocity = state.velocity.limit_length(_speed_limit(state, command))


## Blob movement: velocity is set outright, not accelerated toward.
##
## In agar.io a cell is exactly as fast as its mass allows, immediately. Accelerating
## toward that makes a small cell feel sluggish in exactly the situation it is supposed
## to be nimble, and it makes a split feel like a slide.
func _simulate_blob(
	state: Dot2DState,
	command: Dot2DCommand,
	delta: float
) -> void:
	var wish := wish_vector(command)
	var limit := _speed_limit(state, command)

	if wish == Vector2.ZERO:
		_apply_friction(state, delta)
		return

	state.velocity = wish * limit

	if (
		command.is_pressed(Dot2DCommand.BUTTON_BOOST)
		and tunables.boost_mass_cost > 0.0
		and tunables.mass_rules != null
	):
		state.mass = maxf(1.0, state.mass - tunables.boost_mass_cost * delta)
		state.radius = tunables.mass_rules.radius_for(state.mass)


func _apply_friction(state: Dot2DState, delta: float) -> void:
	var speed := state.velocity.length()

	if speed <= 0.0001:
		state.velocity = Vector2.ZERO
		return

	var drop := tunables.friction * delta

	if drop >= speed:
		state.velocity = Vector2.ZERO
	else:
		state.velocity = state.velocity * ((speed - drop) / speed)


func _integrate(state: Dot2DState, delta: float) -> void:
	var motion := state.velocity * delta

	if motion == Vector2.ZERO:
		return

	if body == null:
		state.position += motion
		return

	var hit := body.move(state.position, motion, state.radius)
	state.position = hit.position

	if not hit.blocked:
		return

	if body is Dot2DBodyFlat:
		var flat := body as Dot2DBodyFlat
		flat.bounce = tunables.bounce_off_walls
		flat.restitution = tunables.restitution
		state.velocity = flat.reflect(state.velocity, hit)
	elif hit.normal != Vector2.ZERO:
		state.velocity = (
			state.velocity.bounce(hit.normal) * tunables.restitution
			if tunables.bounce_off_walls
			else state.velocity.slide(hit.normal)
		)


func _apply_facing(
	state: Dot2DState,
	command: Dot2DCommand,
	_delta: float
) -> void:
	if tunables.mode == Dot2DTunables.Mode.THRUST:
		return

	if tunables.uses_aim() and command.aim != Vector2.ZERO:
		state.facing = command.aim.angle()
		return

	if not tunables.face_velocity:
		return

	# Below the threshold the facing is left alone, so an entity coming to a stop does
	# not spin as its velocity crosses zero.
	if state.velocity.length() >= tunables.face_min_speed:
		state.facing = state.velocity.angle()


## Applies a one-off impulse. What a split, a knockback or an explosion does.
##
## Deterministic, and takes no time: called on the same tick with the same arguments on
## two machines it produces the same velocity.
func impulse(state: Dot2DState, direction: Vector2, strength: float) -> void:
	if state == null or direction == Vector2.ZERO:
		return

	state.velocity += direction.normalized() * strength


func describe() -> Dictionary:
	return {
		"tunables": tunables.describe() if tunables != null else null,
		"body": body.describe() if body != null else null,
	}
