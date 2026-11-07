extends "res://examples/dot_2d_selftest_net.gd"

## Exercises everything in dot-2d, offline and headless.
##
## [codeblock]
## godot --headless --path . res://examples/dot_2d_selftest.tscn
## [/codeblock]
##
## Exits non-zero on any failure, so it works as a smoke test as-is.
##
## The cases that matter most are the ones a cell-eating game reaches within a
## minute: a blob that walks out of the world, a spatial hash that misses an overlap it
## should have found, a scatter field that lays out differently on two machines, and a
## client whose predicted move disagrees with the server's.

const CHECKS := 175

## Sections entered against sections that ran to their last line, and against this. A
## runtime error inside a section aborts that function and nothing says so; a section that
## bailed out early after a failed guard is counted as not finished on purpose. The CHECKS
## total is the other half — see docs/testing.md.
const SECTIONS := 18


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
	_test_admin()

	print("")
	print("%d passed, %d failed" % [_passed, _failed])

	for line in _failures:
		print("  FAIL  %s" % line)

	print("%d of %d sections ran to their last line" % [_completed, _entered])
	if _entered != SECTIONS or _completed != _entered:
		print("ERROR: %d sections entered and %d completed, %d expected. One aborted or was skipped." % [
			_entered, _completed, SECTIONS
		])
		get_tree().quit(1)
		return
	# The total the section counter cannot be. A runtime error inside a section aborts
	# that function, and the counter is satisfied because the section had already
	# announced itself. See docs/testing.md.
	if _passed + _failed != CHECKS:
		print("ERROR: %d checks ran, %d expected. A section aborted part-way." % [
			_passed + _failed, CHECKS
		])
		get_tree().quit(1)
		return
	get_tree().quit(1 if _failed > 0 else 0)


func _test_admin() -> void:
	_section("admin modifiers")

	var tunables := Dot2DTunables.topdown()
	tunables.max_speed = 300.0
	tunables.acceleration = 3000.0
	tunables.friction = 3000.0

	var body := Dot2DBodyFlat.centred(Vector2(1000.0, 1000.0))
	body.add_obstacle(Vector2(100.0, 0.0), 50.0)

	var motor := Dot2DMotor.with_tunables(tunables)
	motor.body = body

	# Noclip: straight through the pillar, and still inside the world.
	var walker := Dot2DState.at(Vector2.ZERO, 10.0)
	_run_ticks(motor, walker, _move_command(Vector2.RIGHT), 60)
	_check(walker.position.x < 45.0, "without noclip the pillar stops a walker", str(walker.position))

	var ghost := Dot2DState.at(Vector2.ZERO, 10.0)
	var on := Dot2DAdminModifiers.set_noclip(ghost, true)
	_check(on.ok and Dot2DAdminModifiers.is_noclipped(ghost), "noclip is set on a state")
	_run_ticks(motor, ghost, _move_command(Vector2.RIGHT), 60)
	_check(ghost.position.x > 200.0, "and a noclipped walker goes through the pillar", str(ghost.position))
	_run_ticks(motor, ghost, _move_command(Vector2.RIGHT), 120)
	_close(ghost.position.x, 490.0, "but not out of the world: the bounds still hold")
	_check(
		is_equal_approx(body.move_through(Vector2.ZERO, Vector2(2000.0, 0.0), 10.0).x, 490.0),
		"move_through clamps to the bounds by itself"
	)
	var off := Dot2DAdminModifiers.set_noclip(ghost, false)
	_check(off.ok and not Dot2DAdminModifiers.is_noclipped(ghost), "and noclip comes off again")

	# Freeze: nothing moves, however hard the player pushes.
	var held := Dot2DState.at(Vector2(-200.0, 200.0), 10.0)
	held.velocity = Vector2(250.0, 0.0)
	var frozen := Dot2DAdminModifiers.set_frozen(held, true)
	_check(frozen.ok and held.velocity == Vector2.ZERO, "freezing stops the entity on the spot")
	_run_ticks(motor, held, _move_command(Vector2.UP), 60)
	_check(held.position == Vector2(-200.0, 200.0), "and a frozen entity does not move", str(held.position))
	_check(held.velocity == Vector2.ZERO, "or gather speed to spend later")

	var both := Dot2DState.at(Vector2(-200.0, -200.0), 10.0)
	var _n := Dot2DAdminModifiers.set_noclip(both, true)
	var _f := Dot2DAdminModifiers.set_frozen(both, true)
	_run_ticks(motor, both, _move_command(Vector2.RIGHT), 30)
	_check(both.position == Vector2(-200.0, -200.0), "freeze wins over noclip")

	var _thaw := Dot2DAdminModifiers.set_frozen(held, false)
	_run_ticks(motor, held, _move_command(Vector2.UP), 30)
	_check(held.position.y < 150.0, "and unfreezing gives the controls back", str(held.position))

	# Blob mode reads the same bit: velocity is set outright there, and a freeze that only
	# stopped the accelerating modes would be a freeze cell-eating games walk out of.
	var blob_tunables := Dot2DTunables.blob()
	var blob_motor := Dot2DMotor.with_tunables(blob_tunables)
	var blob := Dot2DState.at(Vector2.ZERO, 10.0)
	var _bf := Dot2DAdminModifiers.set_frozen(blob, true)
	_run_ticks(blob_motor, blob, _aim_command(Vector2.RIGHT), 30)
	_check(blob.position == Vector2.ZERO, "a frozen blob does not follow the pointer")

	_admin_speed(motor, blob_motor)
	_admin_replay(motor, ghost)
	_admin_wire(tunables)
	_done()


