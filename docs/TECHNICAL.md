# Technical overview

## Architecture at a glance

```
Main (scenes/main.tscn)               menu <-> gameplay, modal screens, planet travel, quitting
 ├─ World (one per loaded planet)
 │   ├─ Planet        VoxelTerrain + VoxelViewer + terrain ShaderMaterial, owns a Geology
 │   ├─ DigSystem     the ONLY code that edits voxels
 │   ├─ Player        CharacterBody3D with planet-centred gravity
 │   │   └─ ToolController   input, tool behaviours, viewmodel animation
 │   ├─ PickupManager loose chunks (SDF-collided, no rigid bodies)
 │   ├─ FxManager     pooled GPU particles, rings, floating text
 │   ├─ PropField     MultiMesh decoration + crystal Formations
 │   ├─ RocketBase    rocket, Sell-o-Matic, shop kiosks, bot dock
 │   ├─ SecretsManager artifacts, cavern decor, the planet Heart
 │   ├─ RobotManager  helper bots
 │   └─ Scanner
 ├─ Hud
 └─ UI layer: ShopUi, PlanetSelectUi, JournalUi, PauseMenu, MainMenu, LoadingScreen

Autoloads: Settings, GameData (res://data/*.json), GameState (progression rules),
           SaveSystem, Audio
```

`GameState` contains only rules and numbers (no scene access), which is why it can be unit
tested headlessly and why it is the natural place for server authority later.

## Planets

A planet is described entirely by `data/planets/<id>.json` and built by two classes.

### `Geology` — the single source of truth (`src/planet/geology.gd`)

One `Geology` instance derives everything from the config and seed:

1. **Shape.** `height_at(dir)` = fBm hills + detail noise + smoothstep mountain/basin bumps,
   flattened to a landing pad. `surface_radius(dir) = radius + height_at(dir)`.
2. **The voxel generator graph** (`build_generator`) reproduces exactly that function inside a
   `VoxelGeneratorGraph` (C++, multithreaded): `sdf = |p| - surface_radius(p/|p|)`, then
   * worm caves: `max(|n1|, |n2|) < width` for two 3D noises, masked to a depth band,
   * hand-placed caverns, their sloped entrance tunnels and sealed artifact pockets: translated
     `SdfSphere`s removed with `SdfSmoothSubtract`,
   * the hollow core chamber.
   The CPU and the graph share the same `ZN_FastNoiseLite` resources, so they agree exactly
   (asserted by `test_generator_graph_compiles_and_matches_cpu_shape`).
3. **Materials are a function, not voxel data.** `material_at(p)` computes depth below the
   *original* surface, warps it slightly, picks the stratum, then tests each ore: an ore exists
   where a tileable 3D noise exceeds a threshold inside its depth band. Thresholds are calibrated
   from the baked noise histogram so the designer writes an `abundance` fraction, not a magic
   number.
4. **The terrain shader runs the same function.** `Geology.apply_to_material` hands the shader
   the three noise volumes (96³, `sampler3D`), an octahedral height map of `height_at`, the
   strata table, ore table and palette. `shaders/terrain.gdshader` re-computes the material per
   fragment, so *what you see is what you dig* without storing a material per voxel. The CPU
   mirrors GPU trilinear filtering (`Geology.sample_noise`).

Consequences: saves only need the SDF channel; a planet is deterministic from its seed (the
same in every session and on every future network peer); adding a planet is a JSON file.

### `Planet` (`src/planet/planet.gd`)

* `VoxelTerrain` with `VoxelMesherTransvoxel`, 16³ mesh blocks, collisions on, scaled by
  `voxel_size` (0.5 m). One `VoxelViewer` at the centre keeps the whole small planet loaded.
* The planet sits at the world origin with identity rotation: world metres = planet metres.
  Voxel coordinates = world / `voxel_size`.
* Queries: `sdf_at`, `is_solid`, `ground_point(dir)` (marches the real, edited SDF),
  `gravity_at` (fades to zero inside the core chamber).

## Excavation (`src/game/dig_system.gd`)

Every edit goes through `dig_sphere(center, radius, power, opts)` or
`dig_capsule(a, b, radius, power, opts)`:

1. **Survey** 56 fixed sample points inside the bite: which are solid (voxel SDF) and what
   material (`Geology.material_at`). Hardness > tool power counts as "hard".
2. **Decide.** Nothing solid → empty. More than 72 % hard → *blocked* (clang, sparks, hint).
3. **Edit.** No hard material: one `VoxelTool.do_sphere` / `do_path`. Mixed: *selective dig* —
   copy the region, `do_sphere`, then restore every 2×2×2 voxel cell whose material is too hard
   and paste it back. Tough ore therefore survives as a nub you can see and return for.
