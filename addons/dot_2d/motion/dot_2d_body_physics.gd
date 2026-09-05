class_name Dot2DBodyPhysics
extends Dot2DBody

## Moves against Godot's 2D physics space.
##
## [b]Not suitable for a predicted entity.[/b] A physics query is a floating-point
## result from a solver whose internal state depends on what ran before it, and the
## space state is a step stale after anything moves. A client replaying a tick reaches
## a different answer than the server did, and reconciliation never converges.
##
## Use it for an unpredicted entity — a server-authoritative NPC, a projectile nobody
## predicts — or for a single-player game where none of that applies. A bounded arena
## should use [Dot2DBodyFlat], which is both faster and exact.

const CHANNEL := "dot2d.body"

var collision_mask: int = 1

var exclude: Array[RID] = []

var _world: World2D = null
var _query := PhysicsShapeQueryParameters2D.new()
var _shape := CircleShape2D.new()


static func for_world(world: World2D) -> Dot2DBodyPhysics:
	var body := Dot2DBodyPhysics.new()
	body.bind(world)
	return body


## Binds to a world. The [World2D] is kept; its space state is not.
##
## A [PhysicsDirectSpaceState2D] is invalidated at every physics step, so caching one
## either answers from the previous step or pushes an error. Fetching it per query is a
## property read.
func bind(world: World2D) -> void:
	if world == null:
		DotLog.warn(CHANNEL, "bound to a null world; nothing will collide")
		return
	_world = world


func bind_from_node(node: Node2D) -> void:
	if node == null or not node.is_inside_tree():
		DotLog.warn(CHANNEL, "bind_from_node() on a node outside the tree")
		return
	bind(node.get_world_2d())


func is_bound() -> bool:
	return _world != null


func move(from: Vector2, motion: Vector2, radius: float) -> Hit:
	var hit := Hit.new()
	hit.position = from + motion

	if _world == null:
		return hit

	var space := _world.direct_space_state

	if space == null:
		DotLog.warn(CHANNEL, "no space state; the move ran outside a physics step")
		return hit

	_shape.radius = radius
	_query.shape = _shape
	_query.transform = Transform2D(0.0, from)
	_query.motion = motion
	_query.collision_mask = collision_mask
	_query.exclude = exclude

	var fractions := space.cast_motion(_query)

	if fractions.is_empty():
		return hit

	var safe := float(fractions[0])

	if safe >= 1.0:
		return hit

	# Stop a whisker short of the contact. Ending exactly touching is the failure
	# dot-fps-controller documents at length: every subsequent query then reports the
	# same contact and the entity is stuck against it.
	hit.position = from + motion * maxf(0.0, safe - 0.001)
	hit.blocked = true

	_query.transform = Transform2D(0.0, hit.position)
	_query.motion = Vector2.ZERO

	var contacts := space.get_rest_info(_query)

	if not contacts.is_empty():
		hit.normal = contacts["normal"]

	return hit


func overlaps(at: Vector2, radius: float) -> bool:
	if _world == null:
		return false

	var space := _world.direct_space_state

	if space == null:
		return false

	_shape.radius = radius
	_query.shape = _shape
	_query.transform = Transform2D(0.0, at)
	_query.motion = Vector2.ZERO
	_query.collision_mask = collision_mask
	_query.exclude = exclude

	return not space.intersect_shape(_query, 1).is_empty()


func describe() -> Dictionary:
	var out := super.describe()
	out["bound"] = is_bound()
	out["mask"] = collision_mask
	return out
