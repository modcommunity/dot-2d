class_name Dot2DAdminModifiers
extends RefCounted

## What an administrator can do to how somebody moves in 2D: noclip, freeze and a speed
## step — carried in [member Dot2DState.admin], so every one of them is predicted.
##
## [codeblock]
## Dot2DAdminModifiers.set_noclip(piece.state, true)     # server side
## Dot2DAdminModifiers.set_speed(piece.state, 2.0)       # -> DotResult(2.0)
## [/codeblock]
##
## [b]Why a field in the state, and not a flag on the server.[/b] Everything here is
## decided on the server and has to be simulated on the owning client too, because the
## client predicts its own movement. A server that zeroed a player's velocity, or skipped
## their collision, would be simulating a player the client is not: the client's replay
## runs the ordinary motor, disagrees on every tick, and is corrected on every snapshot —
## rubber-banding, the one symptom an admin tool must not have. [member Dot2DState.admin] is
## copied by a rewind, compared by [method Dot2DState.matches] and replicated by
## [Dot2DNetSync] as `net_admin`, so the client's replay reads the same bits the server's
## simulation did and the two cannot disagree about them. dot-player-controller reached the
## same answer through its replicated modifier set; this motor has no modifier set, and one
## small bitfield is the whole of what the three abilities need.
##
## [b]Not [member Dot2DState.flags].[/b] Those are a game's, every bit of them — the game
## that shipped first already uses eight — and reserving some for this addon would be a
## collision waiting for the game that uses sixteen.
##
## [b]The speed is a ladder, not a dial,[/b] for dot-player-controller's reason: only an
## index travels, so a multiplier the server made up at runtime is one the client could not
## reproduce exactly. [method set_speed] picks the nearest step and says which.
##
## [b]Noclip keeps the arena.[/b] It passes through everything solid inside the world —
## [Dot2DBodyFlat]'s obstacles, and whatever geometry a game resolves itself, which it
## skips by asking [method is_noclipped] — but not through [member Dot2DBodyFlat.bounds].
## Outside the rectangle there is nothing to see, nothing a game renders, and past
## [constant Dot2DNetSync.WORLD_EXTENT] a position wraps to the other side of the world.
##
## There is no gravity step: nothing in dot-2d has gravity.

# No log channel: static helpers over a value, which return DotResult and let the caller
# decide what to say.

const NOCLIP := 1 << 0
const FREEZE := 1 << 1

## Where the speed step's index sits in [member Dot2DState.admin]: 0 is none, n is
## `SPEED_STEPS[n - 1]`.
const SPEED_SHIFT := 2
const SPEED_MASK := 0b111 << SPEED_SHIFT

## Every bit this addon may set. [constant Dot2DNetSync.ADMIN_BITS] must cover it.
const ALL := NOCLIP | FREEZE | SPEED_MASK

## Speed multipliers an admin can put somebody on. 1.0 is "none" and is not a step.
##
## The same ladder as the first-person motor's, so "speed 2" means the same thing in every
## game an admin moderates. Seven values fit the three bits above; six are used.
const SPEED_STEPS := [0.25, 0.5, 0.75, 1.5, 2.0, 3.0]


# --- On bits -------------------------------------------------------------------
#
# A game whose players are several states at once — a monster made of pieces — keeps one
# value per player and writes it into each state, so these work on the integer too.

static func noclip_bits(bits: int, on: bool) -> int:
	return (bits | NOCLIP) if on else (bits & ~NOCLIP)


static func frozen_bits(bits: int, on: bool) -> int:
	return (bits | FREEZE) if on else (bits & ~FREEZE)


## [param bits] with the speed step nearest [param scale]; 1.0 clears it.
static func speed_bits(bits: int, scale: float) -> int:
	var chosen := nearest(SPEED_STEPS, scale)
	var index := SPEED_STEPS.find(chosen) + 1 if not is_equal_approx(chosen, 1.0) else 0
	return (bits & ~SPEED_MASK) | ((index << SPEED_SHIFT) & SPEED_MASK)


static func bits_noclip(bits: int) -> bool:
	return (bits & NOCLIP) != 0


static func bits_frozen(bits: int) -> bool:
	return (bits & FREEZE) != 0


## The multiplier [param bits] carry, 1.0 when none. An index past the ladder — a newer
## build's step read by an older one — is 1.0 rather than an out-of-range read.
static func bits_speed(bits: int) -> float:
	var index := (bits & SPEED_MASK) >> SPEED_SHIFT

	if index <= 0 or index > SPEED_STEPS.size():
		return 1.0

	return float(SPEED_STEPS[index - 1])


## Short words for a describe: `noclip`, `frozen`, `speed 2`.
static func words(bits: int) -> PackedStringArray:
	var out := PackedStringArray()

	if bits_noclip(bits):
		out.append("noclip")

	if bits_frozen(bits):
		out.append("frozen")

	var speed := bits_speed(bits)

	if not is_equal_approx(speed, 1.0):
		# "speed 2", not "speed 2.0": the admin typed a number and reads one back.
		out.append("speed %s" % (
			str(int(speed)) if is_equal_approx(speed, roundf(speed)) else str(speed)
		))

	return out


## The step in [param steps] closest to [param scale], or 1.0 when 1.0 is closer.
static func nearest(steps: Array, scale: float) -> float:
	var best := 1.0
	var best_distance := absf(scale - 1.0)

	for step in steps:
		var distance := absf(scale - float(step))
		if distance < best_distance:
			best = float(step)
			best_distance = distance

	return best


# --- On a state ------------------------------------------------------------------

static func set_noclip(state: Dot2DState, on: bool) -> DotResult:
	if state == null:
		return _no_state()

	state.admin = noclip_bits(state.admin, on)
	return DotResult.success(on)


## Holds a state still, or lets it go.
##
## The velocity is zeroed here as well as by the motor, so the snapshot that tells the
## client carries a stopped entity rather than one the client has to stop itself.
static func set_frozen(state: Dot2DState, on: bool) -> DotResult:
	if state == null:
		return _no_state()

	adopt(state, frozen_bits(state.admin, on))
	return DotResult.success(on)


## Puts a state on the speed step nearest [param scale]. 1.0 clears it.
##
## Returns the multiplier actually applied, which is the one to tell the admin.
static func set_speed(state: Dot2DState, scale: float) -> DotResult:
	if state == null:
		return _no_state()

	if scale <= 0.0:
		return DotResult.fail(
			DotError.CODE_INVALID,
			"A multiplier has to be above zero.",
			"use freeze to hold somebody still"
		)

	state.admin = speed_bits(state.admin, scale)
	return DotResult.success(bits_speed(state.admin))


## Writes a whole set at once — what a game that keeps one value per player does to each
## of its states.
static func adopt(state: Dot2DState, bits: int) -> void:
	if state == null:
		return

	state.admin = bits & ALL

	if bits_frozen(state.admin):
		state.velocity = Vector2.ZERO


static func is_noclipped(state: Dot2DState) -> bool:
	return state != null and bits_noclip(state.admin)


static func is_frozen(state: Dot2DState) -> bool:
	return state != null and bits_frozen(state.admin)


static func speed_of(state: Dot2DState) -> float:
	return bits_speed(state.admin) if state != null else 1.0


## Takes every admin modifier off.
static func clear(state: Dot2DState) -> void:
	if state != null:
		state.admin = 0


static func _no_state() -> DotResult:
	return DotResult.fail(DotError.CODE_STATE, "That player has no movement to change.")
