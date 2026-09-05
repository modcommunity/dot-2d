class_name Dot2DGrid
extends RefCounted

## A uniform spatial hash. What makes a world with thousands of entities possible.
##
## [b]The single thing an agar.io-like game cannot do without.[/b] Two thousand pellets
## and forty players is 80,000 pair tests per tick done naively, per tick, on the
## server. Bucketed by cell it is a few dozen — and, more importantly, it is a few
## dozen regardless of how big the world gets.
##
## Also what interest management is built on: "everything within a screen of this
## player" is a rectangle query, and sending a client only that is the difference
## between a playable browser game and one that saturates a connection.
##
## Ids are integers a game assigns. The grid never holds an object, so an entity that
## is freed without being removed is a stale id rather than a dangling reference.

## Cell size in world units. Set it to roughly the largest query radius: too small and
## a query walks many cells, too large and each cell holds everything.
var cell_size: float = 128.0

## cell key -> Array[int] of ids.
var _cells: Dictionary = {}

## id -> cell key, so a move knows which cell to leave.
var _homes: Dictionary = {}

## id -> Vector2 position, so a query can reject without the caller supplying them.
var _positions: Dictionary = {}

## id -> radius, for queries that need to account for entity size.
var _radii: Dictionary = {}

## The largest radius currently placed, maintained by [method place].
##
## [method place] only ever raises it — lowering it on every removal would be a walk of
## every entity per removal — so a world whose biggest entity has left keeps querying a
## slightly wider rectangle until [method recompute_bounds] is called. That is a small
## cost and a correct answer; the other way round is a missed overlap.
var _largest_radius: float = 0.0


func _init(p_cell_size: float = 128.0) -> void:
	cell_size = maxf(1.0, p_cell_size)


## Adds or moves an entity.
##
## One method rather than an add and a move: a caller that has to know which it is gets
## it wrong for the entity that was removed and re-added on the same tick, and the
## symptom is an entity in two cells at once.
func place(id: int, position: Vector2, radius: float = 0.0) -> void:
	var key := _key_of(position)
	var previous: Variant = _homes.get(id)

	if previous != null and int(previous) == key:
		_positions[id] = position
		_radii[id] = radius
		_largest_radius = maxf(_largest_radius, radius)
		return

	if previous != null:
		_remove_from_cell(int(previous), id)

	var bucket: Array = _cells.get(key, [])
	bucket.append(id)
	_cells[key] = bucket

	_homes[id] = key
	_positions[id] = position
	_radii[id] = radius
	_largest_radius = maxf(_largest_radius, radius)


func remove(id: int) -> void:
	var home: Variant = _homes.get(id)

	if home != null:
		_remove_from_cell(int(home), id)

	_homes.erase(id)
	_positions.erase(id)
	_radii.erase(id)


func has(id: int) -> bool:
	return _homes.has(id)


func position_of(id: int) -> Vector2:
	return _positions.get(id, Vector2.ZERO)


func radius_of(id: int) -> float:
	return float(_radii.get(id, 0.0))


func size() -> int:
	return _homes.size()


func cell_count() -> int:
	return _cells.size()


func clear() -> void:
	_cells.clear()
	_homes.clear()
	_positions.clear()
	_radii.clear()
	_largest_radius = 0.0


func _remove_from_cell(key: int, id: int) -> void:
	var bucket: Array = _cells.get(key, [])
	var index := bucket.find(id)

	if index >= 0:
		# swap-and-pop: order within a cell is not meaningful, and erase() on a large
		# bucket is a memmove per removal in a loop that runs per entity per tick.
		bucket[index] = bucket[bucket.size() - 1]
		bucket.resize(bucket.size() - 1)

	if bucket.is_empty():
		# Empty cells are dropped, or a world an entity has crossed once holds a cell
		# for every square it has ever been in.
		_cells.erase(key)
	else:
		_cells[key] = bucket


## Packs a cell coordinate into one integer key.
##
## Two 32-bit halves of a 64-bit int rather than a `Vector2i` key: an integer key hashes
## and compares in one operation, and this is the hottest line in the whole addon.
func _key_of(position: Vector2) -> int:
	var cx := int(floor(position.x / cell_size))
	var cy := int(floor(position.y / cell_size))
	return ((cx & 0xFFFFFFFF) << 32) | (cy & 0xFFFFFFFF)


static func _key_from_cell(cx: int, cy: int) -> int:
	return ((cx & 0xFFFFFFFF) << 32) | (cy & 0xFFFFFFFF)


## Ids whose position is within [param radius] of [param centre].
##
## Exact, not merely bucketed: the cells are a filter and the distance is then checked,
## so a caller does not have to. [param exclude] is skipped, which is almost always the
## querying entity itself.
func query_circle(
	centre: Vector2,
	radius: float,
	exclude: int = 0
) -> Array[int]:
	var out: Array[int] = []
	var limit := radius * radius

	for id in query_rect(Rect2(centre - Vector2(radius, radius), Vector2(radius, radius) * 2.0), exclude):
		if position_of(id).distance_squared_to(centre) <= limit:
			out.append(id)

	return out


## Ids whose position is inside [param rect].
##
## The rectangle version is what interest management wants: a client sees a screen, and
## a screen is a rectangle.
func query_rect(rect: Rect2, exclude: int = 0) -> Array[int]:
	var out: Array[int] = []

	var min_x := int(floor(rect.position.x / cell_size))
	var max_x := int(floor(rect.end.x / cell_size))
	var min_y := int(floor(rect.position.y / cell_size))
	var max_y := int(floor(rect.end.y / cell_size))

	for cx in range(min_x, max_x + 1):
		for cy in range(min_y, max_y + 1):
			var bucket: Array = _cells.get(_key_from_cell(cx, cy), [])

			for entry in bucket:
				var id := int(entry)

				if id == exclude:
					continue

				if rect.has_point(position_of(id)):
					out.append(id)

	return out


## Ids whose *circle* overlaps a circle at [param centre].
##
## Distinct from [method query_circle], which tests centres. A blob big enough to
## contain another blob's centre and a blob merely touching it are different questions,
## and eating needs the first while collision needs the second.
##
## The search radius is widened by the largest radius in the grid, because a large
## entity's centre can be outside the query and its edge inside it.
func query_overlapping(
	centre: Vector2,
	radius: float,
	exclude: int = 0
) -> Array[int]:
	var out: Array[int] = []
	var reach := radius + _largest_radius

	for id in query_rect(Rect2(centre - Vector2(reach, reach), Vector2(reach, reach) * 2.0), exclude):
		var other := position_of(id)
		if other.distance_to(centre) <= radius + radius_of(id):
			out.append(id)

	return out


## Recomputes the largest radius. See [member _largest_radius].
func recompute_bounds() -> void:
	_largest_radius = 0.0
	for id in _radii.keys():
		_largest_radius = maxf(_largest_radius, float(_radii[id]))


func ids() -> Array[int]:
	var out: Array[int] = []
	for key in _homes.keys():
		out.append(int(key))
	out.sort()
	return out


func describe() -> Dictionary:
	var largest := 0
	for key in _cells.keys():
		largest = maxi(largest, (_cells[key] as Array).size())

	return {
		"entities": _homes.size(),
		"cells": _cells.size(),
		"cell_size": cell_size,
		"largest_cell": largest,
		"largest_radius": _largest_radius,
	}
