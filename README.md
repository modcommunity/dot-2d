This is the **2D** asset for TMC's **Dot** collection. It is the 2D half of the movement layer, for games played from above rather than from behind the eyes.

This collection of assets provides modular building blocks for creating games and applications within the TMC ecosystem, ensuring consistency and interoperability across all `dot-*` assets. This includes core functionality, networking, authentication, cloud integration, and more.

**These assets are COMPLETELY OPEN SOURCE**. You are free to use, modify, and distribute them under the terms of the MIT license. The only thing not open source is the back-end web infrastructure. So if you opt into using your own authentication backend instead of integrating with TMC, you will need to build and integrate your own back-end infrastructure.

## From Maintainer & WARNING
This asset, along with all the others, was built initially with **Claude Code** and will continue to be maintained and extended using it. This is because I (`gamemann`) cannot build the entire TMC platform alone (I wish I could lol).

**Please treat this as partially tested.** Every asset has its own headless test suite and those suites pass, but very little of this has been in front of real players yet. Expect rough edges, and please report anything you run into.

I intend on reviewing code, testing, and editing documentation regularly. If you're interested in helping out, please let me know!

## Deterministic 2D Movement and World
A deterministic, command-driven 2D movement and world layer for Godot 4. Three feels
(top-down, thrust, mass-based blob), a spatial hash for thousands of entities,
deterministic scatter fields, and `Vector2` replication specs.

The 2D counterpart of [dot-fps-controller](../dot-fps-controller), and what
[game-blob](../game-blob) is built on. Part of the [dot-*](../NOTES.md) family. Needs
**dot-core** and nothing else.

## Install

Copy `addons/dot_2d/` and `addons/dot_core/` into your project and enable both in
*Project → Project Settings → Plugins*.

## Use

```gdscript
var arena := Dot2DArena.new()
arena.bounds = Rect2(Vector2(-2000, -2000), Vector2(4000, 4000))
add_child(arena)

var player := Dot2DController.new()
player.tunables = Dot2DTunables.blob()
add_child(player)
player.attach(arena, session_id)

# Once per simulated tick, on client and server alike.
player.simulate_tick(tick, 1.0 / 60.0)
arena.sync_grid()

# Who can this blob eat?
for id in arena.overlapping(state.position, state.radius, my_id):
    ...
```

## The idea

**The simulation is a pure function of a `Dot2DCommand`.** No device, no clock, no
node, no randomness. A client predicting a move, a server re-running it and a
reconciliation replay all reach the same position — the same contract
dot-fps-controller holds, in two dimensions.

The pointer is resolved to a **direction and a world-space distance** in the sampler,
before it goes on the wire. A screen position is meaningless on a server that has no
window and no camera, and that one decision is what makes an agar.io-like game
predictable at all.

## What is in the box

| | |
| --- | --- |
| `Dot2DCommand` | What a player asked for. Sanitised against everything a hostile client sends. |
| `Dot2DState` | Position, velocity, facing, radius, mass. Snapshot-able and replayable. |
| `Dot2DTunables` | How it moves. Top-down, thrust, or blob. |
| `Dot2DMassRules` | How mass becomes size, speed and the right to eat somebody. |
| `Dot2DMotor` | The simulation. Pure, deterministic, node-free. |
| `Dot2DBody` | What it collides against. `Flat` for a bounded arena, `Physics` for the rest. |
| `Dot2DGrid` | A uniform spatial hash. Two thousand entities, local queries. |
| `Dot2DScatter` | Pellet fields laid out from a seed, refilled on a per-tick budget. |
| `Dot2DArena` | The world: bounds, grid, interest rectangles, spawn positions. |
| `Dot2DController` | Drives one entity. Local, commanded or remote. |
| `Dot2DSampler` | Devices to commands. The only place input is read. |
| `Dot2DCameraRig` | Follows, zooms with size, stays inside the world. |
| `Dot2DNetSync` | What to replicate, without naming a dot-net type. |

## The three relationships a blob game balances on

`Dot2DMassRules` holds all three in one place, because they have to agree — a blob
whose drawn radius and whose eat radius come from different formulas visibly overlaps
things it cannot eat.

- **Radius grows as mass^0.5.** Area is radius squared, so twice the mass is √2 the
  width — which is what makes two small blobs equal to one big one.
- **Speed falls as mass^-0.44, with a floor.** Without the floor, the biggest blob on
  a long-running server is effectively stationary, which is not a challenge, it is a
  player who has stopped playing.
- **Eating needs a ratio *and* an overlap.** `can_eat` checks both in one call, because
  a game that checks them separately eventually checks only one — and the one usually
  forgotten is the distance, which is an eat at any range.

## Why `Dot2DBodyFlat` is the production backend

An agar.io world is a rectangle with nothing in it. A twin-stick arena is a rectangle
with some pillars. Both are cheaper analytically than in the physics server, and both
give **bit-identical answers on a client and a server** — which a physics query, whose
result depends on solver state from previous steps, does not.

`Dot2DBodyPhysics` exists for unpredicted entities and single-player games, and says so.

## Validating

```bash
godot --headless --path . --import
find . -name '*.gd' -not -path './.godot/*' | while read f; do
    godot --headless --path . --check-only --script "res://${f#./}"
done
godot --headless --path . res://examples/dot_2d_selftest.tscn
```

138 checks, all offline. Exits non-zero on any failure.
