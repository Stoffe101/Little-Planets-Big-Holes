# CLAUDE.md — working notes for AI agents

**Little Planets, Big Holes** — first-person incremental excavation on tiny spherical voxel
planets. Godot **4.7.2**, GDScript only, terrain by **Voxel Tools 1.7** (GDExtension, vendored
in `addons/zylann.voxel/`). Read `README.md`, then `docs/ART_DIRECTION.md` (before touching
anything visible) and `docs/TECHNICAL.md`.

## Commands

Set `GODOT` to the Godot executable (on Windows the `*_console.exe`; run the scripts from Git
Bash). The scripts fall back to `godot` on PATH.

```bash
tools/check.sh                                                    # import + compile every script (run after adding a class_name!)
"$GODOT" --headless --path . res://tests/run_tests.tscn           # full test suite (~1 min, exit code 1 on failure)
"$GODOT" --headless --path . res://tests/run_tests.tscn -- world  # filter suites by filename substring
tools/shots.sh <scenario> <prefix> [planet] [WxH] [godot args]    # render screenshots with the real renderer, off-screen
tools/perf.sh [WxH] [mobile|forward_plus] [planet]                # GPU frame-time benchmark, off-screen
"$GODOT" --headless --path . res://tools/dev/econ.tscn -- 60      # economy / pacing simulation
"$GODOT" --headless --path . res://tools/dev/bench.tscn           # CPU terrain benchmark
"$GODOT" --headless --path . res://tools/dev/sheet.tscn -- out.jpg <cols> <tile_w> img...   # contact sheet
python tools/audio_report.py [--gains]                            # objective audio checks
python3 tools/gen_audio.py                                        # regenerate assets/audio (numpy; ffmpeg for music)
```

`godot -s some_script.gd` cannot see autoloads at compile time — make dev tools scenes
(`tools/dev/*.tscn`) instead.

**Never open a visible game window from automation.** On Windows `tools/shots.sh` and
`tools/perf.sh` go through `tools/offscreen.py`, which runs Godot on a separate, invisible
desktop (real GPU, no focus change, no input). On Linux they use xvfb. Any automated run of the
real app flow must redirect `SaveSystem.save_dir` first (`start_game(true)` deletes the save).

## Layout

* `data/*.json` — **all** balance and content. Change numbers here, not in code; then run the
  economy simulator and update `docs/BALANCE.md`.
* `src/autoload/` — `Settings`, `GameData`, `GameState` (rules, no scene access), `SaveSystem`, `Audio`.
* `src/planet/geology.gd` — planet shape + materials; mirrored by `shaders/terrain.gdshader`.
* `src/game/dig_system.gd` — the only place voxels are edited.
* `src/game/world.gd` — assembles a planet session (also sky, sun, ambient); `src/game/main.gd` — app flow.
* `src/core/mesh_kit.gd` — procedural modelling kit; `src/core/palette.gd` (`Pal`) — every model colour.
* `src/tools/tool_models.gd` — all tool tiers and attachments; `tool_controller.gd` — behaviour and viewmodel animation.
* `src/base/rocket_base.gd` — the outpost; `src/planet/prop_field.gd` — surface dressing.
* `src/ui/ui_theme.gd` — the UI design system; `shop_ui.gd` + `tool_preview.gd` — the shop.
* `tests/` — `TestSuite` subclasses, auto-discovered `test_*` methods.

## Rules that keep the project healthy

1. **Terrain edits go through `DigSystem`** (`dig_sphere` / `dig_capsule`). Never call
   `VoxelTool` from gameplay code — this is the future multiplayer replication point.
2. **`Geology.material_for` and the first half of `terrain.gdshader` must stay in sync.** The
   shader is split into "WHAT is here" (mirror of gameplay) and "HOW it looks". Restyle only
   the second half; if you change how strata or ores are decided, change both sides.
3. **The planet is at the world origin, unrotated.** Code assumes world metres == planet
   metres; voxel coords = world / `voxel_size`.
