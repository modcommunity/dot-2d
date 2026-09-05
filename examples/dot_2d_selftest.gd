extends Node

## Exercises everything in dot-2d, offline and headless.
##
## [codeblock]
## godot --headless --path . res://examples/dot_2d_selftest.tscn
## [/codeblock]
##
## Exits non-zero on any failure, so it works as a smoke test as-is.
##
## The cases that matter most are the ones an agar.io-like game reaches within a
## minute: a blob that walks out of the world, a spatial hash that misses an overlap it
## should have found, a scatter field that lays out differently on two machines, and a
## client whose predicted move disagrees with the server's.

const TICK_RATE := 60
const STEP := 1.0 / 60.0

var _passed := 0
var _failed := 0
var _failures := PackedStringArray()


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	_run.call_deferred()


func _run() -> void:
	print("dot-2d self-test")
	print("")

	_test_command()
	_test_state()
	_test_mass_rules()
	_test_tunables()
	_test_body_bounds()
	_test_body_obstacles()
	_test_motor_topdown()
	_test_motor_blob()
	_test_motor_thrust()
	_test_determinism()
	_test_grid()
	_test_grid_overlap()
	_test_scatter()
	_test_arena()
	_test_interest()
	_test_controller()
	_test_net_sync()

	print("")
	print("%d passed, %d failed" % [_passed, _failed])

	for line in _failures:
		print("  FAIL  %s" % line)

	get_tree().quit(1 if _failed > 0 else 0)


# --- Assertions ------------------------------------------------------------

func _check(condition: bool, what: String, detail: String = "") -> bool:
	if condition:
		_passed += 1
		print("  ok    %s" % what)
	else:
		_failed += 1
		_failures.append(what if detail == "" else "%s — %s" % [what, detail])
		print("  FAIL  %s%s" % [what, "" if detail == "" else " — " + detail])
	return condition


func _close(a: float, b: float, what: String, epsilon: float = 0.01) -> bool:
	return _check(absf(a - b) <= epsilon, what, "%.4f vs %.4f" % [a, b])


func _group(title: String) -> void:
	print("")
	print("%s" % title)


# --- Fixtures --------------------------------------------------------------

func _aim_command(direction: Vector2, reach: float = 1000.0) -> Dot2DCommand:
	var command := Dot2DCommand.new()
	command.aim = direction.normalized()
	command.reach = reach
	return command


func _move_command(direction: Vector2) -> Dot2DCommand:
	var command := Dot2DCommand.new()
	command.move = direction.limit_length(1.0)
	return command


func _run_ticks(
	motor: Dot2DMotor,
	state: Dot2DState,
	command: Dot2DCommand,
	count: int
) -> void:
	for tick in range(count):
		motor.simulate(state, command, STEP, tick)


# --- Command ---------------------------------------------------------------

func _test_command() -> void:
	_group("command")

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


func _test_state() -> void:
	_group("state")

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


# --- Mass ------------------------------------------------------------------

func _test_mass_rules() -> void:
	_group("mass rules")

	var rules := Dot2DMassRules.agar()
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


func _test_tunables() -> void:
	_group("tunables")

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


# --- Body ------------------------------------------------------------------

func _test_body_bounds() -> void:
	_group("body: bounds")

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


func _test_body_obstacles() -> void:
	_group("body: obstacles")

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


# --- Motor -----------------------------------------------------------------

func _test_motor_topdown() -> void:
	_group("motor: top-down")

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


func _test_motor_blob() -> void:
	_group("motor: blob")

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


func _test_motor_thrust() -> void:
	_group("motor: thrust")

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


func _test_determinism() -> void:
	_group("determinism")

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

