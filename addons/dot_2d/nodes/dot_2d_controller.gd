@tool
class_name Dot2DController
extends Node2D

## Drives one 2D entity: samples, simulates, publishes.
##
## The 2D counterpart of [code]DotFpsController[/code], and structured the same way.
## [b]The node follows the state, not the other way round.[/b] The simulation owns
## [member state] and the transform is written from it after each tick — a controller
## that read its position back out of the node would be reading a value the renderer
## may have interpolated.

const CHANNEL := "dot2d"
const SERVICE := &"dot_2d_controller"

## A tick was simulated. The place to read the new state.
signal simulated(tick: int, state: Dot2DState)

## The entity hit something solid.
signal collided(normal: Vector2)

## Mass crossed a size threshold a game cares about, in either direction.
signal mass_changed(from: float, to: float)

## How this controller is driven.
enum Drive {
	## Samples input and simulates locally. Single-player, and a predicting client.
	LOCAL,
	## Simulated from commands handed in. A server, and a replay.
	COMMANDED,
	## Not simulated at all; the state is written from the network.
	REMOTE,
}

@export_group("Role")

@export var drive: Drive = Drive.LOCAL

## Must match the netcode's rate.
@export_range(1, 240, 1) var tick_rate: int = 60

## Most ticks one frame may simulate to catch up. A frame that simulated an
## unbounded backlog is a second of movement in one frame, which reads as a
## player teleporting. [member Dot2DConfig.max_catchup_ticks] lands here.
@export_range(1, 60, 1) var max_catchup_ticks: int = 8

@export var register_service: bool = false

@export var service_scope: StringName = &""

@export_group("Configuration")

@export var tunables: Dot2DTunables = null

@export_group("Wiring")

## The arena this belongs to. Registers itself with it when resolved.
@export var arena_ref: DotNodeRef = null

## Where input comes from, in [constant Drive.LOCAL]. Optional.
@export var sampler_ref: DotNodeRef = null

@export_group("Identity")

## The id this entity is known by in the arena and on the wire. Set by the host.
@export var entity_id: int = 0

## The simulation state. The authoritative one.
var state: Dot2DState = Dot2DState.new()

var motor: Dot2DMotor = null

var arena: Dot2DArena = null

var sampler: Node = null

## The command being simulated. Set by the sampler, or handed in.
var current_command: Dot2DCommand = null

var _last_command: Dot2DCommand = null
var _accumulator: float = 0.0
var _tick: int = 0
var _started: bool = false
var _replaying: bool = false
var _registered_name: StringName = &""


func _ready() -> void:
	if Engine.is_editor_hint():
		return

	var res := setup()

	if not res.ok:
		DotLog.result(CHANNEL, "controller setup", res)


func _exit_tree() -> void:
	if arena != null and is_instance_valid(arena) and entity_id != 0:
		arena.forget(entity_id)

	if _registered_name != &"":
		DotRegistry.unregister_instance(_registered_name, self)
		_registered_name = &""


func setup() -> DotResult:
	if tunables == null:
		tunables = Dot2DTunables.topdown()

	var valid := tunables.validate()

	if not valid.ok:
		return valid

	motor = Dot2DMotor.with_tunables(tunables)

	if arena_ref != null:
		arena = arena_ref.resolve_or_null(self, CHANNEL) as Dot2DArena

	if arena != null:
		motor.body = arena.body

		if entity_id != 0:
			arena.register(entity_id, state)

	if sampler_ref != null:
		sampler = sampler_ref.resolve_or_null(self, CHANNEL)

	if state.position == Vector2.ZERO:
		state.position = global_position

	if tunables.mass_rules != null:
		state.radius = tunables.mass_rules.radius_for(state.mass)

	if register_service:
		_registered_name = (
			DotRegistry.scoped_name(SERVICE, service_scope)
			if service_scope != &""
			else SERVICE
		)
		DotRegistry.register(_registered_name, self)

	_started = true
	_publish()
	return DotResult.success(null)


## Attaches to an arena after construction. For an entity spawned at runtime.
func attach(p_arena: Dot2DArena, id: int) -> void:
	if arena != null and is_instance_valid(arena) and entity_id != 0:
		arena.forget(entity_id)

	arena = p_arena
	entity_id = id

	if arena == null:
		return

	if motor != null:
		motor.body = arena.body

	arena.register(entity_id, state)


