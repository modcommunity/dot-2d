@tool
class_name Dot2DArena
extends Node2D

## The bounded world: where things are, what is near what, and who can see whom.
##
## Holds the [Dot2DGrid] every query goes through and the [Dot2DBodyFlat] every entity
## moves against, so a game has one object to hand around rather than three that have
## to be kept in step.
##
## [b]No autoload.[/b] It registers itself in [DotRegistry] under [constant SERVICE].
## A process running a server and a client at once needs two arenas, and
## [member service_scope] is how they coexist.

const CHANNEL := "dot2d.arena"
const SERVICE := &"dot_2d_arena"

## An entity was registered or forgotten.
signal entity_registered(id: int)
signal entity_forgotten(id: int)

@export_group("World")

## The playable rectangle, in world units.
@export var bounds: Rect2 = Rect2(Vector2(-2000.0, -2000.0), Vector2(4000.0, 4000.0))

## Spatial hash cell size. Roughly the largest query radius: too small and a query
## walks many cells, too large and each cell holds everything.
@export_range(16.0, 4096.0, 16.0) var cell_size: float = 256.0

## Bounce entities off the edge rather than sliding them along it.
@export var bounce_off_walls: bool = false

@export_group("Interest")

## Half-width and half-height of what a client is told about, in world units.
##
## Generous rather than exact: a client that is told only what is on screen sees things
## pop in at the edge, and the margin is what buys the interpolation buffer time to
## have something to interpolate from.
@export var interest_extent: Vector2 = Vector2(1200.0, 800.0)

## Scale [member interest_extent] by an entity's radius, so a big blob sees further.
##
## In a mass-based game this is not a nicety: a blob wide enough to fill the screen
## cannot see anything it might eat without it.
@export var interest_scales_with_size: bool = true

@export_group("Service")

@export var register_service: bool = true

@export var service_scope: StringName = &""

## Everything's position and radius.
var grid: Dot2DGrid = null

## What entities collide against.
var body: Dot2DBodyFlat = null

## id -> [Dot2DState] for entities that registered one.
var _states: Dictionary = {}

var _registered_name: StringName = &""


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	setup()


func _exit_tree() -> void:
	if _registered_name != &"":
		DotRegistry.unregister_instance(_registered_name, self)
		_registered_name = &""


func setup() -> DotResult:
	if grid == null:
		grid = Dot2DGrid.new(cell_size)

	if body == null:
		body = Dot2DBodyFlat.in_bounds(bounds)

	body.bounds = bounds
	body.bounce = bounce_off_walls

	if register_service:
		_registered_name = (
			DotRegistry.scoped_name(SERVICE, service_scope)
			if service_scope != &""
			else SERVICE
		)
		DotRegistry.register(_registered_name, self)

	return DotResult.success(null)


# --- Entities --------------------------------------------------------------

## Registers a state so the arena keeps its grid entry up to date.
##
## The alternative — every entity calling `grid.place` itself — is one entity that
## forgets, which is an entity nothing can see and which sees nothing, with no error.
func register(id: int, state: Dot2DState) -> void:
	if id == 0 or state == null:
		return

	_states[id] = state
	grid.place(id, state.position, state.radius)
	entity_registered.emit(id)


func forget(id: int) -> void:
	if not _states.has(id):
		return

	_states.erase(id)
	grid.remove(id)
	entity_forgotten.emit(id)


func state_of(id: int) -> Dot2DState:
	return _states.get(id)


func entity_ids() -> Array[int]:
	var out: Array[int] = []
	for key in _states.keys():
		out.append(int(key))
	out.sort()
	return out


func entity_count() -> int:
	return _states.size()


## Re-places every registered entity into the grid.
##
## Called once per tick, after the simulation and before any query. Doing it inside the
## motor would make the motor depend on the arena; doing it lazily per query would
## re-place the same entity many times a tick.
func sync_grid() -> void:
	for key in _states.keys():
		var state: Dot2DState = _states[key]

		if state == null or not state.active:
			grid.remove(int(key))
			continue

		grid.place(int(key), state.position, state.radius)


## Everything overlapping a circle. What eating and collision are built on.
func overlapping(centre: Vector2, radius: float, exclude: int = 0) -> Array[int]:
	return grid.query_overlapping(centre, radius, exclude)


## Everything within a rectangle. What interest management is built on.
func within(rect: Rect2, exclude: int = 0) -> Array[int]:
	return grid.query_rect(rect, exclude)


## The rectangle an entity should be told about.
func interest_rect(id: int) -> Rect2:
	var state := state_of(id)

	if state == null:
		return Rect2()

	var extent := interest_extent

	if interest_scales_with_size:
		# Linear in radius rather than in mass: a blob's radius is what fills the
		# screen, and mass grows as the square of it.
		extent *= maxf(1.0, state.radius / 32.0)

	return Rect2(state.position - extent, extent * 2.0)


## Everything [param id] should be told about.
func interest_set(id: int) -> Array[int]:
	var rect := interest_rect(id)

	if rect.size == Vector2.ZERO:
		return []

	return grid.query_rect(rect, id)


## Clamps a position into the arena, accounting for a radius.
func clamp_position(position: Vector2, radius: float = 0.0) -> Vector2:
	return Vector2(
		clampf(position.x, bounds.position.x + radius, bounds.end.x - radius),
		clampf(position.y, bounds.position.y + radius, bounds.end.y - radius),
	)


## A deterministic spawn position for [param key], away from the arena edge.
##
## Deterministic so a server and a replay agree. A game that wants a safe spawn — away
## from anything bigger — filters candidates itself with [method overlapping]; this is
## the placement, not the policy.
func spawn_position(key: int, inset: float = 64.0) -> Vector2:
	var h := Dot2DScatter._hash(key, 0x5A17)
	var inner := Rect2(
		bounds.position + Vector2(inset, inset),
		Vector2(
			maxf(1.0, bounds.size.x - inset * 2.0),
			maxf(1.0, bounds.size.y - inset * 2.0)
		)
	)

	return Vector2(
		inner.position.x + Dot2DScatter._unit(h) * inner.size.x,
		inner.position.y + Dot2DScatter._unit(Dot2DScatter._hash(h, 1)) * inner.size.y,
	)


func describe() -> Dictionary:
	return {
		"bounds": bounds,
		"entities": _states.size(),
		"grid": grid.describe() if grid != null else {},
		"interest": interest_extent,
	}


func describe_lines() -> PackedStringArray:
	var stats := grid.describe() if grid != null else {}
	return PackedStringArray([
		"arena    %.0f x %.0f" % [bounds.size.x, bounds.size.y],
		"entities %d in %d cells (largest %d)" % [
			_states.size(),
			int(stats.get("cells", 0)),
			int(stats.get("largest_cell", 0)),
		],
	])
