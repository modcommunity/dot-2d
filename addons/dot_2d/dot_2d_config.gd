@tool
class_name Dot2DConfig
extends DotConfig

## Everything configurable about the 2D layer. Layered like every [DotConfig]:
## exported defaults, then a JSON file, then [code]DOT_2D_*[/code] environment
## variables, then [code]--2d-*[/code] arguments.

@export_group("Simulation")

## Must match the netcode's rate and every controller's.
@export_range(1, 240, 1) var tick_rate: int = 60

## Ticks one frame may catch up by after a stall.
##
## A frame that simulated an unbounded backlog is a second of movement in one frame,
## which reads as a player teleporting.
@export_range(1, 60, 1) var max_catchup_ticks: int = 8

@export_group("World")

@export var world_size: Vector2 = Vector2(4000.0, 4000.0)

@export_range(16.0, 4096.0, 16.0) var cell_size: float = 256.0

@export_range(0, 20000, 50) var scatter_count: int = 800

@export_range(0, 512, 1) var scatter_refill_per_tick: int = 8

@export_group("Interest")

@export var interest_extent: Vector2 = Vector2(1200.0, 800.0)

## Entities one client is told about at once.
##
## The bound that keeps a browser client playable: a player in the middle of a crowded
## world can otherwise be in interest range of everything at once.
@export_range(16, 4096, 16) var max_interest_entities: int = 400

@export_group("Anti-cheat")

## Largest pointer distance a client may report, in world units.
##
## Clamped rather than trusted: the reach is a speed multiplier in pointer mode, and a
## client reporting a reach of ten thousand is a client moving ten thousand times too
## fast.
@export_range(1.0, 20000.0, 10.0) var max_reach: float = 1000.0


func env_prefix() -> String:
	return "DOT_2D_"


func cli_prefix() -> String:
	return "--2d-"


func validate() -> DotResult:
	if world_size.x <= 0.0 or world_size.y <= 0.0:
		return DotResult.fail(DotError.CODE_INVALID, "A world with no size.")

	if cell_size > minf(world_size.x, world_size.y):
		DotLog.warn(
			"dot2d.config",
			"the grid cell is larger than the world, so every entity is in one cell "
			+ "and the spatial hash does nothing"
		)

	return DotResult.success(null)


## The arena rectangle, centred on the origin.
func world_bounds() -> Rect2:
	return Rect2(-world_size * 0.5, world_size)


func describe_summary() -> String:
	return "%.0fx%.0f, %d Hz, %d scatter" % [
		world_size.x, world_size.y, tick_rate, scatter_count
	]


## Puts the simulation fields on a controller. A [Dot2DConfig] is a document; the
## nodes read their own exports, and this is how the two meet. Until it existed
## nothing read this config at all — every field was documented and applied by
## nothing, which is the family's recurring bug and, here, a whole resource of it.
func apply_to_controller(controller: Dot2DController) -> void:
	if controller == null:
		return
	controller.tick_rate = tick_rate
	controller.max_catchup_ticks = max_catchup_ticks


## Puts the world fields on a scatter field.
func apply_to_scatter(scatter: Dot2DScatter) -> void:
	if scatter == null:
		return
	scatter.target_count = scatter_count
	scatter.refill_budget = scatter_refill_per_tick