# --- Simulation ------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or not _started:
		return

	if drive == Drive.REMOTE:
		_publish()
		return

	if drive == Drive.COMMANDED:
		# A commanded controller is stepped by whoever owns the tick — a netcode
		# manager, a test — so it must not also step itself here.
		return

	_accumulator += delta
	var step := 1.0 / float(tick_rate)

	# Bounded so a long stall does not spend a whole frame catching up, which on a
	# loading hitch is a second of simulation in one frame and a player who teleports.
	var budget := max_catchup_ticks

	while _accumulator >= step and budget > 0:
		_accumulator -= step
		budget -= 1
		_tick += 1
		simulate_tick(_tick, step)

	if budget == 0:
		_accumulator = 0.0


## Simulates one tick. The whole of the simulation for this entity.
func simulate_tick(tick: int, delta: float) -> void:
	if not _started or drive == Drive.REMOTE:
		return

	var command := current_command

	if command == null and drive == Drive.LOCAL and sampler != null:
		if sampler.has_method(&"sample"):
			command = sampler.call(&"sample", delta)

	if command == null:
		# Repeat the last command rather than falling to zero. A dropped input packet
		# should read as "still holding the key", which is what actually happened, not
		# as "let go" — and a blob that stops every time a packet is late is unplayable
		# at any latency.
		command = _last_command if _last_command != null else Dot2DCommand.new()

	var before_mass := state.mass
	var before_position := state.position

	motor.simulate(state, command, delta, tick)

	_last_command = command.duplicate_command()
	current_command = null

	if arena != null and entity_id != 0:
		arena.grid.place(entity_id, state.position, state.radius)

	_publish()

	if not _replaying:
		if not is_equal_approx(before_mass, state.mass):
			mass_changed.emit(before_mass, state.mass)

		# The move being shorter than the velocity asked for is the only evidence a
		# body reports, and it is what a wall-slide sound is triggered from.
		var wanted := state.velocity.length() * delta
		var moved := before_position.distance_to(state.position)

		if wanted > 0.01 and moved < wanted * 0.5:
			collided.emit((state.position - before_position).normalized())

	simulated.emit(tick, state)


## Hands in a command for the next tick. What a server does with a received input.
func apply_command(command: Dot2DCommand) -> void:
	current_command = command


## Overwrites the state from the network. What a remote entity does.
func apply_state(remote: Dot2DState) -> void:
	state.copy_from(remote)
	_publish()

	if arena != null and entity_id != 0:
		arena.grid.place(entity_id, state.position, state.radius)


## Marks the following ticks as a reconciliation replay, so signals that would fire an
## effect twice are suppressed.
func begin_replay() -> void:
	_replaying = true


func end_replay() -> void:
	_replaying = false


func is_replaying() -> bool:
	return _replaying


## Moves the entity without simulating. A spawn, a teleport, an admin command.
func teleport(position: Vector2, keep_velocity: bool = false) -> void:
	state.position = position

	if not keep_velocity:
		state.velocity = Vector2.ZERO

	_publish()

	if arena != null and entity_id != 0:
		arena.grid.place(entity_id, state.position, state.radius)


## Sets mass and recomputes radius from it.
##
## Setting `state.mass` directly leaves the radius describing the old mass until the
## next tick, and anything that queries in between — an eat check, an interest
## rectangle — uses the wrong one.
func set_mass(mass: float) -> void:
	var before := state.mass
	state.mass = maxf(0.0001, mass)

	if tunables != null and tunables.mass_rules != null:
		state.radius = tunables.mass_rules.radius_for(state.mass)

	if arena != null and entity_id != 0:
		arena.grid.place(entity_id, state.position, state.radius)

	if not is_equal_approx(before, state.mass):
		mass_changed.emit(before, state.mass)


func _publish() -> void:
	global_position = state.position

	if tunables != null and not tunables.face_velocity and tunables.mode \
		!= Dot2DTunables.Mode.THRUST:
		return

	rotation = state.facing


## Speed this entity can currently reach, for a HUD.
func current_speed_limit() -> float:
	if tunables == null:
		return 0.0

	var limit := tunables.max_speed

	if tunables.mass_rules != null:
		limit *= tunables.mass_rules.speed_scale(state.mass)

	return limit


func describe() -> Dictionary:
	return {
		"id": entity_id,
		"drive": Drive.keys()[drive],
		"tick": _tick,
		"state": state.describe(),
		"speed_limit": current_speed_limit(),
		"arena": arena != null,
	}


func describe_lines() -> PackedStringArray:
	return PackedStringArray([
		"entity   %d  %s" % [entity_id, Drive.keys()[drive]],
		"position %.1f, %.1f" % [state.position.x, state.position.y],
		"speed    %.1f of %.1f" % [state.speed(), current_speed_limit()],
		"mass     %.1f  radius %.1f" % [state.mass, state.radius],
	])
