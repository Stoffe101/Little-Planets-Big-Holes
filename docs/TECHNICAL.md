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
`tools/dev/lodproto.tscn` (streaming, editability and persistence on real Voxel Tools) and by
what the player experiences:

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

* `VoxelLodTerrain` + `VoxelMesherTransvoxel`, 16³ mesh blocks, node scaled by `voxel_size`
  (0.5 m). Octree sized to contain the planet (Pipseed: 8 LODs over 2048 voxels).
* **Clipbox streaming** with `lod_distance` 96 voxels: full-resolution, *editable, collidable*
  voxels within ~70 m of the viewer, coarser LODs out to the far side (the whole planet is
  always drawn). Octree streaming was 5–50× slower to become ready; `full_load_mode` with
  Clipbox failed. The `VoxelViewer` is a child of the player.
* **Readiness.** `is_area_ready(center, r)` = voxels editable + LOD0 meshing finished + every
  existing LOD0 mesh block in the box has an *active collider*. Voxel Tools activates LODs from
  the top of the octree down, so a block can be meshed seconds before its collider exists; the
  loading screen, the player's "hold while ground streams in", relay travel, tests and tools
  all wait on this. (Uses `debug_get_mesh_block_info`, which exists in release builds too.)
* **LOD transitions.** Transvoxel transition meshes and secondary vertex positions are decoded
  in `terrain.gdshader` (`transvoxel_position`: CUSTOM0 bits 0–5 cell border, 8–13 vertex border,
  16+ transition side; the engine sets `u_transition_mask`).
* **Queries outside the loaded area** fall back to the analytic original surface (`sdf_at`), so
  bots, props and placement can reason about far ground without forcing it to load.
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

Measured in the 400-dig stress test: `dig_sphere` averages **1.7 ms** on the LOD terrain (v0.2:
0.25–0.9 ms on `VoxelTerrain`), because each edit also updates the coarser LOD copies of the
edited blocks. That is well under a frame but worth watching for very fast tools.

## Measured performance

All numbers from this machine: Windows 11, Ryzen 7 5800X3D, RTX 5070, Godot 4.7.2, Mobile
renderer, v-sync off, window on an off-screen desktop (`tools/perf.sh`). A 1440-row request
yields a 1421-row window there. Run-to-run variation between repeats was about ±10 %.

**Loading and memory (Pipseed, 1920×1080):** terrain ready with colliders at the spawn 2.2–2.4 s
after start (incl. 0.45 s geology bake from cache); world ready (props, outpost, caverns) 3.5–3.8 s.
Static memory 300 MB after arrival, 373–387 MB after the whole benchmark; video memory
329 / 431 / 507 MB at the three resolutions (+~25 MB by the end). ~12,400 voxel data blocks and
3,000–3,800 mesh blocks loaded at any time. Saving progress + all terrain edits after the run:
14–15 ms; database ~970 KB.

| Scenario (avg FPS / p99 ms / max ms; GPU ms) | 1920×1080 | 2560×1421 | 3440×1421 |
|---|---|---|---|
| Vista from a mountain | 117 / 15.8 / 16.0; 0.7 | 119 / 15.2 / 15.8; 1.0 | 105 / 15.6 / 16.3; 1.3 |
| Outpost in view | 105 / 16.1 / 16.8; 1.4 | 96 / 16.2 / 16.5; 1.8 | 86 / 17.5 / 24.0; 2.6 |
| Power shovel held down | 95 / 17.0 / 17.9; 2.0 | 86 / 17.7 / 18.4; 3.1 | 78 / 18.5 / 20.5; 3.6 |
| Eight 6.5 m blasts + debris | 99 / 18.5 / 25.3; 1.8 | 93 / 16.9 / 21.4; 2.5 | 99 / 15.8 / 29.3; 3.3 |
| Crystal cavern | 93 / 17.2 / 18.4; 2.1 | 91 / 16.4 / 19.2; 3.1 | 104 / 14.1 / 14.5; 4.0 |
| Three bots, 150 chunks | 99 / 18.0 / 19.1; 1.7 | 96 / 17.1 / 20.7; 2.1 | 96 / 15.0 / 16.4; 2.4 |
| Sprint + jetpack traversal (streaming) | 94 / 27.4 / 34.8; 1.4 | 94 / 26.2 / 41.4; 1.9 | 93 / 27.8 / 44.6; 2.2 |
| First 240 frames after a 300 m jump | 69 / 66.5 / 118; 1.1 | 73 / 62.1 / 96.6; 1.6 | 74 / 46.1 / 90.6; 2.0 |

After a 300 m relay jump the ground under the player has live colliders after 1.7–1.8 s; the
player is held until then ("Surveying ground...").

**Reading these numbers honestly.** v0.2 ran at 500–880 FPS and was GPU-bound on a tiny,
fully loaded planet. The big streamed planets run at ~80–120 FPS here and are **CPU-bound**: the
GPU needs 1–4 ms, the frame takes 8–13 ms. The CPU cost has not been profiled in detail yet;
candidates are prop-cell streaming, physics with thousands of static prop bodies, Voxel Tools'
main-thread work and the HUD. Streaming causes frame-time spikes: the 99th percentile while
sprinting is ~27 ms, and the first frames after a long jump spike to 90–120 ms (hidden behind the
travel flash, but real). See ROADMAP for the planned work. Not measured: other GPUs/CPUs, 4K,
long-session thermals.

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
  writes a verbatim `progress.v2.json`, and never opens, changes or deletes the old terrain file.
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
