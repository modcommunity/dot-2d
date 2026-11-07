extends "res://examples/dot_2d_selftest_mid.gd"

## Self-test layer: grid, scatter, arena, interest and the controller.


func _test_grid() -> void:
	_section("grid")

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
	_done()


func _test_grid_overlap() -> void:
	_section("grid: overlap")

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
	_done()


func _test_scatter() -> void:
	_section("scatter")

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

	_scatter_taking(scatter)
	_done()


func _scatter_taking(scatter: Dot2DScatter) -> void:
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
	_section("arena")

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
	_done()


func _test_interest() -> void:
	_section("interest")

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
	_done()


# --- Controller ------------------------------------------------------------

func _test_controller() -> void:
	_section("controller")

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

	_controller_ticks(controller, arena)
	controller.queue_free()
	remove_child(controller)
	arena.queue_free()
	remove_child(arena)
	_done()


func _controller_ticks(controller: Dot2DController, arena: Dot2DArena) -> void:
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