func _test_grid() -> void:
	_group("grid")

	var grid := Dot2DGrid.new(100.0)

	grid.place(1, Vector2(10.0, 10.0), 5.0)
	grid.place(2, Vector2(20.0, 20.0), 5.0)
	grid.place(3, Vector2(900.0, 900.0), 5.0)

	_check(grid.size() == 3, "entities are placed")
	_check(grid.has(1), "and found by id")

	var near := grid.query_circle(Vector2(15.0, 15.0), 30.0)
	_check(near.size() == 2, "a circle query finds the nearby ones", str(near))
	_check(not near.has(3), "and not the distant one")

	# Exact, not merely bucketed: a caller must not have to re-check the distance.
	var tight := grid.query_circle(Vector2(10.0, 10.0), 5.0)
	_check(tight == [1], "a query is exact, not merely bucketed", str(tight))

	_check(
		grid.query_circle(Vector2(15.0, 15.0), 30.0, 1).size() == 1,
		"and the querying entity can exclude itself"
	)

	# Moving. place() is both add and move, because a caller that has to know which
	# gets it wrong for the entity removed and re-added on the same tick.
	grid.place(1, Vector2(900.0, 905.0), 5.0)
	_check(
		grid.query_circle(Vector2(15.0, 15.0), 30.0).size() == 1,
		"moving an entity takes it out of its old cell"
	)
	_check(
		grid.query_circle(Vector2(900.0, 900.0), 30.0).size() == 2,
		"and puts it in the new one"
	)

	grid.remove(1)
	_check(not grid.has(1), "removing works")
	_check(grid.size() == 2, "and the count follows")

	# Cells that empty must be dropped, or a world an entity has crossed once holds a
	# cell for every square it has ever been in.
	var walker := Dot2DGrid.new(50.0)
	for step in range(200):
		walker.place(1, Vector2(float(step) * 60.0, 0.0), 1.0)
	_check(
		walker.cell_count() == 1,
		"an entity crossing the world leaves no empty cells behind",
		str(walker.cell_count())
	)

	# Scale. This is the whole point of the class.
	var big := Dot2DGrid.new(128.0)
	for index in range(2000):
		big.place(index, Vector2(float(index % 50) * 80.0, float(index / 50) * 80.0), 4.0)
	var sample := big.query_circle(Vector2(400.0, 400.0), 150.0)
	_check(big.size() == 2000, "two thousand entities fit")
	_check(
		sample.size() > 0 and sample.size() < 40,
		"and a local query returns a handful rather than all of them",
		str(sample.size())
	)


func _test_grid_overlap() -> void:
	_group("grid: overlap")

	var grid := Dot2DGrid.new(100.0)

	grid.place(1, Vector2.ZERO, 10.0)
	# Centre 300 away, radius 300: its edge is at the query and its centre is far
	# outside it. Placing it further out would put it genuinely out of reach and the
	# case would pass for the wrong reason.
	grid.place(2, Vector2(300.0, 0.0), 300.0)

	# The case a centre-based query gets wrong: a large entity whose centre is far away
	# and whose edge is right here. Missing it is a blob you can stand inside and not
	# be eaten by.
	var touching := grid.query_overlapping(Vector2.ZERO, 10.0, 1)
	_check(
		touching.has(2),
		"a large entity whose edge reaches the query is found",
		str(touching)
	)

	var centres := grid.query_circle(Vector2.ZERO, 10.0, 1)
	_check(
		not centres.has(2),
		"which a centre query deliberately does not"
	)

	grid.place(3, Vector2(1000.0, 1000.0), 5.0)
	_check(
		not grid.query_overlapping(Vector2.ZERO, 10.0, 1).has(3),
		"and something genuinely far away is still not found"
	)


func _test_scatter() -> void:
	_group("scatter")

	var scatter := Dot2DScatter.over(
		Rect2(Vector2(-500.0, -500.0), Vector2(1000.0, 1000.0)), 100, 12345
	)

	var placed := scatter.fill()
	_check(placed.size() == 100, "a field fills to its target")
	_check(scatter.alive_count() == 100, "and reports it")

	# Determinism: a client can lay out the whole field from a seed rather than
	# receiving two thousand positions.
	var mirror := Dot2DScatter.over(
		Rect2(Vector2(-500.0, -500.0), Vector2(1000.0, 1000.0)), 100, 12345
	)
	_check(
		mirror.position_of(7) == scatter.position_of(7),
		"the same seed lays out the same field"
	)

	var other := Dot2DScatter.over(
		Rect2(Vector2(-500.0, -500.0), Vector2(1000.0, 1000.0)), 100, 999
	)
	_check(
		other.position_of(7) != scatter.position_of(7),
		"and a different seed lays out a different one"
	)

	# Everything stays inside, including the margin.
	var outside := 0
	for index in range(500):
		var at := scatter.position_of(index)
		if not scatter.bounds.has_point(at):
			outside += 1
	_check(outside == 0, "every slot is inside the world", "%d outside" % outside)

	# Spread: a hash that clustered would put every pellet in one corner.
	var quadrants := [0, 0, 0, 0]
	for index in range(400):
		var at := scatter.position_of(index)
		quadrants[(1 if at.x > 0.0 else 0) + (2 if at.y > 0.0 else 0)] += 1
	# Every quadrant must get roughly a quarter. This is the check that caught the
	# hash returning only the bottom half of its range, which put every pellet in one
	# corner of the world.
	var lowest := 400
	for count in quadrants:
		lowest = mini(lowest, int(count))
	_check(
		lowest > 60,
		"and the field covers every quadrant rather than clustering",
		str(quadrants)
	)

	# Taking, and the duplicate claim two clients both make at any latency.
	_check(scatter.take(3), "a slot is taken")
	_check(not scatter.take(3), "and cannot be taken twice")
	_check(scatter.alive_count() == 99, "leaving one fewer")

	# The budget, so a mass respawn is not one long frame.
	scatter.refill_budget = 5
	var refilled := scatter.refill()
	_check(refilled.size() == 1, "refilling replaces what was taken", str(refilled.size()))

	for index in range(50):
		scatter.take(index + 10)
	var batch := scatter.refill()
	_check(
		batch.size() == 5,
		"and never more than the budget in one tick",
		str(batch.size())
	)

	# A respawned slot must be a new position, not the one just eaten — or food comes
	# back under the player who took it.
	_check(
		scatter.position_of(batch[0]) != scatter.position_of(10),
		"a refilled slot is somewhere new"
	)

	var into_grid := Dot2DGrid.new(100.0)
	scatter.populate(into_grid, 100000, 4.0)
	_check(
		into_grid.size() == scatter.alive_count(),
		"a field populates a grid"
	)


