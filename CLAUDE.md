# CLAUDE.md — working notes for AI agents

**Little Planets, Big Holes** — first-person incremental excavation on tiny spherical voxel
planets. Godot **4.7.2**, GDScript only, terrain by **Voxel Tools 1.7** (GDExtension, vendored
in `addons/zylann.voxel/`). Read `README.md` first, then `docs/TECHNICAL.md`.

## Commands

```bash
tools/check.sh                                                  # import + compile every script (run after adding a class_name!)
godot --headless --path . res://tests/run_tests.tscn            # full test suite (~1 min, exit code 1 on failure)
godot --headless --path . res://tests/run_tests.tscn -- world   # filter suites by filename substring
godot --headless --path . res://tools/dev/bench.tscn            # terrain benchmark
tools/shots.sh <scenario> <prefix> [planet] [WxH]               # render screenshots (needs xvfb + mesa-vulkan-drivers)
python3 tools/gen_audio.py                                      # regenerate assets/audio (numpy; ffmpeg for music)
```

`godot -s some_script.gd` cannot see autoloads at compile time — make dev tools scenes
(`tools/dev/*.tscn`) instead.

## Layout

* `data/*.json` — **all** balance and content. Change numbers here, not in code.
* `src/autoload/` — `Settings`, `GameData`, `GameState` (rules, no scene access), `SaveSystem`, `Audio`.
* `src/planet/geology.gd` — planet shape + materials; mirrored by `shaders/terrain.gdshader`.
* `src/game/dig_system.gd` — the only place voxels are edited.
* `src/game/world.gd` — assembles a planet session; `src/game/main.gd` — app flow.
* `src/core/mesh_kit.gd` — procedural modelling kit used for every model.
* `tests/` — `TestSuite` subclasses, auto-discovered `test_*` methods.

## Rules that keep the project healthy

1. **Terrain edits go through `DigSystem`** (`dig_sphere` / `dig_capsule`). Never call
   `VoxelTool` from gameplay code — this is the future multiplayer replication point.
2. **`Geology.material_for` and `terrain.gdshader` must stay in sync.** If you change how
   strata or ores are decided, change both, or players will dig something other than what they see.
3. **The planet is at the world origin, unrotated.** Code assumes world metres == planet
   metres; voxel coords = world / `voxel_size`.
4. **"Up" is never `Vector3.UP`** in gameplay code. Use `planet.up_at(pos)` / `player.up`.
5. **No physics bodies for loot.** Pickups collide against the voxel SDF (`planet.sdf_at`).
6. **Models are code.** Build with `MeshKit`, draw with `shaders/prop.gdshader`. Keep the
   palette bright and the shapes chunky; no default grey materials, no bare primitives.
7. **Anything the player buys must change something visible** (tool model part, stat line in
   the shop). Add the model change in `ToolModels` together with the data.
8. **Custom shaders that write `POSITION` must write it on every path** (see `prop.gdshader`).
9. **Do not claim visual or audio results you did not observe.** Headless tests prove logic
   only. If you render with `tools/shots.sh`, look at the images before describing them.
10. Saves: bump `GameState.SAVE_VERSION` and add a step to `SaveSystem.migrate` when the
    layout changes; `from_dict` must keep tolerating missing/unknown fields.

## Gotchas already paid for

* Voxel Tools mesh blocks are separate instances → terrain shader uses `MODEL_MATRIX * VERTEX`.
* `NODE_DISTANCE_3D` ignores constant inputs in 1.7 → use translated `SdfSphere`.
* `SdfSphere` radius is input port 3, not a parameter.
* Terrain meshing/collision is asynchronous: in tests use `wait_until(...)`, never a fixed sleep.
* `RenderingServer.frame_post_draw` never fires headless — guard screenshot code.
* Forward+ shows light-cluster tile artefacts under llvmpipe; the project uses the Mobile renderer.
* GDScript infers `Variant` from untyped dictionary reads and treats that as an error here —
  annotate (`var x: float = d["k"]`).
* A new `class_name` is invisible until `godot --headless --path . --import` has run.

## Adding content (the usual jobs)

* **New material**: append to `data/materials.json` (max 24), reference it from a planet.
* **New tool tier / mod / gear level**: edit `data/tools.json` / `data/gear.json`; add the
  look in `src/tools/tool_models.gd`; tests in `test_a_data` validate table shapes.
* **New planet**: add `data/planets/<id>.json` (copy `glimmerock.json`), give it discoveries in
  `data/discoveries.json` and optionally a `music_<id>` track. No code required.
* **New discovery**: entry in `data/discoveries.json` + an artifact/cavity in the planet file;
  use `requires: {"discovery": "<id>"}` on shop items to make it unlock something.
