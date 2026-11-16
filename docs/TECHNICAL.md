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
 │   ├─ PropField     MultiMesh ground cover, rocks, landmarks + crystal Formations
 │   ├─ RocketBase    the outpost: lander, Depot, Workshop, Outfitter, bot dock
 │   ├─ SecretsManager artifacts, cavern dressing, the planet Heart
 │   ├─ RobotManager  helper bots
 │   └─ Scanner
 ├─ Hud
 └─ UI layer: ShopUi, PlanetSelectUi, JournalUi, PauseMenu, MainMenu, LoadingScreen

Autoloads: Settings, GameData (res://data/*.json), GameState (progression rules),
           SaveSystem, Audio
Shared:    MeshKit (procedural modelling), Pal (model palette), UiTheme (interface)
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

### Measured performance (CPU side)

`godot --headless --path . res://tools/dev/bench.tscn` on the Windows development PC
(Ryzen 7 5800X3D, 8 voxel worker threads):

| Measurement | Result |
|---|---|
| Geology bake + generator compile | 0.83 s |
| Stream + mesh until playable | 2.5 s (≈3.2 s total; includes ~5,400 props) |
| Voxel data | 2,076 blocks, 16 MB |
| `dig_sphere` r = 0.85 / 1.5 / 2.4 / 3.4 / 6.5 m | 0.25 / 0.28 / 0.29 / 0.31 / 0.43 ms |
| Selective dig r = 1.5 m | 0.87 ms |
| Edit → collision updated | 11 physics ticks |
| Blocking save after ~350 large digs | 110 ms, 6.9 MB database |

## Rendering

All visual rules are in `docs/ART_DIRECTION.md`; this section is the plumbing.

* **Lighting model:** plain PBR (Burley diffuse, GGX specular), AgX tonemapping, ambient taken
  mostly from the sky shader, one four-split shadowed sun that follows the player, reflections
  from the sky. Tunables per planet live in the JSON `look` block (`sun_energy`,
  `sun_elevation`, `ambient_energy`, `exposure`, `atmosphere`, `stars`, `nebula`, `wind`…).
  `LPBH_LOOK='{"sun_energy": 2.0, "tonemap": "filmic"}'` in the environment overrides them for
  experiments.
* **Props, tools, machines:** `MeshKit` builds single vertex-coloured meshes drawn with
  `shaders/prop.gdshader` — COLOR = albedo (sRGB, converted in the shader), UV = emission and
  sway, UV2 = roughness and metallic. First-person tools set `viewmodel = true`, which squashes
  depth so they never clip into walls and re-projects them with a fixed 62° field of view.
* **Terrain:** `shaders/terrain.gdshader` — material lookup identical to gameplay, then a
  procedural relief normal (two octaves of value noise with analytic gradient, faded by
  distance), strata, turf skin with a damp band, ore bodies, depth-based ambient occlusion,
  scanner pulse.
* **Sky:** `shaders/sky.gdshader` — gradient from the planet's limb (`horizon_dip`), stars,
  sun, a neighbouring world and a moon; in the cubemap pass the lower hemisphere is the ground
  colour so bounce light is plausible.
* **Shop previews:** `ToolPreview` is a `SubViewportContainer` with its own 3D world, a camera
  framed from the model's bounds, key and rim lights and a turntable.

### Renderer: Mobile (measured choice)

Both Vulkan renderers were run on an RTX 5070 with `tools/perf.sh` (v-sync off, window on an
off-screen desktop, so presentation is unthrottled) and compared in still renders of the
outpost, a cavern and a fresh dig.

Average FPS (and GPU time per frame in ms). A request for 1440 rows yields a 1421-row window:

| Scenario | Mobile 1920×1080 | Mobile 2560×1421 | Mobile 3440×1421 | Forward+ 2560×1421 | Forward+ 3440×1421 |
|---|---|---|---|---|---|
| Surface | 879 (0.65) | 693 (0.91) | 615 (1.13) | 425 (1.83) | 354 (2.22) |
| Outpost in view | 819 (0.66) | 724 (0.89) | 629 (1.09) | 417 (1.88) | 350 (2.26) |
| Power shovel held down | 549 (1.09) | 476 (1.57) | 429 (1.74) | 341 (2.36) | 273 (3.01) |
| Eight 6.5 m blasts + debris | 605 (0.91) | 521 (1.38) | 431 (1.68) | 337 (2.37) | 256 (3.14) |
| Crystal cavern | 511 (1.43) | 356 (2.24) | 295 (2.68) | 239 (3.54) | 191 (4.54) |
| Three bots, 150 chunks | 557 (0.94) | 516 (1.27) | 466 (1.45) | 388 (2.01) | 326 (2.45) |

* CPU time for the viewport is 0.5–1.2 ms in every case: the game is **GPU-bound**, and far
  from any limit on this hardware. The 99th-percentile frame is under 6 ms everywhere; the
  worst single frames (5–16 ms) occur during heavy digging and on first use of an effect.
* Forward+ adds SSAO (wired in `World._build_environment`). Side by side, with this art style
  and the terrain's own depth occlusion, the two images are nearly indistinguishable, while
  Forward+ costs roughly twice the GPU time.
* **Decision:** stay on Mobile. Forward+ works without artefacts on real hardware and can be
  selected with `--rendering-method forward_plus`.
* Not measured: integrated or older GPUs, 4K, the F3 overlay's own cost, thermal behaviour
  over long sessions.

## Audio (`src/autoload/audio.gd`)

Pooled one-shots (2D and 3D), named loops with fades, music. `Audio.LEVEL` trims every sound to
the same measured loudness (table generated by `tools/audio_report.py --gains`), `Audio.SOFTEN`
lowers the pitch of the brightest effects, the SFX bus carries a low-pass and a reverb that
`World` drives from the player's depth (`set_underground`), and two ambience beds (wind, cave
tone) are synthesised at start-up from filtered noise (`_noise_bed`) and cross-faded by depth
and by the planet's `look.wind`.

## Exporting

`export_presets.cfg` has Windows and Linux presets. Non-resource files are not packaged by
default, so the presets include `data/*.json, data/planets/*.json` explicitly and exclude
`tests/`, `tools/`, `docs/`. `Main` implements `-- --smoke-test` (see docs/TESTING.md); the
exported Windows build passes it headless and on the Vulkan renderer.

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
