extends "res://examples/dot_2d_selftest_base.gd"

## Self-test layer: command, state, mass, tunables, body, motor and determinism.


func _test_command() -> void:
	_section("command")

	var command := Dot2DCommand.new()
	command.set_button(Dot2DCommand.BUTTON_SPLIT, true)
	_check(command.is_pressed(Dot2DCommand.BUTTON_SPLIT), "a button sets")

	var previous := Dot2DCommand.new()
	_check(
		command.just_pressed(Dot2DCommand.BUTTON_SPLIT, previous),
		"and reads as an edge against a command that did not have it"
	)
	_check(
		not command.just_pressed(Dot2DCommand.BUTTON_SPLIT, command),
		"and not against one that did"
	)

	# The single most common cheat in a client-driven game: a move vector longer than
	# one, which is a player who simply moves faster than everyone else.
	var cheat := Dot2DCommand.new()
	cheat.move = Vector2(40.0, 40.0)
	cheat.aim = Vector2(0.0, 900.0)
	cheat.reach = 999999.0
	cheat.buttons = 0xFFFFFFFF
	cheat.sanitise(1000.0)

	_close(cheat.move.length(), 1.0, "an over-long move vector is clamped")
	_close(cheat.aim.length(), 1.0, "and the aim is normalised")
	_close(cheat.reach, 1000.0, "and the reach is capped")
	_check(
		cheat.buttons < (1 << Dot2DCommand.BUTTON_BITS),
		"and unknown buttons are masked off"
	)

	var nan_command := Dot2DCommand.new()
	nan_command.move = Vector2(NAN, NAN)
	nan_command.aim = Vector2(NAN, 1.0)
	nan_command.reach = NAN
	nan_command.sanitise()
	_check(nan_command.move == Vector2.ZERO, "a NaN move becomes zero")
	_check(nan_command.aim == Vector2.ZERO, "and so does a NaN aim")
	_close(nan_command.reach, 0.0, "and a NaN reach")

	# A zero aim must stay zero rather than becoming an arbitrary direction.
	var still := Dot2DCommand.new()
	still.aim = Vector2.ZERO
	still.sanitise()
	_check(still.aim == Vector2.ZERO, "a zero aim is left as zero, not normalised")

	var copy := command.duplicate_command()
	_check(copy.equals(command), "a command duplicates")
	_done()


func _test_state() -> void:
	_section("state")

	var state := Dot2DState.at(Vector2(10.0, 20.0), 5.0)
	_check(state.position == Vector2(10.0, 20.0), "a state holds a position")

	state.set_flag(4, true)
	_check(state.has_flag(4), "and flags")

	var copy := state.duplicate_state()
	_check(copy.position == state.position, "and duplicates")

	# The tolerance is what stops a client being corrected on every tick: two machines
	# doing the same float arithmetic in a different order do not agree bit for bit.
	copy.position += Vector2(0.01, 0.0)
	_check(copy.matches(state, 0.05), "a near-identical state matches within tolerance")

	copy.position += Vector2(1.0, 0.0)
	_check(not copy.matches(state, 0.05), "and a genuinely different one does not")

	copy.copy_from(state)
	copy.flags = 8
	_check(not copy.matches(state), "differing flags never match, whatever the tolerance")
	_done()


# --- Mass ------------------------------------------------------------------

