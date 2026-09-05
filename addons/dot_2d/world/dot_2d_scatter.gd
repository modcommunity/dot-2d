class_name Dot2DScatter
extends RefCounted

## Thousands of little things spread over a world, placed and replaced
## deterministically.
##
## The pellet field. Also crates, resource nodes, and anything else a game sprinkles.
##
## [b]Positions come from a hash, not from a random stream.[/b] A stream means a server
## restart, a late-joining client and a replay all get different worlds; a hash of
## (seed, index) means every one of them gets the same pellet in the same place, and a
## client can place the whole field itself from a seed rather than receiving two
## thousand positions.
##
## Respawning is budgeted per tick rather than done all at once, because a round that
## clears half the field would otherwise place a thousand entities inside a single
## frame — and on a server that is a visible stall.

const CHANNEL := "dot2d.scatter"

## Same masking discipline as [DotSpread] in dot-combat: GDScript integers are signed
## 64-bit and the published mixing constants are all above 2^63.
const _MASK := 0x7FFFFFFFFFFFFFFF

## Where things go.
var bounds: Rect2 = Rect2(Vector2.ZERO, Vector2(1000.0, 1000.0))

## How many there should be.
var target_count: int = 500

## Placements per tick when refilling. Zero places them all at once.
var refill_budget: int = 8

## The world seed. Two peers with the same seed lay out the same field.
var seed_value: int = 1

## Margin from the edge, so nothing spawns half inside a wall.
var margin: float = 8.0

## index -> true for slots that are currently filled.
var _alive: Dictionary = {}

## The next index to hand out. Never reused, so a respawned pellet is a new position
## rather than the one that was just eaten — which would put food back where a player
## is standing.
var _next_index: int = 0

var _placed: int = 0
var _taken: int = 0


static func over(rect: Rect2, count: int, world_seed: int = 1) -> Dot2DScatter:
	var scatter := Dot2DScatter.new()
	scatter.bounds = rect
	scatter.target_count = count
	scatter.seed_value = world_seed
	return scatter


## The position of slot [param index]. A pure function of the seed and the index.
func position_of(index: int) -> Vector2:
	var h := _hash(seed_value, index)
	var inner := Rect2(
		bounds.position + Vector2(margin, margin),
		Vector2(
			maxf(1.0, bounds.size.x - margin * 2.0),
			maxf(1.0, bounds.size.y - margin * 2.0)
		)
	)

	return Vector2(
		inner.position.x + _unit(h) * inner.size.x,
		inner.position.y + _unit(_hash(h, index + 1)) * inner.size.y,
	)


## A value in [0, 1) associated with a slot, for a game that wants variety.
##
## What a pellet's colour or a crate's contents come from. Deterministic, so two peers
## agree without it being sent.
func variant_of(index: int) -> float:
	return _unit(_hash(seed_value + 0x5EED, index))


func alive_count() -> int:
	return _alive.size()


func alive_indices() -> Array[int]:
	var out: Array[int] = []
	for key in _alive.keys():
		out.append(int(key))
	out.sort()
	return out


func is_alive(index: int) -> bool:
	return _alive.has(index)


## Marks a slot taken. Returns false if it was already gone.
##
## Returning false rather than silently succeeding is what lets a server tell a real
## pickup from a duplicate claim — two clients both reporting they ate the same pellet
## is normal at any latency, and one of them has to lose.
func take(index: int) -> bool:
	if not _alive.has(index):
		return false

	_alive.erase(index)
	_taken += 1
	return true


## Places up to [member refill_budget] new slots. Returns the indices placed.
##
## Called every tick. The budget is what stops a mass respawn from being one long
## frame; with a budget of 8 at 60 Hz a field refills at nearly 500 a second, which is
## faster than players can clear it.
func refill() -> Array[int]:
	var out: Array[int] = []
	var missing := target_count - _alive.size()

	if missing <= 0:
		return out

	var budget := missing if refill_budget <= 0 else mini(missing, refill_budget)

	for _step in range(budget):
		var index := _next_index
		_next_index += 1
		_alive[index] = true
		_placed += 1
		out.append(index)

	return out


## Marks one specific slot alive, without allocating a new index.
##
## [b]What a peer mirroring an authority's field does.[/b] [method refill] is the
## authority's path: it hands out the next index and returns it so the caller can tell
## everybody which slots appeared. A receiving peer already has the index and has to
## adopt exactly that one — allocating its own would give the same pellet two different
## names on two machines, and the eaten signal would then name a slot the other side has
## never heard of.
##
## The counter is advanced past an adopted index so that a peer which later becomes the
## authority — a listen server, a host migration — cannot reissue an index that is
## already in use.
func adopt(index: int) -> bool:
	if index < 0 or _alive.has(index):
		return false

	_alive[index] = true
	_placed += 1
	_next_index = maxi(_next_index, index + 1)
	return true


## Fills the field completely, ignoring the budget. What a round start does.
func fill() -> Array[int]:
	var out: Array[int] = []

	while _alive.size() < target_count:
		var index := _next_index
		_next_index += 1
		_alive[index] = true
		_placed += 1
		out.append(index)

	return out


func clear() -> void:
	_alive.clear()
	_taken = 0
	_placed = 0


## Empties the field and lays the next one out from a new seed. What a round does.
##
## [b]The index counter is deliberately not reset.[/b] An index is a slot's identity —
## it goes on the wire, it is what a signal carries, and it is how a client knows which
## pellet it just ate. Restarting the count means two different pellets with the same
## name a round apart, and the confusion shows up as a client eating something that is
## not there.
##
## Positions still change: [method position_of] hashes the seed with the index, so the
## same index under a new seed is somewhere new.
func reseed(new_seed: int) -> void:
	seed_value = new_seed
	clear()


## Registers every live slot into a [Dot2DGrid].
##
## [param id_base] is added to the slot index to make the grid id, so pellets and
## players can share one grid without colliding — a game usually gives players low ids
## and pellets a large base.
func populate(grid: Dot2DGrid, id_base: int, radius: float) -> void:
	for index in alive_indices():
		grid.place(id_base + index, position_of(index), radius)


static func _hash(a: int, b: int) -> int:
	var x := ((a + 0x1E3779B97F4A7C15) ^ (b * 0x3F58476D1CE4E5B9)) & _MASK
	x = (x ^ (x >> 30)) & _MASK
	x = (x * 0x3F58476D1CE4E5B9) & _MASK
	x = (x ^ (x >> 27)) & _MASK
	x = (x * 0x14D049BB133111EB) & _MASK
	x = (x ^ (x >> 31)) & _MASK
	return x


static func _unit(h: int) -> float:
	# h is masked to 63 bits, so shifting by 39 leaves exactly 24 -- the width a
	# 32-bit float represents exactly, and the whole range. Shifting by 40 leaves 23,
	# and every value then falls in [0, 0.5): a scatter field clustered into one
	# quadrant, and a spread cone that only ever covered half a circle.
	return float(h >> 39) / 16777216.0


func describe() -> Dictionary:
	return {
		"bounds": bounds,
		"target": target_count,
		"alive": _alive.size(),
		"placed": _placed,
		"taken": _taken,
		"seed": seed_value,
		"next_index": _next_index,
	}