4. **Yield.** `units = samples × volume_per_sample × material.yield (× ore bonus)`; fractions
   carry over to the next dig so nothing is lost to rounding.

Voxel data changes immediately; meshing and collision rebuild on Voxel Tools' worker threads
(only the touched 16³ blocks, never the planet).

Other terrain-adjacent rules: the launch pad is shielded (`World.is_protected`), props whose
base is dug out are uprooted (`PropField.on_dig`), crystal `Formation`s are cracked rather than
dug.

### Measured performance

`godot --headless --path . res://tools/dev/bench.tscn` on the 4-vCPU cloud VM used for
development (no GPU; Voxel Tools picked 2 worker threads):

| Measurement | Result |
|---|---|
| Geology bake + generator compile | 0.62 s |
| Stream + mesh until playable | 1.20 s (≈1.7 s total) |
| Voxel data | 2,076 blocks, 16 MB |
| `dig_sphere` r = 0.85 / 1.5 / 3.4 / 6.5 m | 0.19 / 0.23 / 0.30 / 0.36 ms |
| Selective dig r = 1.5 m | 0.67 ms |
| Edit → collision updated | 12 physics ticks (63 ms wall) |
| Blocking save after ~350 large digs | 55 ms, 6.9 MB database |

These are CPU-side numbers. **Frame rate on a real GPU has not been measured** — the
development machine only has a software rasteriser. Use the F3 overlay (FPS, draw calls, voxel
task queues, dig timings, memory) when profiling on real hardware.

## Rendering

* **Renderer: Mobile (Vulkan).** Forward+ also runs, but on the software rasteriser used for
  development its clustered lighting produced tile artefacts around omni/spot lights, so it
  could not be visually verified; Mobile rendered correctly and is what all screenshots were
  checked with. Switching to Forward+ (Project Settings → Rendering → Renderer) additionally
  enables SSAO (already wired in `World._build_environment`) and should be tried on a real GPU.
* One shared lighting model (`shaders/toon_light.gdshaderinc`): half-Lambert through two soft
  steps, softened shadows, linear tonemapping so palette colours appear as authored.
* All props, tools and machines are built by `MeshKit` into single vertex-coloured meshes drawn
  with `shaders/prop.gdshader` (vertex colour = albedo, UV.x = emission, UV.y = wind sway).
  First-person tools set `viewmodel = true`, which squashes depth so they never clip into walls.
* The sun follows the player around the planet so the playable side is always lit; ambient
  light dims with depth and a headlamp fades in underground.

## Saving (`src/autoload/save_system.gd`)

```
user://saves/slot1/progress.json        pretty JSON + "#sha256:<hash>" trailer
user://saves/slot1/progress.bak.json    previous good save
user://saves/slot1/terrain_<planet>.sqlite   modified voxel blocks (VoxelStreamSQLite)
```

* Write to a temp file → verify it parses and its checksum matches → rotate current → backup →
  rename temp → current. A torn write can never replace a good save.
* Load tries the main file, then the backup (and tells the player). Truncated files (no
  checksum trailer) and edited files (checksum mismatch) are rejected.
* `GameState.from_dict` clamps and drops anything unknown, so old or hand-edited saves degrade
  gracefully. `SaveSystem.migrate` upgrades older layouts (currently v1 → v2).
* Terrain: only *modified* blocks are stored; untouched ground regenerates from the seed.
  Autosave every 75 s, on planet travel, on returning to the menu and on quit.
* Not saved: loose chunks lying on the ground, helper-bot cargo in flight, player position
  (you always start at the rocket).

## Multiplayer considerations (not implemented)

The code was shaped so 2–4 player co-op can be added without rewrites:

* **Terrain edits are commands.** Tools never touch voxels; they call `DigSystem.dig_*` with
  (shape, position, radius, power, options). Replicating terrain = sending those small commands
  from an authoritative host and applying them on each peer. Because geology is deterministic
  from the seed, every peer computes identical yields and identical "blocked" decisions.
  Late joiners need the host's modified blocks: Voxel Tools ships
  `VoxelTerrainMultiplayerSynchronizer` for exactly that.
* **Progression is separate from presentation.** `GameState` has no scene references. For
  co-op it becomes per-player state (inventory, tools) plus shared state (discoveries, planet
  flags); the host validates purchases and sales.
* **Pickups are data** (`PickupManager.items`), simulated without physics bodies → cheap to
  replicate as spawn/collect events. Robots are simple state machines driven by that data.
* Things that assume a single player today and would need work: `World.player`, the sun
  following one player, `GameState` being a singleton, autosave ownership.