func _admin_speed(motor: Dot2DMotor, blob_motor: Dot2DMotor) -> void:
	# Speed: a ladder, and the admin is told which step they got.
	var fast := Dot2DState.at(Vector2(0.0, 300.0), 10.0)
	var got := Dot2DAdminModifiers.set_speed(fast, 2.2)
	_check(got.ok and is_equal_approx(float(got.value), 2.0), "speed 2.2 lands on the 2x step", str(got.value))
	# Twenty ticks, not sixty: at 600 a second a longer run reaches the wall, stops, and
	# measures the wall.
	_run_ticks(motor, fast, _move_command(Vector2.LEFT), 20)
	_close(fast.speed(), 600.0, "and doubles the top speed", 0.5)

	var normal := Dot2DState.at(Vector2(0.0, -300.0), 10.0)
	_run_ticks(motor, normal, _move_command(Vector2.LEFT), 3)
	var quick := Dot2DState.at(Vector2(0.0, -300.0), 10.0)
	var _q := Dot2DAdminModifiers.set_speed(quick, 2.0)
	_run_ticks(motor, quick, _move_command(Vector2.LEFT), 3)
	_close(quick.speed(), normal.speed() * 2.0, "and the acceleration with it, so 2x is not a slide", 0.5)

	var blob_fast := Dot2DState.at(Vector2.ZERO, 10.0)
	var blob_slow := Dot2DState.at(Vector2.ZERO, 10.0)
	var _bs := Dot2DAdminModifiers.set_speed(blob_fast, 0.5)
	_run_ticks(blob_motor, blob_fast, _aim_command(Vector2.RIGHT), 1)
	_run_ticks(blob_motor, blob_slow, _aim_command(Vector2.RIGHT), 1)
	_close(blob_fast.speed(), blob_slow.speed() * 0.5, "a blob on 0.5x moves at half speed", 0.5)

	var cleared := Dot2DAdminModifiers.set_speed(fast, 1.0)
	_check(
		cleared.ok and is_equal_approx(float(cleared.value), 1.0) and fast.admin == 0,
		"speed 1 clears the step and leaves no bits behind"
	)
	_check(not Dot2DAdminModifiers.set_speed(fast, 0.0).ok, "and speed 0 is refused rather than a second freeze")
	_check(not Dot2DAdminModifiers.set_noclip(null, true).ok, "a missing state is refused, not a crash")

	var every := Dot2DAdminModifiers.speed_bits(Dot2DAdminModifiers.NOCLIP, 3.0)
	_check(
		Dot2DAdminModifiers.bits_noclip(every) and is_equal_approx(Dot2DAdminModifiers.bits_speed(every), 3.0),
		"a speed step leaves noclip where it was"
	)
	_check(
		(Dot2DAdminModifiers.ALL & ~((1 << Dot2DNetSync.ADMIN_BITS) - 1)) == 0,
		"every admin bit fits in what the wire carries"
	)
	_check(
		is_equal_approx(Dot2DAdminModifiers.bits_speed(7 << Dot2DAdminModifiers.SPEED_SHIFT), 1.0),
		"a step index past the ladder reads as none rather than out of range"
	)
	_check(
		Dot2DAdminModifiers.words(every) == PackedStringArray(["noclip", "speed 3"]),
		"and the set describes itself in words",
		str(Dot2DAdminModifiers.words(every))
	)



