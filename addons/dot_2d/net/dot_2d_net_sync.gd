class_name Dot2DNetSync
extends RefCounted

## What a networked 2D entity replicates, and how to move it in and out of a
## [Dot2DState].
##
## [b]dot-net is not a dependency and is not imported here.[/b] Only dot-core is a hard
## dependency in this family, and a script that [i]mentions[/i] a [code]class_name[/code]
## the project does not have fails to parse. Types are named as strings and a bridge
## resolves them with [code]DotNetVar.Type[spec.type][/code].
##
## [codeblock]
## class_name BlobNet extends DotNetBehaviour
##
## @export var controller: Dot2DController
##
## var net_position: Vector2
## var net_velocity: Vector2
## var net_mass: float
## var net_flags: int
##
## func _register_net_vars() -> void:
##     for spec in Dot2DNetSync.specs():
##         var declaration := replicate(spec.property, DotNetVar.Type[spec.type])
##         if spec.bits > 0:
##             declaration.bits(spec.bits)
##         if spec.interpolated:
##             declaration.interpolated()
##
## func _net_simulate(tick: int, delta: float) -> void:
##     controller.simulate_tick(tick, delta)
##     Dot2DNetSync.pull(controller.state, self)
##
## func _net_state_applied(_tick: int) -> void:
##     Dot2DNetSync.push(self, controller.state)
## [/codeblock]

## World extent the position is quantised against, in each direction from the origin.
##
## Must match the arena, and both peers must agree. Too small and distant entities wrap
## to the wrong place; too large and every position costs bits it did not need.
const WORLD_EXTENT := 8192.0

const POSITION_BITS := 20
const VELOCITY_EXTENT := 4096.0
const VELOCITY_BITS := 14
const MASS_BITS := 20
const MASS_MAX := 1000000.0
const FLAG_BITS := 16


## Position and velocity are `CUSTOM`, not a built-in type.
##
## dot-net's quantised vector types are three-component; a 2D game paying for a Z it
## never uses is a third of its position bandwidth wasted, and on a world with two
## thousand entities that is the difference between fitting in a packet and not. The
## codecs below are what a bridge passes to `replicate_custom`.
static func specs() -> Array[Dictionary]:
	return [
		{
			"property": &"net_position",
			"type": "CUSTOM",
			"bits": 0,
			"interpolated": true,
			"custom": true,
		},
		{
			"property": &"net_velocity",
			"type": "CUSTOM",
			"bits": 0,
			"interpolated": false,
			"custom": true,
		},
		{
			"property": &"net_mass",
			"type": "UINT",
			"bits": MASS_BITS,
			"interpolated": true,
			"custom": false,
		},
		{
			"property": &"net_flags",
			"type": "UINT",
			"bits": FLAG_BITS,
			"interpolated": false,
			"custom": false,
		},
	]


static func properties() -> Array[StringName]:
	var out: Array[StringName] = []
	for spec in specs():
		out.append(spec["property"])
	return out


## Writes a position. Pass to `replicate_custom` for `net_position`.
##
## [param writer] is [Variant] for the same no-dot-net-identifier reason as everything
## else here.
static func write_position(writer: Variant, value: Variant) -> void:
	var position: Vector2 = value if value is Vector2 else Vector2.ZERO
	writer.write_vector2_range(position, -WORLD_EXTENT, WORLD_EXTENT, POSITION_BITS)


static func read_position(reader: Variant) -> Variant:
	return reader.read_vector2_range(-WORLD_EXTENT, WORLD_EXTENT, POSITION_BITS)


static func write_velocity(writer: Variant, value: Variant) -> void:
	var velocity: Vector2 = value if value is Vector2 else Vector2.ZERO
	writer.write_vector2_range(velocity, -VELOCITY_EXTENT, VELOCITY_EXTENT, VELOCITY_BITS)


static func read_velocity(reader: Variant) -> Variant:
	return reader.read_vector2_range(-VELOCITY_EXTENT, VELOCITY_EXTENT, VELOCITY_BITS)


## Copies the simulation state onto a replicating object.
##
## Mass is quantised to a whole number. A blob's mass is displayed as an integer, it
## compares exactly, and a reconciling client is not corrected every tick because the
## server's 412.0001 differs from its own 412.0.
static func pull(state: Dot2DState, target: Object) -> void:
	if state == null or target == null:
		return

	target.set(&"net_position", state.position)
	target.set(&"net_velocity", state.velocity)
	target.set(
		&"net_mass", clampi(int(round(state.mass)), 0, (1 << MASS_BITS) - 1)
	)
	target.set(&"net_flags", state.flags & ((1 << FLAG_BITS) - 1))


## Copies received state back into the simulation, on a peer that is not authoritative.
##
## [param rules] recomputes the radius from the received mass. Replicating the radius
## as well would be a second copy of something already derivable, and the two would
## eventually disagree by a rounding error and put an entity's eat radius and its drawn
## radius in different places.
static func push(
	source: Object,
	state: Dot2DState,
	rules: Dot2DMassRules = null
) -> void:
	if source == null or state == null:
		return

	state.position = source.get(&"net_position")
	state.velocity = source.get(&"net_velocity")
	state.mass = float(source.get(&"net_mass"))
	state.flags = int(source.get(&"net_flags"))

	if rules != null:
		state.radius = rules.radius_for(state.mass)


## Bits one entity's full state costs. For a bandwidth estimate.
##
## The number that decides whether a crowded world fits. At 104 bits an entity, the
## hundred entities a client can see at once are about 1.3 kB a snapshot — which is
## why [member Dot2DConfig.max_interest_entities] exists, and why the position codec
## is 2D rather than dot-net's three-component one: paying for a Z that is always zero
## would add another 40%.
static func estimated_bits() -> int:
	return POSITION_BITS * 2 + VELOCITY_BITS * 2 + MASS_BITS + FLAG_BITS