# --- Arena -----------------------------------------------------------------

func _make_arena() -> Dot2DArena:
	var arena := Dot2DArena.new()
	arena.register_service = false
	arena.bounds = Rect2(Vector2(-1000.0, -1000.0), Vector2(2000.0, 2000.0))
	arena.cell_size = 200.0
	add_child(arena)
	return arena


func _test_arena() -> void:
	_group("arena")

	var arena := _make_arena()

	var a := Dot2DState.at(Vector2(0.0, 0.0), 10.0)
	var b := Dot2DState.at(Vector2(50.0, 0.0), 10.0)

	arena.register(1, a)
	arena.register(2, b)

	_check(arena.entity_count() == 2, "entities register")
	_check(arena.state_of(1) == a, "and are found by id")

	_check(
		arena.overlapping(Vector2.ZERO, 60.0, 1).has(2),
		"a nearby entity is found"
	)

	# The arena keeps the grid in step. Every entity calling place() itself is one
	# entity that forgets, which is invisible to everything and produces no error.
	a.position = Vector2(900.0, 900.0)
	arena.sync_grid()
	_check(
		not arena.overlapping(Vector2.ZERO, 60.0, 2).has(1),
		"syncing moves an entity's grid entry"
	)

	# An inactive entity leaves the grid, so a dead blob cannot be eaten again.
	b.active = false
	arena.sync_grid()
	_check(
		arena.overlapping(Vector2(50.0, 0.0), 60.0).is_empty(),
		"an inactive entity is out of the grid"
	)

	arena.forget(1)
	_check(arena.entity_count() == 1, "forgetting removes it")

	_check(
		arena.clamp_position(Vector2(5000.0, 0.0), 10.0).x <= 990.0,
		"a position outside the world is clamped"
	)

	# Spawn positions are deterministic, and inside the world.
	var spawn := arena.spawn_position(42)
	_check(arena.bounds.has_point(spawn), "a spawn is inside the world")
	_check(
		arena.spawn_position(42) == spawn,
		"and the same key spawns in the same place"
	)
	_check(
		arena.spawn_position(43) != spawn,
		"while a different key does not"
	)

	arena.queue_free()
	remove_child(arena)


func _test_interest() -> void:
	_group("interest")

	var arena := _make_arena()
	arena.interest_extent = Vector2(200.0, 200.0)
	arena.interest_scales_with_size = false

	var watcher := Dot2DState.at(Vector2.ZERO, 10.0)
	arena.register(1, watcher)

	for index in range(20):
		arena.register(
			100 + index,
			Dot2DState.at(Vector2(float(index) * 60.0, 0.0), 4.0)
		)

	arena.sync_grid()

	var seen := arena.interest_set(1)
	_check(seen.size() > 0, "a player sees something")
	_check(
		seen.size() < 20,
		"and not everything in the world",
		"%d of 20" % seen.size()
	)
	_check(not seen.has(1), "and not itself")

	# The one a mass-based game cannot do without: a blob wide enough to fill the
	# screen must be able to see what it might eat.
	arena.interest_scales_with_size = true
	watcher.radius = 320.0
	arena.sync_grid()
	var wider := arena.interest_set(1)
	_check(
		wider.size() > seen.size(),
		"a bigger entity sees further",
		"%d vs %d" % [wider.size(), seen.size()]
	)

	arena.queue_free()
	remove_child(arena)


# --- Controller ------------------------------------------------------------

