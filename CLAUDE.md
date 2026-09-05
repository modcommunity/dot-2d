# dot-2d

2D movement and world. Read `../../CLAUDE.md` first for the family-wide rules; this
file is only what is specific to the 2D layer.

## The one idea

**`Dot2DMotor.simulate()` is a pure function of its arguments.** No device, no clock,
no node, no randomness. A client predicting a move, a server re-running it and a
reconciliation replay all reach the same position from the same command.

The self-test replays 180 commands twice and asserts the positions are **exactly**
equal, not approximately — and then changes one command in the middle and asserts the
outcome differs, because otherwise the first check would pass for a motor that ignored
its inputs.

## The pointer is resolved in the sampler, not sent

`Dot2DCommand` carries `aim` (a unit direction) and `reach` (a world-unit distance),
never a screen position. A screen position depends on a window size and a camera zoom
the server does not have.

`reach` is also a speed multiplier in pointer mode, which makes it the thing a hostile
client inflates. `sanitise()` clamps it, normalises `aim`, limits `move` to unit length
and masks unknown buttons — a move vector of length 40 is not a crash, it is a player
who simply moves faster than everyone else, and it is the single most common cheat in a
game where movement is client-driven.

## Blobs do not accelerate

`_simulate_blob` sets the velocity outright rather than accelerating toward it, and
`Dot2DTunables.blob()` sets acceleration and friction to 100000 so nothing else in the
pipeline reintroduces a ramp.

In agar.io a cell is exactly as fast as its mass allows, immediately. Accelerating
toward that makes a small cell feel sluggish in precisely the situation it is supposed
to be nimble, and it makes a split feel like a slide.

## Mass is applied before the move, not after

`_apply_mass` runs first in `simulate()`. Speed depends on mass, so a tick that moved at
last tick's speed and then changed mass is a tick where the two disagree by one frame.
Invisible — until a client and a server disagree about which side of an eat threshold a
blob was on.

For the same reason `Dot2DController.set_mass()` exists and setting `state.mass`
directly is wrong: it leaves the radius describing the old mass until the next tick, and
anything that queries in between (an eat check, an interest rectangle) uses the stale
one.

## The hash returns its whole range

`Dot2DScatter._unit` shifts by **39, not 40**. The mixer output is masked to 63 bits, so
shifting by 40 leaves 23 and every value falls in `[0, 0.5)`.

This put every pellet in one corner of the world, which the self-test caught because it
bins 400 slots into quadrants. **The same line existed in dot-combat's `DotSpread`**,
where the symptom was invisible: the spread azimuth covered half a circle and every
shotgun pattern was a half-moon that merely "felt off". Both are fixed; both now have a
quadrant check, because a maximum-magnitude check alone passes for a half-moon.

The constants also have their top bit cleared — GDScript integers are signed 64-bit and
the published mixing constants are all above 2^63.

## A scatter index is an identity, and is never reused

`Dot2DScatter.reseed()` changes the seed and empties the field but **does not reset the
index counter**. An index goes on the wire, it is what `take()` and the eaten signal
carry, and it is how a client knows which pellet it just ate. Restarting the count
means two different pellets with the same name a round apart.

The consequence for a caller is that a new field's grid ids sit *beside* the old
field's rather than overwriting them, so **whatever indexed the old field into a grid
must remove it first**. `game-blob`'s `_reset_world` does; before it did, the grid
ended a round holding twice as many pellets as existed, half of them phantoms at stale
positions that `take()` then refused — and eating quietly stopped working.

## A mirroring peer adopts an index; it never allocates one

`refill()` is the authority's path: it hands out the next index and returns it so the
caller can tell everybody which slots appeared. `adopt(index)` is the other side of that,
and it exists because a receiving peer already *has* the index and has to mark exactly
that slot alive. Allocating its own would give the same pellet two different names on two
machines, and the eaten signal would then name a slot the other side has never heard of.

It advances `_next_index` past whatever it adopted, so a peer that later becomes the
authority — a listen server, a host migration — cannot reissue an index already in use.

`dot-2d-hungry` is what needed it: its client mirrors four fields off the wire.

## `Dot2DBodyFlat` is production, not a stub

An agar.io world is a rectangle with nothing in it. Analytic bounds and circles are
cheaper than the physics server *and* give bit-identical answers on two machines, which
a physics query does not: it is a floating-point result from a solver whose internal
state depends on what ran before it, and the space state is a step stale after anything
moves.

`Dot2DBodyPhysics` is documented as unsuitable for a predicted entity, in its own class
docs, because someone will otherwise reach for it by default.

Three degenerate cases it handles that are each a permanently stuck entity:

- **A move landing exactly on an obstacle centre** has no direction to be pushed along,
  and normalising a zero vector gives zero.