func _test_mass_rules() -> void:
	_section("mass rules")

	var rules := Dot2DMassRules.cell_eating()
	_check(rules.validate().ok, "the default rules validate")

	# The relationship the whole genre balances on: twice the mass is √2 the width, so
	# two small blobs are worth the same area as one big one.
	var small := rules.radius_for(100.0)
	var big := rules.radius_for(200.0)
	_close(big / small, sqrt(2.0), "twice the mass is root-two the radius", 0.001)

	_close(
		rules.mass_for(rules.radius_for(437.0)),
		437.0,
		"radius and mass are exact inverses",
		0.01
	)

	_check(
		rules.speed_scale(1000.0) < rules.speed_scale(10.0),
		"a heavier blob is slower"
	)
	_check(
		rules.speed_scale(100000000.0) >= rules.min_speed_scale,
		"but never below the floor, or the leader simply stops playing"
	)

	# Eating: the ratio and the distance, both in one call.
	var eater_radius := rules.radius_for(200.0)
	_check(
		rules.can_eat(200.0, eater_radius, 100.0, 1.0),
		"a much bigger blob on top of a smaller one eats it"
	)
	_check(
		not rules.can_eat(200.0, eater_radius, 190.0, 1.0),
		"a barely bigger one does not"
	)
	_check(
		not rules.can_eat(200.0, eater_radius, 100.0, eater_radius * 2.0),
		"and neither does one that is nowhere near"
	)

	_close(rules.absorb(200.0, 100.0), 300.0, "absorbing adds the victim's mass")

	# Decay: exponential, so the rate is the same fraction at every size.
	_close(rules.decay(100.0, 10.0), 100.0, "small blobs never decay")
	_check(rules.decay(1000.0, 1.0) < 1000.0, "large ones do")
	_check(
		rules.decay(1000.0, 60.0) > rules.decay_floor,
		"but never below the floor"
	)

	var equal := Dot2DMassRules.new()
	equal.eat_ratio = 1.0
	_check(
		not equal.validate().ok,
		"an eat ratio of 1 is refused, because two equal blobs would each eat the other"
	)

	var stuck := Dot2DMassRules.new()
	stuck.min_speed_scale = 0.0
	_check(
		not stuck.validate().ok,
		"a speed floor of zero is refused for the same kind of reason"
	)
	_done()


func _test_tunables() -> void:
	_section("tunables")

	_check(Dot2DTunables.topdown().validate().ok, "the top-down preset validates")
	_check(Dot2DTunables.blob().validate().ok, "the blob preset validates")
	_check(Dot2DTunables.thrust().validate().ok, "the thrust preset validates")

	_check(Dot2DTunables.blob().uses_aim(), "blob mode follows the pointer")
	_check(not Dot2DTunables.topdown().uses_aim(), "and top-down does not by default")

	var no_rules := Dot2DTunables.new()
	no_rules.mode = Dot2DTunables.Mode.BLOB
	_check(
		not no_rules.validate().ok,
		"blob mode without mass rules is refused"
	)

	var degenerate := Dot2DTunables.new()
	degenerate.dead_reach = 200.0
	degenerate.full_speed_reach = 100.0
	_check(
		not degenerate.validate().ok,
		"a dead zone past the full-speed distance is refused"
	)
	_done()


# --- Body ------------------------------------------------------------------

func _test_body_bounds() -> void:
	_section("body: bounds")

	var body := Dot2DBodyFlat.centred(Vector2(1000.0, 1000.0))

	var clear := body.move(Vector2.ZERO, Vector2(100.0, 0.0), 10.0)
	_check(not clear.blocked, "an unobstructed move is not blocked")
	_check(clear.position == Vector2(100.0, 0.0), "and goes where it was told")

	# The one that matters: a blob must not leave the world. Ever.
	var out := body.move(Vector2(400.0, 0.0), Vector2(1000.0, 0.0), 20.0)
	_check(out.blocked, "a move past the edge is blocked")
	_close(out.position.x, 480.0, "and stops a radius short of it")

	_check(
		not body.overlaps(Vector2.ZERO, 10.0),
		"a circle in the middle overlaps nothing"
	)
	_check(
		body.overlaps(Vector2(495.0, 0.0), 20.0),
		"and one poking through the wall does"
	)

	# A blob wider than the world. Degenerate, and a blob that has eaten everything
	# reaches it — clamping to a negative range would put it outside.
	var huge := body.move(Vector2.ZERO, Vector2(100.0, 0.0), 5000.0)
	_close(huge.position.x, 0.0, "an entity wider than the world is centred, not ejected")

	# Sliding, so the edges are not traps.
	var sliding := Dot2DBodyFlat.centred(Vector2(1000.0, 1000.0))
	var into_wall := sliding.move(Vector2(495.0, 0.0), Vector2(50.0, 50.0), 5.0)
	var slid := sliding.reflect(Vector2(50.0, 50.0), into_wall)
	_check(
		absf(slid.x) < 0.001 and slid.y > 0.0,
		"a slide keeps the along-wall component and drops the into-wall one",
		str(slid)
	)

	sliding.bounce = true
	sliding.restitution = 0.5
	var bounced := sliding.reflect(Vector2(50.0, 50.0), into_wall)
	_check(bounced.x < 0.0, "a bounce reverses it instead")
	_done()


