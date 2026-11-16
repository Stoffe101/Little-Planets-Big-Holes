# Technical overview

## Architecture at a glance

```
Main (scenes/main.tscn)               menu <-> gameplay, modal screens, planet travel, quitting
 ├─ World (one per loaded planet)
 │   ├─ Planet        VoxelLodTerrain (Clipbox streaming) + VoxelViewer + terrain material
 │   ├─ DigSystem     the ONLY code that edits voxels
 │   ├─ Player        CharacterBody3D, planet-centred gravity; carries the VoxelViewer
 │   │   └─ ToolController   input, tool behaviours, viewmodel animation
 │   ├─ PickupManager loose chunks (SDF-collided, no rigid bodies)
 │   ├─ FxManager     pooled GPU particles, rings, floating text
 │   ├─ PropField     streamed cube-sphere cells: cover, rocks, trees, landmarks, crystals
 │   ├─ RocketBase    the outpost: Seedpod lander, Depot, Workshop, Outfitter, bot dock
 │   ├─ SecretsManager artifacts, cavern dressing (built when their terrain streams in), Heart
 │   ├─ Navigation    regions, survey relays + travel, waypoint, compass/map markers
 │   ├─ Contracts     the open survey contract
 │   ├─ AutoBorer     the deployable shaft-sinking rig
 │   ├─ RobotManager  helper bots and their work zone
 │   └─ Scanner
 ├─ Hud (+ CompassStrip)
 └─ UI layer: ShopUi, MapUi, PlanetSelectUi, JournalUi, PauseMenu, MainMenu, LoadingScreen

Autoloads: Settings, GameData (res://data/*.json), GameState (progression rules),
           SaveSystem, Audio
Shared:    MeshKit (procedural modelling), Pal (model palette), UiTheme (interface)
```

`GameState` contains only rules and numbers (no scene access), which is why it can be unit
tested headlessly and why it is the natural place for server authority later.

## Planet scale: why 400 m

Pass 3 replaced the 48 m / 42 m planets. Candidate radii of 300–600 m were evaluated with
`tools/dev/lodproto.tscn` (a prototype that measures streaming readiness, editable distance and
persistence on real Voxel Tools; run it with `-- <radius> stream dig 1 96 cache`) and by what the
player experiences:

| Radius | World turns while walking (5.6 m/s) | At top speed | Horizon from eye height | Walk around the equator |
|---|---|---|---|---|
| 48 m (v0.2) | 6.7 °/s | 15.0 °/s | 12 m | 54 s |
| 300 m (Glimmerock) | 1.1 °/s | 2.4 °/s | 30 m | 5.6 min |
| **400 m (Pipseed)** | **0.8 °/s** | **1.8 °/s** | **35 m** (a 50 m mountain is visible from ~240 m) | 7.5 min |
| 600 m | 0.5 °/s | 1.2 °/s | 43 m | 11 min |

*Rotation figures are computed from the radius and measured in `test_j_traversal`; feel has
not been validated by a human (see `docs/PLAYTEST.md`).*

400 m is where walking stops feeling like balancing on a ball (under 1 °/s, about one-eighth of
v0.2) while the sphere still shows: you see hills drop below the horizon, the far side is a
real journey, and jet flights reveal the curve. Larger radii multiplied empty walking without
adding much comfort, and every metre of radius is LOD data and prop placement to stream.
Glimmerock, a low-gravity moon, is 300 m.

## Planets

A planet is described entirely by `data/planets/<id>.json`. The geography (radius,
generation, landforms, regions, layers, ores, caves, caverns, artifacts, relays, prop
densities) is written by `tools/planet_layout.py` from human units (metres along the surface
and a bearing from the landing site).

### `Geology` — the single source of truth (`src/planet/geology.gd`)

1. **Shape.** `height_exact(dir)` = hill noise + detail noise + regional roughness +
   **landforms** (domes/basins, flat-topped plateaus, craters with rims, ridges along great
   circles, seeded crater fields), flattened at the landing pad. Every landform is a function of
   `dot(n, dir)` (and, for ridges, a second axis), so it can be expressed in a voxel graph.
2. **Height bake.** `height_exact` is baked into a 256–1024² octahedral map (`WorkerThreadPool`
   group task, cached on disk under `user://planet_cache/` keyed by a hash of the shape inputs).
   `height_at` reads it bilinearly exactly like the GPU sampler; the shader uses the same texture.
3. **Regions** (up to 8): soft caps on the sphere that lift the strata, change turf colour and
   coverage, roughness, prop densities and **which ore is rich** (regional ore threshold blend,
   mirrored in the shader).