- **An entity wider than the arena** clamps to a negative range; it is centred instead,
  and a blob that has eaten the whole map reaches it.
- **A wall that stopped an entity dead** makes moving along it impossible, so the edges
  become traps. `reflect()` slides by default.

## `Dot2DGrid` is why a crowded world is possible

Two thousand pellets and forty players is 80,000 pair tests a tick done naively. It is
also what interest management is built on: "everything within a screen of this player"
is a rectangle query, and sending a client only that is the difference between a
playable browser game and one that saturates a connection.

Three details that are not obvious:

- **`place()` is both add and move.** A caller that has to know which gets it wrong for
  the entity removed and re-added on the same tick, and the symptom is an entity in two
  cells at once.
- **Empty cells are erased.** Otherwise a world an entity has crossed once holds a cell
  for every square it has ever been in.
- **`query_overlapping` is not `query_circle`.** The first tests circle-against-circle
  and widens its search by the largest radius in the grid; the second tests centres. A
  blob big enough to contain another blob's centre and one merely touching it are
  different questions, and eating needs the first. `_largest_radius` only ever rises on
  `place()` — lowering it per removal would be a walk of every entity — so
  `recompute_bounds()` exists and is optional. A slightly wide query is correct; a
  narrow one misses an overlap.

## Interest scales with size

`Dot2DArena.interest_scales_with_size` is on by default and is not a nicety: a blob wide
enough to fill the screen cannot see anything it might eat without it. It scales
linearly in **radius**, not mass, because radius is what fills the screen.

## Replication is 2D, deliberately

`Dot2DNetSync` declares position and velocity as `CUSTOM` with its own codecs rather
than using dot-net's quantised vector types, which are three-component. A 2D game paying
for a Z that is always zero wastes 40% of its position bandwidth, and on a world with a
hundred visible entities that is the difference between fitting in a packet and not.

**The radius is derived on receipt, not replicated.** Sending both lets them disagree by
a rounding error and puts an entity's eat radius and its drawn radius in different
places.

`WORLD_EXTENT` must cover the arena and both peers must agree. Too small and distant
entities wrap to the wrong place.

## `Dot2DConfig` is an offer, not a requirement

The nodes carry their own exports and work without it. `Dot2DConfig` is the layered
document for a project that wants one place for the simulation and world numbers, and
`apply_to_controller` / `apply_to_scatter` are how it reaches them.

Those two methods are new because **nothing read this resource at all** — every field
was documented and applied by nothing, which is this family's most repeated bug and
here was a whole resource of it. `max_catchup_ticks` is the one that mattered: the
controller capped a frame's backlog at a literal 8 while the config declared the
number beside it.

Both games in the family predate it and set the node fields from their own config, and
that stays correct. A new project should prefer the document.

## Coupling: nothing is imported

dot-2d names no class outside dot-core.

- `Dot2DCommand.write` / `read` and every codec in `Dot2DNetSync` take `Variant`, so
  this project parses without dot-net installed.
- `Dot2DNetSync` describes what to replicate as data — property names and *type names
  as strings*.
- `Dot2DCameraRig` duck-types its target's radius, so it can follow anything and simply
  not zoom.

## Validating changes

```bash
cd godot/dot-2d
ln -s ../../dot-core/addons/dot_core addons/dot_core   # gitignored
godot --headless --path . --import
find . -name '*.gd' -not -path './.godot/*' | while read f; do
    godot --headless --path . --check-only --script "res://${f#./}"
done
godot --headless --path . res://examples/dot_2d_selftest.tscn
```

138 checks, all offline. Exits non-zero on any failure.

**Run it after any change to the motor, the grid or the scatter.** The determinism
check is the one that matters: it is the property every other guarantee in this addon
depends on, and it is not visible by reading the code.

## Things deliberately not here

- **Splitting and merging.** `Dot2DMassRules` holds the numbers — `max_pieces`,
  `min_split_mass`, `split_impulse`, `merge_delay_sec` — and nothing reads them. Split
  pieces are *several entities owned by one player*, which needs an ownership model,
  a merge rule and a camera that frames a set rather than a point. That is a game's
  design, and `game-blob` is where it belongs.
- **Ejecting mass, viruses, teams.** Same reasoning. The primitives are here.
- **Rotation for anything but facing.** `Dot2DState.facing` is a single angle. A game
  with independent body and turret rotation carries the second itself.
- **Tile maps and navigation.** `Dot2DBodyFlat` takes circles and a rectangle. A game
  with real level geometry uses `Dot2DBodyPhysics` and gives up prediction, or
  subclasses `Dot2DBody` against its own representation — which is the seam.
- **Interpolation on the client.** dot-net already owns snapshot interpolation, and a
  second one here would fight it.
- **Sprites, animation, particles.** dot-2d ships no art and draws nothing.
