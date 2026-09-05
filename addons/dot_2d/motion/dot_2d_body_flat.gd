class_name Dot2DBodyFlat
extends Dot2DBody

## An arena rectangle and a list of solid circles. Analytic, and exact.
##
## **This is the production backend for a bounded-arena game**, not a test stub. An
## agar.io world is a rectangle with nothing in it; a twin-stick arena is a rectangle
## with some pillars. Both are cheaper and more predictable here than in the physics
## server, and both give the same answer on every machine — which is what makes the
## movement predictable at all.

## The playable rectangle. Zero size means unbounded.
var bounds: Rect2 = Rect2()

## Solid circles: `Vector3(x, y, radius)`.
##
## Packed into a `Vector3` rather than held as objects because this list is walked per
## entity per tick, and an array of `RefCounted`s is a pointer chase per element.
var obstacles: Array[Vector3] = []

## Bounce off the arena edge rather than sliding along it.
var bounce: bool = false

## Fraction of speed kept in a bounce. Only read when [member bounce] is on.
var restitution: float = 0.5


static func in_bounds(rect: Rect2) -> Dot2DBodyFlat:
	var body := Dot2DBodyFlat.new()
	body.bounds = rect
	return body


static func centred(size: Vector2) -> Dot2DBodyFlat:
	return in_bounds(Rect2(-size * 0.5, size))


func add_obstacle(centre: Vector2, radius: float) -> Dot2DBodyFlat:
	obstacles.append(Vector3(centre.x, centre.y, radius))
	return self


func clear_obstacles() -> void:
	obstacles.clear()


func move(from: Vector2, motion: Vector2, radius: float) -> Hit:
	var hit := Hit.new()
	var target := from + motion

	# Obstacles first, then bounds. A push out of an obstacle can put the entity
	# outside the arena, and clamping afterwards is what stops it staying there.
	var blocked_by_obstacle := false

	for obstacle in obstacles:
		var centre := Vector2(obstacle.x, obstacle.y)
		var combined := obstacle.z + radius
		var offset := target - centre
		var distance := offset.length()

		if distance >= combined:
			continue

		blocked_by_obstacle = true

		# A dead-centre overlap has no direction to push along, and normalising a zero
		# vector gives zero — which leaves the entity inside the obstacle forever.
		var away := (
			offset / distance if distance > 0.0001
			else (from - centre).normalized()
		)

		if away.length_squared() < 0.5:
			away = Vector2.RIGHT

		target = centre + away * combined
		hit.normal = away

	var clamped := _clamp_to_bounds(target, radius)

	if not clamped.is_equal_approx(target):
		hit.normal = _bounds_normal(target, radius)
		target = clamped
		hit.blocked = true

	hit.blocked = hit.blocked or blocked_by_obstacle
	hit.position = target
	return hit


func overlaps(at: Vector2, radius: float) -> bool:
	if bounds.size != Vector2.ZERO:
		if (
			at.x - radius < bounds.position.x
			or at.y - radius < bounds.position.y
			or at.x + radius > bounds.end.x
			or at.y + radius > bounds.end.y
		):
			return true

	for obstacle in obstacles:
		if at.distance_to(Vector2(obstacle.x, obstacle.y)) < obstacle.z + radius:
			return true

	return false


## Reflects a velocity off whatever [method move] reported hitting.
##
## Separate from [method move] because the motor decides what a wall does to a
## velocity, and a body that also changed the velocity would be two owners of it.
func reflect(velocity: Vector2, hit: Hit) -> Vector2:
	if not hit.blocked or hit.normal == Vector2.ZERO:
		return velocity

	if bounce:
		return velocity.bounce(hit.normal) * restitution

	# Slide: remove the component into the surface, keep the rest. A wall that stopped
	# an entity dead makes moving along it impossible, which in a bounded arena means
	# the edges are traps.
	return velocity.slide(hit.normal)


func _clamp_to_bounds(at: Vector2, radius: float) -> Vector2:
	if bounds.size == Vector2.ZERO:
		return at

	# An entity wider than the arena would clamp to a negative range, so the axis is
	# centred instead. It is degenerate, and a blob that has eaten the whole map
	# reaches it.
	var min_x := bounds.position.x + radius
	var max_x := bounds.end.x - radius
	var min_y := bounds.position.y + radius
	var max_y := bounds.end.y - radius

	return Vector2(
		(bounds.position.x + bounds.end.x) * 0.5 if min_x > max_x
			else clampf(at.x, min_x, max_x),
		(bounds.position.y + bounds.end.y) * 0.5 if min_y > max_y
			else clampf(at.y, min_y, max_y),
	)


func _bounds_normal(at: Vector2, radius: float) -> Vector2:
	var normal := Vector2.ZERO

	if at.x - radius < bounds.position.x:
		normal.x = 1.0
	elif at.x + radius > bounds.end.x:
		normal.x = -1.0

	if at.y - radius < bounds.position.y:
		normal.y = 1.0
	elif at.y + radius > bounds.end.y:
		normal.y = -1.0

	return normal.normalized() if normal != Vector2.ZERO else Vector2.ZERO


func describe() -> Dictionary:
	var out := super.describe()
	out["bounds"] = bounds
	out["obstacles"] = obstacles.size()
	out["bounce"] = bounce
	return out