func _test_body_obstacles() -> void:
	_section("body: obstacles")

	var body := Dot2DBodyFlat.centred(Vector2(2000.0, 2000.0))
	body.add_obstacle(Vector2(100.0, 0.0), 50.0)

	var into := body.move(Vector2.ZERO, Vector2(120.0, 0.0), 10.0)
	_check(into.blocked, "an obstacle blocks a move")
	_close(
		into.position.distance_to(Vector2(100.0, 0.0)),
		60.0,
		"and pushes the entity out to the combined radius"
	)

	var past := body.move(Vector2(0.0, 300.0), Vector2(200.0, 0.0), 10.0)
	_check(not past.blocked, "and a move that misses it is not blocked")

	# The degenerate case that leaves an entity stuck forever: a move landing exactly
	# on an obstacle's centre has no direction to be pushed along.
	var dead_centre := body.move(Vector2(100.0, 0.0), Vector2.ZERO, 10.0)
	_check(
		dead_centre.position.distance_to(Vector2(100.0, 0.0)) >= 59.0,
		"an entity exactly on an obstacle centre is still pushed out",
		str(dead_centre.position)
	)
	_done()


# --- Motor -----------------------------------------------------------------

func _test_motor_topdown() -> void:
	_section("motor: top-down")

	var tunables := Dot2DTunables.topdown()
	tunables.max_speed = 300.0
	tunables.acceleration = 3000.0
	tunables.friction = 3000.0

	var motor := Dot2DMotor.with_tunables(tunables)
	var state := Dot2DState.at(Vector2.ZERO)

	_run_ticks(motor, state, _move_command(Vector2.RIGHT), 60)

	_close(state.speed(), 300.0, "a held direction reaches top speed", 0.5)
	_check(state.position.x > 250.0, "and travels", str(state.position.x))
	_check(absf(state.position.y) < 0.001, "in a straight line")

	_run_ticks(motor, state, Dot2DCommand.new(), 60)
	_close(state.speed(), 0.0, "letting go stops it")

	# Diagonal must not be faster than cardinal. Normalising is what prevents the
	# oldest bug in 2D movement.
	var diagonal := Dot2DState.at(Vector2.ZERO)
	_run_ticks(motor, diagonal, _move_command(Vector2.ONE), 60)
	_close(diagonal.speed(), 300.0, "diagonal movement is not faster", 0.5)

	# Turn authority.
	tunables.turn_authority = 0.2
	var turning := Dot2DState.at(Vector2.ZERO)
	turning.velocity = Vector2(300.0, 0.0)
	_run_ticks(motor, turning, _move_command(Vector2.LEFT), 6)
	_check(
		turning.velocity.x > -300.0,
		"low turn authority makes reversing take time",
		str(turning.velocity.x)
	)
	tunables.turn_authority = 1.0

	# Facing follows travel, but not while stopping — or the entity spins as the
	# velocity crosses zero.
	var facing := Dot2DState.at(Vector2.ZERO)
	_run_ticks(motor, facing, _move_command(Vector2.UP), 30)
	_close(facing.facing, Vector2.UP.angle(), "facing follows the direction of travel", 0.05)
	var before := facing.facing
	_run_ticks(motor, facing, Dot2DCommand.new(), 60)
	_close(facing.facing, before, "and is left alone once stopped", 0.05)
	_done()


