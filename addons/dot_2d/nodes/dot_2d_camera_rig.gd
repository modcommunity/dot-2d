@tool
class_name Dot2DCameraRig
extends Camera2D

## Follows an entity, zooms with its size, and stays inside the arena.
##
## Three things a 2D camera has to do that are individually trivial and interact:
## zooming out shows more world, which changes what "inside the arena" means, which
## changes how far the camera may follow.
##
## [b]It follows the render position, not the simulation state.[/b] A camera snapped to
## a tick-rate position judders at any frame rate that is not the tick rate, which is
## every frame rate.

const CHANNEL := "dot2d.camera"

@export_group("Target")

## What to follow. A [Node2D]; usually the controlled entity.
@export var target_ref: DotNodeRef = null

## Seconds to catch up. Zero snaps.
@export_range(0.0, 2.0, 0.01) var follow_sec: float = 0.12

@export_group("Zoom")

## Zoom out as the target grows. What a blob game needs.
@export var zoom_with_size: bool = true

## Radius at which the zoom is exactly [member base_zoom].
@export_range(1.0, 1000.0, 1.0) var reference_radius: float = 32.0

@export_range(0.05, 8.0, 0.01) var base_zoom: float = 1.0

## Zoom falls as radius to this power.
##
## 0.5 keeps the *fraction of the screen* the entity fills roughly constant, which is
## what makes a blob game readable at every size — a linear relationship makes a large
## blob fill the same number of pixels as a small one, which removes the sense of scale
## entirely.
@export_range(0.0, 1.5, 0.05) var zoom_exponent: float = 0.5

@export_range(0.05, 8.0, 0.01) var min_zoom: float = 0.18
@export_range(0.05, 8.0, 0.01) var max_zoom: float = 2.0

## Seconds the zoom takes to catch up. Slower than the follow on purpose: a zoom that
## tracks every mass change is a camera that pulses while you eat.
@export_range(0.0, 5.0, 0.05) var zoom_sec: float = 0.45

@export_group("Bounds")

## Keep the view inside the arena. Resolved from the arena when one is bound.
@export var clamp_to_arena: bool = true

@export var arena_ref: DotNodeRef = null

var _target: Node2D = null
var _arena: Dot2DArena = null
var _zoom_target: float = 1.0


func _ready() -> void:
	if Engine.is_editor_hint():
		return

	if target_ref != null:
		_target = target_ref.resolve_or_null(self, CHANNEL) as Node2D

	if arena_ref != null:
		_arena = arena_ref.resolve_or_null(self, CHANNEL) as Dot2DArena

	_zoom_target = base_zoom
	zoom = Vector2(base_zoom, base_zoom)

	# The camera positions itself; letting Godot's own smoothing run as well is two
	# owners of the same value and reads as a camera that lags twice.
	position_smoothing_enabled = false


## Follows [param node]. For a target that is spawned at runtime.
func follow(node: Node2D) -> void:
	_target = node

	if node != null:
		global_position = node.global_position


func bind_arena(arena: Dot2DArena) -> void:
	_arena = arena


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return

	if _target == null or not is_instance_valid(_target):
		return

	_follow(delta)
	_zoom(delta)
	_clamp()


func _follow(delta: float) -> void:
	if follow_sec <= 0.0:
		global_position = _target.global_position
		return

	global_position = global_position.lerp(
		_target.global_position, clampf(delta / follow_sec, 0.0, 1.0)
	)


func _zoom(delta: float) -> void:
	if not zoom_with_size:
		return

	var radius := _target_radius()

	if radius > 0.0:
		_zoom_target = clampf(
			base_zoom * pow(reference_radius / maxf(0.001, radius), zoom_exponent),
			min_zoom,
			max_zoom
		)

	var current := zoom.x
	var next := (
		_zoom_target if zoom_sec <= 0.0
		else lerpf(current, _zoom_target, clampf(delta / zoom_sec, 0.0, 1.0))
	)

	zoom = Vector2(next, next)


## The target's radius, from a [Dot2DController] if it has one.
##
## Duck-typed rather than requiring a controller, so a camera can follow anything —
## a plain sprite, a cursor, a cinematic marker — and simply not zoom.
func _target_radius() -> float:
	if _target.has_method(&"describe") and _target is Dot2DController:
		return (_target as Dot2DController).state.radius

	return 0.0


## Keeps the visible rectangle inside the arena.
##
## The half-extent depends on the zoom, which is why this runs after [method _zoom]:
## clamping against last frame's zoom lets a corner of the world show through for one
## frame every time the camera zooms out.
func _clamp() -> void:
	if not clamp_to_arena or _arena == null or not is_instance_valid(_arena):
		return

	var bounds := _arena.bounds

	if bounds.size == Vector2.ZERO:
		return

	var half := get_viewport_rect().size * 0.5 * zoom

	# A view wider than the world is centred rather than clamped to a negative range,
	# which is the normal case for a small arena or a very zoomed-out blob.
	var min_x := bounds.position.x + half.x
	var max_x := bounds.end.x - half.x
	var min_y := bounds.position.y + half.y
	var max_y := bounds.end.y - half.y

	global_position = Vector2(
		(bounds.position.x + bounds.end.x) * 0.5 if min_x > max_x
			else clampf(global_position.x, min_x, max_x),
		(bounds.position.y + bounds.end.y) * 0.5 if min_y > max_y
			else clampf(global_position.y, min_y, max_y),
	)


## The world rectangle currently visible. What interest management can be checked
## against, and what a minimap draws.
func visible_rect() -> Rect2:
	var half := get_viewport_rect().size * 0.5 * zoom
	return Rect2(global_position - half, half * 2.0)


func describe() -> Dictionary:
	return {
		"target": _target.name if _target != null else "<none>",
		"zoom": zoom.x,
		"zoom_target": _zoom_target,
		"position": global_position,
		"clamped": clamp_to_arena and _arena != null,
	}
