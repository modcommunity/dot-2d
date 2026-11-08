extends "res://examples/dot_2d_selftest_world.gd"

## Self-test layer: the net-sync descriptors and the fakes they are tested against.


# --- Net sync --------------------------------------------------------------

## A stand-in for the DotNetBehaviour a game writes. Plain properties, because that is
## all [Dot2DNetSync] requires.
class FakeBehaviour extends Object:
	var net_position: Vector2 = Vector2.ZERO
	var net_velocity: Vector2 = Vector2.ZERO
	var net_mass: int = 0
	var net_flags: int = 0
	var net_admin: int = 0


## A behaviour written before `net_admin` existed. [method Dot2DNetSync.push] must still
## move it rather than aborting on the missing property.
class OlderBehaviour extends Object:
	var net_position: Vector2 = Vector2.ZERO
	var net_velocity: Vector2 = Vector2.ZERO
	var net_mass: int = 0
	var net_flags: int = 0


## A stand-in for DotNetWriter/DotNetReader, quantising the same way dot-net does.
class FakeWire extends RefCounted:
	var values: Array = []
	var index: int = 0

	func write_vector2_range(
		value: Vector2, min_value: float, max_value: float, bits: int
	) -> void:
		values.append(Vector2(
			_quantise(value.x, min_value, max_value, bits),
			_quantise(value.y, min_value, max_value, bits)
		))

	func read_vector2_range(
		_min_value: float, _max_value: float, _bits: int
	) -> Vector2:
		var out: Vector2 = values[index]
		index += 1
		return out

	static func _quantise(
		value: float, min_value: float, max_value: float, bits: int
	) -> float:
		var steps := float((1 << bits) - 1)
		var t := clampf((value - min_value) / (max_value - min_value), 0.0, 1.0)
		return min_value + roundf(t * steps) / steps * (max_value - min_value)


func _test_net_sync() -> void:
	_section("net sync")

	var specs := Dot2DNetSync.specs()
	_check(specs.size() == 5, "the bridge describes what replicates")

	var custom := 0
	for spec in specs:
		if bool(spec["custom"]):
			custom += 1
	_check(
		custom == 2,
		"position and velocity use a custom codec rather than a 3D vector type"
	)

	var state := Dot2DState.at(Vector2(123.4, -567.8), 12.0)
	state.velocity = Vector2(200.0, -100.0)
	state.mass = 412.0
	state.flags = 5

	var behaviour := FakeBehaviour.new()
	Dot2DNetSync.pull(state, behaviour)

	_check(behaviour.net_position == state.position, "position replicates")
	_check(behaviour.net_mass == 412, "mass replicates as a whole number")
	_check(behaviour.net_flags == 5, "and flags")

	# The received radius is derived, not replicated. Replicating both would let them
	# disagree by a rounding error and put the eat radius and the drawn radius in
	# different places.
	var received := Dot2DState.new()
	var rules := Dot2DMassRules.cell_eating()
	Dot2DNetSync.push(behaviour, received, rules)

	_check(received.position == state.position, "and comes back")
	_close(
		received.radius,
		rules.radius_for(412.0),
		"with the radius derived from the received mass rather than replicated"
	)

	# The quantisation the wire actually applies. A world extent that does not cover
	# the arena wraps distant entities to the wrong place.
	var wire := FakeWire.new()
	Dot2DNetSync.write_position(wire, Vector2(1234.5, -2345.6))
	var decoded: Vector2 = Dot2DNetSync.read_position(wire)
	_check(
		decoded.distance_to(Vector2(1234.5, -2345.6)) < 0.05,
		"a position survives quantisation to within a fraction of a unit",
		"%s" % decoded
	)

	var edge := FakeWire.new()
	Dot2DNetSync.write_position(edge, Vector2(Dot2DNetSync.WORLD_EXTENT, 0.0))
	var edge_back: Vector2 = Dot2DNetSync.read_position(edge)
	_close(
		edge_back.x,
		Dot2DNetSync.WORLD_EXTENT,
		"and the far edge of the world survives it too",
		0.05
	)

	# Sixteen bytes an entity is the number the interest cap is sized against: a
	# hundred entities in view is about 1.3 kB a snapshot.
	_check(
		Dot2DNetSync.estimated_bits() <= 128,
		"one entity's full state fits in sixteen bytes",
		"%d bits" % Dot2DNetSync.estimated_bits()
	)

	behaviour.free()
	_done()


# --- Admin modifiers ---------------------------------------------------------

## noclip, freeze and a speed step, as bits in the state. What matters is not that each
## does its thing on one machine — it is that a replay from a rewound copy reaches the
## same place, which is what a predicting client does, and that the same replay WITHOUT
## the bits does not, or the first check proves nothing.


func _test_command_neutralise() -> void:
	_section("command neutralise")
	var command := Dot2DCommand.new()
	command.move = Vector2(1.0, 0.0)
	command.aim = Vector2(0.0, 1.0)
	command.reach = 300.0
	command.set_button(Dot2DCommand.BUTTON_SPLIT, true)
	command.neutralise()
	_check(command.move == Vector2.ZERO and command.reach == 0.0 and command.buttons == 0,
		"neutralise stops the move, the reach and the buttons")
	_check(command.aim == Vector2(0.0, 1.0), "and keeps where it points")
	_done()