func _test_controller() -> void:
	_group("controller")

	var arena := _make_arena()

	var controller := Dot2DController.new()
	controller.drive = Dot2DController.Drive.COMMANDED
	controller.tick_rate = TICK_RATE
	controller.tunables = Dot2DTunables.blob()
	controller.entity_id = 7
	add_child(controller)
	controller.attach(arena, 7)
	controller.setup()
	controller.attach(arena, 7)

	controller.state.mass = 50.0
	controller.set_mass(50.0)

	# A backlog is capped at max_catchup_ticks and the rest dropped: a frame that
	# simulated a second of movement is a player teleporting.
	var catching := Dot2DController.new()
	catching.drive = Dot2DController.Drive.LOCAL
	catching.tick_rate = TICK_RATE
	catching.tunables = Dot2DTunables.blob()
	catching.entity_id = 8
	add_child(catching)
	catching.attach(arena, 8)
	catching.setup()
	catching.max_catchup_ticks = 3
	catching._accumulator = 10.0 / float(TICK_RATE)
	var ticks_before := catching._tick
	catching._physics_process(0.0)
	_check(catching._tick - ticks_before == 3, "a backlog is capped at max_catchup_ticks", str(catching._tick - ticks_before))
	_check(catching._accumulator == 0.0, "and the rest is dropped rather than replayed later")
	var doc := Dot2DConfig.new()
	doc.tick_rate = 30
	doc.max_catchup_ticks = 5
	doc.apply_to_controller(catching)
	_check(catching.tick_rate == 30 and catching.max_catchup_ticks == 5, "Dot2DConfig reaches the controller")
	var field := Dot2DScatter.new()
	doc.scatter_count = 123
	doc.scatter_refill_per_tick = 4
	doc.apply_to_scatter(field)
	_check(field.target_count == 123 and field.refill_budget == 4, "and the scatter field")
	catching.queue_free()

	_close(
		controller.state.radius,
		controller.tunables.mass_rules.radius_for(50.0),
		"set_mass recomputes the radius with it"
	)

	var moves: Array[int] = []
	controller.simulated.connect(
		func(_t: int, _s: Dot2DState) -> void: moves.append(1)
	)

	controller.apply_command(_aim_command(Vector2.RIGHT, 500.0))
	controller.simulate_tick(1, STEP)
	_check(moves.size() == 1, "a commanded tick simulates once")
	_check(controller.state.position.x > 0.0, "and moves the entity")
	_check(
		controller.global_position == controller.state.position,
		"the node follows the state, not the other way round"
	)

	# A dropped input packet must read as "still holding", not as "let go" — a blob
	# that stops every time a packet is late is unplayable at any latency.
	var before := controller.state.velocity
	controller.simulate_tick(2, STEP)
	_check(
		controller.state.velocity.is_equal_approx(before),
		"a missing command repeats the last one rather than stopping",
		"%s vs %s" % [controller.state.velocity, before]
	)

	# The arena's grid follows the controller without anyone syncing.
	_check(
		arena.grid.position_of(7).is_equal_approx(controller.state.position),
		"the grid entry follows the simulation"
	)

	controller.teleport(Vector2(-500.0, 200.0))
	_check(controller.state.position == Vector2(-500.0, 200.0), "teleporting moves it")
	_check(controller.state.velocity == Vector2.ZERO, "and stops it")
	_check(
		arena.grid.position_of(7) == Vector2(-500.0, 200.0),
		"and updates the grid"
	)

	# A remote controller is never simulated.
	controller.drive = Dot2DController.Drive.REMOTE
	var remote_state := Dot2DState.at(Vector2(123.0, 456.0), 8.0)
	controller.apply_state(remote_state)
	_check(
		controller.state.position == Vector2(123.0, 456.0),
		"a remote controller takes its state from the network"
	)
	var count := moves.size()
	controller.simulate_tick(3, STEP)
	_check(moves.size() == count, "and does not simulate")

	# Speed limits fall with mass, which is what a HUD shows.
	controller.drive = Dot2DController.Drive.COMMANDED
	controller.set_mass(10.0)
	var light := controller.current_speed_limit()
	controller.set_mass(5000.0)
	_check(
		controller.current_speed_limit() < light,
		"a heavier entity has a lower speed limit"
	)

	controller.queue_free()
	remove_child(controller)
	arena.queue_free()
	remove_child(arena)


# --- Net sync --------------------------------------------------------------

## A stand-in for the DotNetBehaviour a game writes. Plain properties, because that is
## all [Dot2DNetSync] requires.
class FakeBehaviour extends Object:
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
	_group("net sync")

	var specs := Dot2DNetSync.specs()
	_check(specs.size() == 4, "the bridge describes what replicates")

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
	var rules := Dot2DMassRules.agar()
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