func _test_motor_blob() -> void:
	_section("motor: blob")

	var tunables := Dot2DTunables.blob()
	tunables.max_speed = 400.0
	tunables.full_speed_reach = 100.0
	tunables.dead_reach = 5.0

	var motor := Dot2DMotor.with_tunables(tunables)
	var state := Dot2DState.at(Vector2.ZERO)
	state.mass = 10.0

	motor.simulate(state, _aim_command(Vector2.RIGHT, 200.0), STEP, 0)
	var small_speed := state.speed()
	_check(small_speed > 0.0, "a small blob moves", "%.1f" % small_speed)

	# The trade the whole genre is built on.
	var heavy := Dot2DState.at(Vector2.ZERO)
	heavy.mass = 5000.0
	motor.simulate(heavy, _aim_command(Vector2.RIGHT, 200.0), STEP, 0)
	_check(
		heavy.speed() < small_speed,
		"and a big one is slower",
		"%.1f vs %.1f" % [heavy.speed(), small_speed]
	)

	# Fine positioning: a cursor close by moves the blob slowly.
	var near := Dot2DState.at(Vector2.ZERO)
	near.mass = 10.0
	motor.simulate(near, _aim_command(Vector2.RIGHT, 50.0), STEP, 0)
	_check(
		near.speed() < small_speed,
		"a nearby pointer moves it more slowly",
		"%.1f vs %.1f" % [near.speed(), small_speed]
	)

	# The dead zone, so a cursor resting on the blob does not jitter.
	var resting := Dot2DState.at(Vector2.ZERO)
	resting.mass = 10.0
	motor.simulate(resting, _aim_command(Vector2.RIGHT, 2.0), STEP, 0)
	_close(resting.speed(), 0.0, "a pointer inside the dead zone stops it entirely")

	# Radius must track mass every tick. Anything that queries in between — an eat
	# check, an interest rectangle — uses whichever is current.
	var growing := Dot2DState.at(Vector2.ZERO)
	growing.mass = 100.0
	motor.simulate(growing, Dot2DCommand.new(), STEP, 0)
	_close(
		growing.radius,
		tunables.mass_rules.radius_for(growing.mass),
		"radius is recomputed from mass every tick",
		0.001
	)

	# Blobs do not accelerate: the velocity is set outright.
	var instant := Dot2DState.at(Vector2.ZERO)
	instant.mass = 10.0
	motor.simulate(instant, _aim_command(Vector2.RIGHT, 200.0), STEP, 0)
	var first := instant.speed()
	motor.simulate(instant, _aim_command(Vector2.RIGHT, 200.0), STEP, 1)
	_close(instant.speed(), first, "a blob reaches its speed on the first tick", 0.5)
	_done()


func _test_motor_thrust() -> void:
	_section("motor: thrust")

	var tunables := Dot2DTunables.thrust()
	tunables.turn_rate = PI
	var motor := Dot2DMotor.with_tunables(tunables)

	var state := Dot2DState.at(Vector2.ZERO)
	state.facing = 0.0

	var turn := Dot2DCommand.new()
	turn.move = Vector2(1.0, 0.0)
	_run_ticks(motor, state, turn, 30)
	_close(state.facing, PI * 0.5, "turning rotates the facing", 0.1)

	var thrust := Dot2DCommand.new()
	thrust.set_button(Dot2DCommand.BUTTON_ACTION, true)
	state.facing = 0.0
	state.velocity = Vector2.ZERO
	_run_ticks(motor, state, thrust, 30)
	_check(state.velocity.x > 0.0, "thrusting accelerates along the facing")
	_check(absf(state.velocity.y) < 0.001, "and only along it")
	_done()


func _test_determinism() -> void:
	_section("determinism")

	var tunables := Dot2DTunables.blob()
	var body := Dot2DBodyFlat.centred(Vector2(2000.0, 2000.0))
	body.add_obstacle(Vector2(200.0, 50.0), 60.0)

	var commands: Array[Dot2DCommand] = []
	for index in range(180):
		var angle := float(index) * 0.11
		commands.append(_aim_command(Vector2.from_angle(angle), 40.0 + float(index)))

	# Two runs of the same inputs. This is the property everything else depends on: a
	# client that predicts a move and a server that re-runs it must reach the same
	# position, and a reconciliation replay must reach it a third time.
	var first := _replay(tunables, body, commands)
	var second := _replay(tunables, body, commands)

	_check(
		first.position == second.position,
		"the same inputs produce the same position, exactly",
		"%s vs %s" % [first.position, second.position]
	)
	_check(first.velocity == second.velocity, "and the same velocity")
	_check(first.mass == second.mass, "and the same mass")

	# A different input anywhere in the stream must diverge, or the test above would
	# pass for a motor that ignored its commands entirely.
	commands[90] = _aim_command(Vector2.UP, 500.0)
	var altered := _replay(tunables, body, commands)
	_check(
		altered.position != first.position,
		"and a changed input somewhere in the middle changes the outcome"
	)
	_done()


func _replay(
	tunables: Dot2DTunables,
	body: Dot2DBodyFlat,
	commands: Array[Dot2DCommand]
) -> Dot2DState:
	var motor := Dot2DMotor.with_tunables(tunables)
	motor.body = body

	var state := Dot2DState.at(Vector2(-300.0, -300.0))
	state.mass = 40.0

	for index in range(commands.size()):
		motor.simulate(state, commands[index], STEP, index)

	return state


# --- Grid ------------------------------------------------------------------
