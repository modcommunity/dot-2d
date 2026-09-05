class_name Dot2DBody
extends RefCounted

## What a 2D entity collides against.
##
## The same abstraction dot-fps-controller's [code]DotFpsBody[/code] is, for the same
## reason: a headless server, a self-test and a deterministic replay all need to move
## against a world and only one of the three has a populated physics space.
##
## [Dot2DBodyFlat] — an arena rectangle and a list of circles — is not a fallback. It
## is what an agar.io-like game actually collides against, and it gives bit-identical
## answers on a client and a server, which a physics query does not.


## What a move ran into.
class Hit extends RefCounted:
	## Where the move actually ended.
	var position: Vector2 = Vector2.ZERO

	## Surface normal at the contact, pointing away from what was hit.
	var normal: Vector2 = Vector2.ZERO

	## Whether anything was hit at all.
	var blocked: bool = false

	## What was hit, when the backend knows. Null for an arena wall.
	var collider: Object = null

	func _to_string() -> String:
		return "Hit(%s)" % ("clear" if not blocked else "blocked at %s" % position)


## Moves a circle from [param from] by [param motion] and reports where it ended.
##
## Must be deterministic given the same arguments. A backend that consults a physics
## solver whose internal state depends on what ran before it cannot be, which is why
## [Dot2DBodyPhysics] is documented as unsuitable for a predicted entity.
func move(
	_from: Vector2,
	_motion: Vector2,
	_radius: float
) -> Hit:
	var hit := Hit.new()
	hit.position = _from + _motion
	return hit


## Whether a circle at [param at] overlaps anything solid.
func overlaps(_at: Vector2, _radius: float) -> bool:
	return false


func describe() -> Dictionary:
	return {"backend": get_script().resource_path.get_file()}
