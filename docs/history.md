# History

Bugs worth recognising if they come back. The lessons that still apply are rules in [CLAUDE.md](../CLAUDE.md) and [design.md](design.md). Both scatter bugs are also in the family catalogue, [game-dev/docs/bugs-found.md](../../../docs/bugs-found.md).

## The hash returned half its range

`Dot2DScatter._unit` once shifted by 40. The mixer output is masked to 63 bits, so that left 23 and every value fell in `[0, 0.5)`: every pellet in one corner of the world, which the self-test caught because it bins slots into quadrants. **The same line existed in dot-combat's `DotSpread`**, where the symptom was invisible: the spread azimuth covered half a circle and every spread pattern was a half-moon that merely "felt off". Both are fixed and both have a quadrant check, because a maximum-magnitude check alone passes for a half-moon.

## A grid holding twice the pellets

Because `reseed()` keeps the index counter, a new field's grid ids sit beside the old field's. A game that did not remove the old field from its grid first ended a round holding twice as many pellets as existed, half of them phantoms at stale positions that `take()` then refused, and eating quietly stopped working. The game's reset now removes the old ids first ([design](design.md#an-index-is-an-identity-and-is-never-reused)).

## A config nothing read

`Dot2DConfig` was documented field by field and applied by nothing: this family's most repeated bug, here a whole resource of it. `max_catchup_ticks` was the one that mattered: the controller capped a frame's backlog at a literal 8 while the config declared the number beside it. `apply_to_controller` and `apply_to_scatter` were added, and the controller exports `max_catchup_ticks`.