4. **The voxel generator graph** (`build_generator`) reproduces `height_exact` in a
   `VoxelGeneratorGraph` (C++, multithreaded), then subtracts worm caves, caverns with sloped
   entrances, sealed artifact pockets and the core chamber. Asserted equal to the CPU shape by
   `test_generator_graph_compiles_and_matches_cpu_shape`; sampled across LODs while debugging.
5. **Materials are a function, not voxel data** (`material_at`), and the terrain shader runs the
   same function per fragment. Saves only need the SDF channel.

### `Planet` (`src/planet/planet.gd`) — streamed LOD terrain

* `VoxelLodTerrain` + `VoxelMesherTransvoxel`, **32³ mesh blocks** (16³ data blocks), node
  scaled by `voxel_size` (0.5 m). Octree sized to contain the planet (Pipseed: 8 LODs over 2048
  voxels). 32 rather than 16 (pass 3.1): ~740 instead of ~3,100 mesh blocks for the same
  terrain, render CPU −40 %, and a 300 m jump unloads ~600 blocks in one 35–40 ms frame instead
  of ~3,000 in 100–140 ms; load time and edit-to-collision latency did not get worse.
* **Generated blocks are cached** (`cache_generated_blocks`). Without it every edit and every
  voxel read in a block nobody had edited regenerated that block from the generator graph on
  the main thread: 4–12 ms per first edit, `sdf_at` stalls up to 40 ms while streaming. Costs
  ~50–85 MB, bounded by the streaming area (tested).
* **Clipbox streaming** with `lod_distance` 96 voxels: full-resolution, *editable* voxels
  58–114 m from the viewer depending on direction and block alignment (collidable 50–102 m;
  `bench.tscn` measures it), coarser LODs out to the far side (the whole planet is always
  drawn). Octree streaming was 5–50× slower to become ready; `full_load_mode` with Clipbox
  failed. The `VoxelViewer` is a child of the player. Voxel Tools' main-thread budget is 4 ms
  per frame (`project.godot`, was the default 8): smoother traversal, colliders after a long
  jump ~0.3 s later.
* **Readiness.** `is_area_ready(center, r)` = voxels editable + LOD0 meshing finished + every
  existing LOD0 mesh block in the box has an *active collider*. Voxel Tools activates LODs from
  the top of the octree down, so a block can be meshed seconds before its collider exists; the
  loading screen, the player's "hold while ground streams in", relay travel, tests and tools
  all wait on this. (Uses `debug_get_mesh_block_info`, which exists in release builds too. If
  that query is missing or stops reporting `collision_active`, `readiness_mode` switches to a
  physics-ray probe; a test checks the probe never reports ready before the block query does.)
* **LOD transitions.** Transvoxel transition meshes and secondary vertex positions are decoded
  in `terrain.gdshader` (`transvoxel_position`: CUSTOM0 bits 0–5 cell border, 8–13 vertex border,
  16+ transition side; the engine sets `u_transition_mask`).
* **Queries.** `sdf_at` samples the loaded voxels trilinearly - the surface the mesh and its
  collider follow (it used the lower-corner voxel before, up to ~0.5 m off). `sdf_at_voxel` is
  that old stored-voxel read, kept only for the dig survey, whose yields the economy was tuned
  on. Outside the loaded area both fall back to the analytic original surface, so bots, props
  and placement can reason about far ground without forcing it to load.
* **Long jumps** (relay travel, recall) go through `TransitOverlay`: the view cuts to a transit
  card in the jump frame, the player is held until the destination's ground is collidable and
  most meshing is done (measured 1.2–2.5 s), then snapped onto the real ground and the card
  fades. The unload/remesh frames (35–55 ms) are never shown.
* **Persistence.** `VoxelStreamSQLite` with the key cache on (6× faster block loads); only
  modified blocks are stored, and blocks that stream out are written to it, so edits survive
  walking away (tested) as well as quitting.

### Props (`src/planet/prop_field.gd`)

The sphere is a cube-sphere grid of ~28 m cells. A near layer (tufts, ferns, pebbles, ≤72 m)
and a far layer (shrubs, trees, boulders, crystals, landmarks, ≤230 m) are built under a
2.5 ms/frame budget and freed behind the player. Everything is seeded per (cell, kind, index),
so a cell rebuilds identically and crystal flags stay valid. Cells built before their terrain
loaded are re-checked against the real (dug) SDF once it does. Relays and the outpost keep
their footing clear.