4. **"Up" is never `Vector3.UP`** in gameplay code. Use `planet.up_at(pos)` / `player.up`.
5. **No physics bodies for loot.** Pickups collide against the voxel SDF (`planet.sdf_at`).
6. **Models are code, and follow `docs/ART_DIRECTION.md`.** Build with `MeshKit`; manufactured
   things use the hard-surface primitives (`hbox`, `prism`, `lathe`, `louvre`…) with a finish
   set (`paint()`, `bare()`, `rubber()`…); natural things are faceted (`rock`, `crystal`).
   Colours come from `Pal` (models), the planet palette (terrain, sky, foliage) or `UiTheme`
   (interface) — no hex codes in model code. One accent (`AMBER`), small lights, emission
   within the budget in the art-direction doc.
7. **Anything the player buys must change something visible** (tool model part, base
   installation, stat line in the shop). `test_every_tool_tier_and_mod_builds_a_model` enforces
   that each attachment level adds geometry.
8. **Custom shaders that write `POSITION` must write it on every path** (see `prop.gdshader`).
9. **Do not claim visual or audio results you did not observe.** Headless tests prove logic
   only. Render with `tools/shots.sh` and look at the images before describing them; say
   plainly when audio was measured but not heard.
10. Saves: bump `GameState.SAVE_VERSION` and add a step to `SaveSystem.migrate` when the
    layout changes; `from_dict` must keep tolerating missing/unknown fields. Never change
    material ids/order or a planet's terrain shape, caves, cavities or seed — saved terrain
    blocks would no longer match regenerated ground. Palettes, props and prices are safe.
11. **Props are seeded per item** (`PropField._item(kind, index)`): draw all of an item's random
    numbers right after that call. Do not share one advancing RNG across items, or digging in
    one place reshuffles props (and crystal flags) elsewhere.

## Gotchas already paid for

* Voxel Tools mesh blocks are separate instances → terrain shader uses `MODEL_MATRIX * VERTEX`.
* `NODE_DISTANCE_3D` ignores constant inputs in 1.7 → use translated `SdfSphere`.
* `SdfSphere` radius is input port 3, not a parameter.
* Terrain meshing/collision is asynchronous: in tests use `wait_until(...)`, never a fixed sleep.
* `RenderingServer.frame_post_draw` never fires headless — guard screenshot code.
* GDScript infers `Variant` from untyped dictionary reads and treats that as an error here —
  annotate (`var x: float = d["k"]`).
* A new `class_name` is invisible until `godot --headless --path . --import` has run.
* Vertex colours reach shaders raw; `prop.gdshader` converts sRGB → linear itself, so `Pal`
  values look as authored. Uniform colours need `source_color`.
* A tiny planet's horizon sits far below eye level: the sky gradient is driven by
  `horizon_dip`, and the sky's *lighting* (cubemap pass) uses the ground colour below it.
* Strata bands on floors/ceilings smear into contour swirls → the terrain shader only draws
  them on walls (`wall` factor).
* The viewmodel is re-projected with a fixed FOV in the vertex shader; tool rest poses in
  `ToolController.REST` are tuned for that FOV, not for the camera's.
* Teleporting the player makes the viewmodel sway spike; `ToolController` ignores look deltas
  over ~0.5 rad, and screenshot scenarios wait ~40 physics frames after `place()`.
* A decorated window is clamped to the desktop work area (1440-high requests become 1421):
  quote the real size the tools print.
* Git Bash heredocs choke on some quoted Python/GDScript; write patch scripts to a file.
* MSDF rendering of system fonts shows notches at small sizes → `UiTheme` uses plain
  rasterised fonts.

## Adding content (the usual jobs)

* **New material**: append to `data/materials.json` (max 24), reference it from a planet.
  Optional `roughness` / `metallic` override the category finish.
* **New tool tier / attachment / gear level**: edit `data/tools.json` / `data/gear.json`; add
  the look in `src/tools/tool_models.gd`; run the economy simulator; tests in `test_a_data`
  and `test_i_overhaul` validate table shapes and model changes.
* **New planet**: add `data/planets/<id>.json` (copy `glimmerock.json`) with its `palette`,
  `look` and `props` blocks, give it discoveries in `data/discoveries.json` and optionally a
  `music_<id>` track. No code required.
* **New discovery**: entry in `data/discoveries.json` + an artifact/cavity in the planet file;
  use `requires: {"discovery": "<id>"}` on shop items to make it unlock something; add a model
  and a small "setting" in `SecretsManager`.
* **New screenshot scenario**: a `scenario_<name>` method in `tools/dev/shots.gd`.
