# dot-2d

2D movement and world for a predicted, server-authoritative game: a pure motor, sanitised commands, an analytic arena body, a spatial grid for eating and interest, a deterministic pellet scatter, 2D replication descriptors and an administrator's noclip, freeze and speed.

Read the family [CLAUDE.md](../../CLAUDE.md) first; this file is only what is specific to the 2D layer. Classes are `Dot2D*`, because `class_name` is global.

**The distributable is `addons/dot_2d/`.** It requires dot-core (symlinked, `.gitignore`) and names no class outside it. game-hungario is the one game on it.

## Read before

| Read | Before |
| --- | --- |
| [docs/design.md](docs/design.md) | anything: the pure motor, sanitising, mass order, the scatter's indices, the flat body, the grid, replication, admin modifiers, the config, what is not here |
| [docs/history.md](docs/history.md) | the half-range hash, the doubled grid, the config nothing read |

## Layout

| Path | What |
| --- | --- |
| `core/` | `Dot2DCommand` (aim, reach, move, buttons; `sanitise()`), `Dot2DState`, `Dot2DTunables` (`blob()`), `Dot2DMassRules`, `Dot2DAdminModifiers` |
| `motion/` | `Dot2DMotor` (`simulate()`, pure), `Dot2DBody` (the seam), `Dot2DBodyFlat` (analytic circles and a rectangle), `Dot2DBodyPhysics` (unpredicted entities only) |
| `world/` | `Dot2DGrid`, `Dot2DScatter`, `Dot2DArena` |
| `net/dot_2d_net_sync.gd` | `Dot2DNetSync`: what to replicate, as data; 2D codecs, `WORLD_EXTENT`, `ADMIN_BITS` |
| `nodes/` | `Dot2DController`, `Dot2DSampler` (resolves the pointer), `Dot2DCameraRig` |
| `dot_2d_config.gd` | `Dot2DConfig`: the optional layered document; `apply_to_controller`, `apply_to_scatter` |
| `examples/dot_2d_selftest.tscn` | the suite; all offline, non-zero on failure |

Paths above, except `examples/`, are in `addons/dot_2d/`.

## Running and testing

The family's two steps ([game-dev/CLAUDE.md](../../CLAUDE.md#validating-anything)), then `godot --headless --path . res://examples/dot_2d_selftest.tscn`. Run it after any change to the motor, the grid or the scatter: the determinism check is the property every other guarantee here depends on, and it is not visible by reading the code.

## Rules that bite

- `Dot2DMotor.simulate()` stays a pure function: no device, clock, node or randomness. [design](docs/design.md#the-motor-is-a-pure-function)
- Commands carry `aim` + `reach`, never a screen position; the server runs `sanitise()` on every one. [design](docs/design.md#the-pointer-is-resolved-in-the-sampler-not-sent)
- `_apply_mass` runs before the move; change mass through `Dot2DController.set_mass()`, never `state.mass`. [design](docs/design.md#mass-is-applied-before-the-move-not-after)
- `Dot2DScatter._unit` shifts by 39; a hash check needs quadrants, not just magnitude. [design](docs/design.md#the-hash-returns-its-whole-range)
- `reseed()` never resets the index counter; remove the old field from any grid first. A mirroring peer calls `adopt(index)`, never `refill()`. [design](docs/design.md#the-scatter)
- A predicted entity uses `Dot2DBodyFlat`, never `Dot2DBodyPhysics`. [design](docs/design.md#dot2dbodyflat-is-production-not-a-stub)
- `Dot2DGrid.place()` is add and move; eating uses `query_overlapping`, not `query_circle`. [design](docs/design.md#dot2dgrid-is-why-a-crowded-world-is-possible)
- Interest scales with radius, not mass. [design](docs/design.md#interest-scales-with-size)
- Radius is derived on receipt, never replicated; `WORLD_EXTENT` must cover the arena on both peers. [design](docs/design.md#replication-is-2d-deliberately)
- Admin state lives in `Dot2DState.admin`, never `flags` (the game's); a game's behaviour declares `var net_admin: int`, and skips its own geometry when `is_noclipped` inside the replayed function. [design](docs/design.md#an-administrators-noclip-freeze-and-speed-are-in-the-state)
- Name no class outside dot-core: dot-net is reached through `Variant` and type names as strings. [design](docs/design.md#coupling-nothing-is-imported)

Deliberately not here: splitting and merging (`Dot2DMassRules` holds numbers nothing here reads), ejecting mass, teams, turret rotation, tile maps and navigation, client interpolation, art. [design](docs/design.md#deliberately-not-here)