func _admin_replay(motor: Dot2DMotor, ghost: Dot2DState) -> void:
	# The state carries it through everything a reconciliation does.
	var copy := Dot2DState.new()
	copy.copy_from(ghost)
	var _gn := Dot2DAdminModifiers.set_noclip(ghost, true)
	copy.copy_from(ghost)
	_check(copy.admin == ghost.admin and copy.admin != 0, "a rewind copies the admin bits")
	var stripped := ghost.duplicate_state()
	stripped.admin = 0
	_check(not stripped.matches(ghost), "and two states that disagree about them do not match")

	# The prediction property itself. The server runs 40 ticks with noclip through the
	# pillar; a client rewound to the server's state at tick 10 replays the rest and has to
	# land on the same spot. The same replay with the bits stripped — a server that
	# skipped the collision on its own side only — must NOT, or the first check could not
	# have failed.
	var server := Dot2DState.at(Vector2(-60.0, 0.0), 10.0)
	var _sn := Dot2DAdminModifiers.set_noclip(server, true)
	var history: Array[Dot2DState] = []
	for tick in range(40):
		history.append(server.duplicate_state())
		motor.simulate(server, _move_command(Vector2.RIGHT), STEP, tick)

	var client := history[10].duplicate_state()
	for tick in range(10, 40):
		motor.simulate(client, _move_command(Vector2.RIGHT), STEP, tick)
	_check(client.position == server.position, "a replay from a rewound copy lands exactly where the server did", "%s vs %s" % [client.position, server.position])

	var naive := history[10].duplicate_state()
	naive.admin = 0
	for tick in range(10, 40):
		motor.simulate(naive, _move_command(Vector2.RIGHT), STEP, tick)
	_check(
		naive.position.distance_to(server.position) > 20.0,
		"and without the bits the replay disagrees: that is the rubber band",
		"%.1f units apart" % naive.position.distance_to(server.position)
	)



func _admin_wire(tunables: Dot2DTunables) -> void:
	# On the wire.
	var sent := Dot2DState.at(Vector2(5.0, 5.0), 10.0)
	var _a := Dot2DAdminModifiers.set_frozen(sent, true)
	var _b := Dot2DAdminModifiers.set_speed(sent, 0.5)
	var behaviour := FakeBehaviour.new()
	Dot2DNetSync.pull(sent, behaviour)
	_check(behaviour.net_admin == sent.admin, "pull writes the admin bits")
	var arrived := Dot2DState.new()
	Dot2DNetSync.push(behaviour, arrived)
	_check(arrived.admin == sent.admin, "and push brings them back")

	var older := OlderBehaviour.new()
	older.net_position = Vector2(42.0, 7.0)
	var kept := Dot2DState.new()
	kept.admin = Dot2DAdminModifiers.NOCLIP
	Dot2DNetSync.push(older, kept)
	_check(
		kept.position == Vector2(42.0, 7.0) and kept.admin == Dot2DAdminModifiers.NOCLIP,
		"a behaviour with no net_admin still pushes, and leaves the bits alone"
	)
	_check(
		Dot2DNetSync.estimated_bits() <= 128,
		"and an entity still fits in sixteen bytes with them",
		"%d bits" % Dot2DNetSync.estimated_bits()
	)

	# The controller, which a HUD reads.
	var controller := Dot2DController.new()
	controller.tunables = tunables
	add_child(controller)
	var _cf := Dot2DAdminModifiers.set_frozen(controller.state, true)
	_check(is_zero_approx(controller.current_speed_limit()), "a frozen controller reports a top speed of zero")
	var _cu := Dot2DAdminModifiers.set_frozen(controller.state, false)
	var _cs := Dot2DAdminModifiers.set_speed(controller.state, 2.0)
	_close(controller.current_speed_limit(), 600.0, "and a fast one the stepped speed")
	controller.queue_free()

	behaviour.free()
	older.free()