## Orientation and comfort

* The body re-aligns to the radial "up" every physics tick with the shortest rotation (no roll).
* The camera's up eases towards the body's (`horizon_smoothing`, default 0.25 s; 0 = rigid).
  Sudden changes of down (core chamber, teleports) are softened instead of snapping.
* Comfort settings: horizon smoothing, view bob, camera shake, sprint FOV widening, compass.
* Measured (`test_j_traversal`): walking turns the world 0.77 °/s, sprint + jumps with the best
  boots 1.7 °/s; largest per-frame change of up 0.03–0.06°; roll ≤ 0.2° while strafing and
  turning. A regression test walks the roughest regions and fails if the player sinks into
  the ground.

## Navigation, activities and machines

* **Regions** are announced on entry and remembered (`region/<planet>/<id>` flags).
* **Survey relays** (`relays` in the planet file): tall masts in outlying regions, online when
  you walk up. Travel between online relays and the outpost from the map; **recall** to the
  outpost from anywhere. The destination streams in while the player is held.
* **Map** (`MapUi`): azimuthal equidistant projection centred on the outpost (distances from
  home are true), relief rendered on a worker thread, zoom, waypoint by click.
* **Compass** strip: heading (north = the planet's −Z pole) and markers with distances.
* **Contracts** (`data/contracts.json`): relay / deliver / depth, generated per save slot.
* **Auto-Borer**: a rig that sinks a shaft through `DigSystem`, lifts spoil as chunks, stalls on
  rock above its level, pauses when its area streams out.
* **Bot zones**: bots sweep 40 m around a marked spot and unload at the closest online relay.

## Excavation (`src/game/dig_system.gd`)

Every edit goes through `dig_sphere` / `dig_capsule`: survey 56 sample points, decide (empty /
blocked / selective), edit with `VoxelTool`, yield units by material. **New:** an edit whose
area is not editable at full resolution (outside the streamed range) is refused and reported as
`unloaded` — nothing is dug and nothing counts.

Measured (`tools/dev/bench.tscn`, one dig per frame, 16–45 m from the outpost, pass 3.1):
`dig_sphere` takes **0.5–0.7 ms** (r = 0.85 / 1.5 / 2.4 / 3.4 / 6.5 m: 0.63 / 0.58 / 0.54 / 0.52 /
0.71 ms), of which the voxel edit is 0.02–0.21 ms and the 56-point material survey 0.43–0.57 ms;
selective digs 1.1 ms. v0.3.0 took 1.6–5.2 ms (and 11–12 ms for a 6.5 m blast into untouched
ground): the cost was **regenerating never-edited blocks on the main thread**, not the LOD
copies as guessed in pass 3 - with `cache_generated_blocks` on it is gone. v0.2 on
`VoxelTerrain` took 0.25–0.9 ms. Collision follows an edit after 6–7 physics ticks. A blocking
save after ~200 large digs takes 78 ms (3.6 MB database). World setup 0.83 s, terrain playable
after 2.1–2.3 s (headless).

## Measured performance

All numbers from this machine: Windows 11, Ryzen 7 5800X3D, RTX 5070, Godot 4.7.2, Mobile
renderer, v-sync off, window on an off-screen desktop. A 1440-row request yields a 1421-row
window there.

**Read this first: the GPU was shared.** During pass 3.1 another application (a game on the
visible desktop) kept the GPU at **80–96 % utilisation** for every benchmark (`nvidia-smi`, logged
per run by `tools/perf_compare.py`). Under that load *any* build tops out around 100–140 FPS:
v0.2, which pass 2 measured at 500–880 FPS, ran at 123–145 FPS here, the same as v0.3. With 3D
drawing switched off the whole game (scripts, physics, voxel engine, UI) takes ~0.9 ms per frame,
and even with every object hidden (9 draw calls) the frame took ~6 ms. So most of the "5–8×
regression" reported in pass 3 was this contention, not the game; pass 3's "CPU-bound, periodic
per-tick cost" reading was wrong. **No uncontended v0.3.x frame rate has been measured yet.** What
the game itself costs is visible in the columns that contention barely touches: the renderer's
CPU time, draw calls, Godot's profiler (script and physics time) and the streaming spike frames.

What the game really did cost, found with `tools/profile.sh` (Godot's own profiler, off-screen)
and `streamprobe`: (1) never-edited voxel blocks were regenerated on the main thread for every
edit and voxel query (digs 1.6–12 ms, `sdf_at` stalls up to 40 ms while streaming); (2) per-mesh-
block work after a long jump: ~3,000 blocks unloaded in one 100–140 ms frame, then ~6,700 meshing
tasks and 2–3 s of 15–30 ms frames; (3) renderer CPU about twice v0.2's (1,300–2,800 draw calls).
Fixes: cached generated blocks, 32-voxel mesh blocks, a 4 ms voxel main-thread budget, the relay
transit card. Script time is 0.3–1 ms per frame and physics 0.1–1 ms (profiler); prop streaming
is budgeted at 2.5 ms and stays under it except when cells are freed after a jump (~4–6 ms, behind
the card).

**Before (v0.3.0, e73f98b) / after (v0.3.1), same benchmark code, runs alternated, medians of
three each** (`python tools/perf_compare.py --before <v0.3.0 checkout> --res <WxH> --reps 3`).
Columns: avg FPS · p99 ms · max ms · renderer CPU ms · draw calls.

PERF_TABLES

**Loading and memory (1920×1080):** terrain ready with colliders at the spawn 2.2–2.4 s (same as
before), world ready 3.7–3.9 s. Static memory at the end of the run 405–415 MB (was 380: the
cached voxel blocks, ~56 MB); video memory 305 MB (was 351: a quarter of the mesh instances).
Saving all terrain edits 14–25 ms; database ~900 KB.

**What 165 Hz needs (an estimate, not a measurement).** 165 Hz leaves 6.06 ms per frame. The
CPU side measured here is ~0.9 ms of game logic plus 1.0–1.6 ms of renderer CPU when nothing
streams, and up to the 4 ms voxel budget more while terrain streams in; the GPU timestamps say
0.8–2.1 ms at 1080p (shared GPU). On an idle RTX 5070 that suggests standing and digging fits
comfortably in 6 ms, and fast jetpack traversal will sometimes not (streaming frames of 8–15 ms
were measured here). V-sync is on by default; with a non-VRR display a late frame halves the
rate for that frame. Measure it with `perf_compare.py` on an idle machine before relying on it.

Not measured: an idle GPU, other GPUs/CPUs, 4K, long-session thermals.

## Audio (`src/autoload/audio.gd`)

Pooled one-shots (2D and 3D), named loops with fades, music; per-sound level trims, a depth-
driven low-pass and reverb, synthesised wind/cave ambience. Unchanged in pass 3.

## Exporting

`export_presets.cfg` has Windows and Linux presets; data JSON is packaged explicitly. `Main`
implements `-- --smoke-test` (new game in a throw-away folder, waits for the planet, digs, saves).

## Saving (`src/autoload/save_system.gd`)

```
user://saves/slot1/progress.json             pretty JSON + "#sha256:<hash>" trailer
user://saves/slot1/progress.bak.json         previous good save
user://saves/slot1/progress.v2.json          verbatim copy of a save before it was upgraded
user://saves/slot1/terrain_<planet>.sqlite   generation-1 dig site (v0.x planets, kept, unused)
user://saves/slot1/terrain_<planet>_g2.sqlite  modified voxel blocks of the current planets
```

* Atomic write with verification and a rolling backup; checksummed; damaged saves fall back to
  the backup. `from_dict` clamps and drops unknown data.
* **Save version 3 / terrain generations.** A planet's `generation` changes whenever its shape,
  size or caves change. Each generation has its own terrain database, so old edits are never
  applied to new ground. Migration (v2 → v3) keeps all progression (credits, tools, attachments,
  gear, inventory, discoveries, objectives, stats), records which generation the save last saw,
  writes a verbatim `progress.v2.json`, and never opens or changes the old terrain file.
  (*New game* still clears the whole slot, including those files, exactly as in v0.2.)
  On first arrival the player is told once that the planet was resurveyed.
* **Limitation:** dig sites made in v0.1/v0.2 do not carry over to the new planets (they cannot:
  the ground they were dug into no longer exists). They stay on disk.
* Not saved: loose chunks, bot cargo in flight, player position (you start at the outpost).
  Saved since pass 3: relays online, regions visited, waypoint, contract, Auto-Borer site and
  depth, bot work zone (all as flags).

## Multiplayer considerations (not implemented)

Terrain edits are commands (`DigSystem`), geology is deterministic, `GameState` has no scene
references, pickups are data. Streaming adds one requirement: every peer needs its own viewer,
and an authoritative host must only accept edits inside an area loaded for the editing player
(the `unloaded` refusal is the hook). Single-player assumptions: `World.player`, the sun and
the prop streaming focus follow one player.
