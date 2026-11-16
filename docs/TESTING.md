# Testing

Set `GODOT` to the Godot 4.7.2 executable (on Windows the `*_console.exe`; run the shell
scripts from Git Bash). Everything falls back to `godot` on PATH.

## Automated tests

```bash
"$GODOT" --headless --path . --import                              # after cloning / adding class_names
"$GODOT" --headless --path . res://tests/run_tests.tscn            # everything (~6-8 minutes)
"$GODOT" --headless --path . res://tests/run_tests.tscn -- world   # only suites whose filename contains "world"
tools/check.sh                                                     # compile every script; fails if Godot did not run
```

The runner prints `[PASS]/[FAIL]` per test and exits with code 1 on any failure (CI uses this,
see `.github/workflows/tests.yml`, on Linux). Tests redirect all saves to
`user://test_sandbox/`, so they never touch a real save.

### What is covered (105 tests, 2,199 assertions)

| Suite | Checks |
|---|---|
| `test_a_data` | JSON databases load; every material/discovery/planet/gear reference resolves; every material can be dug by some purchasable tool |
| `test_b_state` | capacity, sell value, multipliers, tiers, mods, gear, lock reasons, objectives, discoveries, planet unlock, serialisation, garbage-tolerant loading |
| `test_c_save` | round trip, backup rotation, corrupted/truncated/tampered saves, v1 migration, **v2 → v3 migration keeps every kind of progress, writes a byte-identical `progress.v2.json`, never touches the old terrain file, falls back to a v2 backup**, terrain generations round trip, delete |
| `test_d_geology` | determinism, seeds, pad flat out to 12 m, strata, starter shovel, ore abundance, octahedral mapping, generator graph = CPU shape |
| `test_e_world` | spawn; gravity/orientation around the planet; walking the curve; jump; zero-g core; dig + **collision follows**; yields; hardness; selective dig; walkable hillside tunnel; **digs in unloaded terrain are refused**; pickups; tool controller; pad protection; selling; formations; scanner; cannon; helper bot; artifacts, cavern and heart discoveries; 400-dig stress in a streamed area + queue drain |
| `test_f_persistence` | dig a tunnel, **walk 260 m away (it unloads) and back: still there**; save, quit, reload in a new session: same SDF, standable, progress restored; control slot; **resurveyed planet: new generation database, old file byte-identical, notice once** |
| `test_g_planets` | Glimmerock loads and plays by its own rules |
| `test_h_main` | real `main.tscn` flow: menu → new game → play → shop → menu → continue |
| `test_i_overhaul` | every tier/mod builds and adds geometry; MeshKit; palette/look data; balance invariants; old flags load; arrival; props deterministic per cell and item; landmarks uprooted; nothing grows through the pads; outpost grows; purchase presentation; Lucky Charm; shop views |
| `test_j_traversal` | world rotation rate, largest per-frame change of up, roll while walking, sprinting + jumping, jetpack flight, strafing with turning on a hillside, in a tunnel; horizon smoothing eases a sudden change and 0 = rigid; **walking the rough regions of both planets never sinks into the ground** |
| `test_k_identity` | palette rules (no near-white enamel, verdigris accent, warm frames); every viewmodel has gloved hands, previews do not; stations collide as drums; the lander is squat |
| `test_l_navigation` | relays on the surface, shielded, in named regions on every planet; **relay transit covers the jump frame, holds the player still until the ground is collidable and releases onto the ground; every relay on both planets has a clear arrival spot**; region entry announced and remembered; relay activation and the travel rules (no jump from the field, recall from anywhere, outpost ↔ online relay); compass bearings and heading; map projection round trip and true distances; waypoint survives save/load; map relief image |
| `test_m_activities` | contracts deterministic per slot and paid through ordinary sales (player and bots); relay and depth contracts complete from world state; **the Auto-Borer digs a real shaft, lifts spoil, saves progress, pauses when its area streams out, resumes, stalls on hard rock**; bots work a marked zone and unload at the nearest relay |
| `test_o_stability` | collider vs voxel surface around a buried mesh-block corner (26 rays, ≤0.3 m, again after a second edit); a 30 m tunnel across block faces walked end to end; four save/quit/load sessions keeping all 8 holes; 14 relay jumps all landing on the ground with bounded memory; 12 s sprint + jetpack runs on both planets never inside the ground and rarely held |
| `test_n_terrain` | LOD pyramid covers the planet (LOD0 colliders near, far side visible at coarse LOD, transition masks at LOD seams); caves exist at depth and never under the pad; regions are measurably richer in their ore; **memory stays bounded while jumping around the planet**; loading three planets in turn grows static memory < 250 MB; **the physics-ray readiness fallback never reports ready before the block query does** |

### Pre-existing tests changed in v0.3, and why

The planets grew 8× and are streamed, so tests that hard-coded small-planet distances or touched
far-away terrain without loading it were adapted. None was loosened in what it checks:

* `test_d_geology.test_landing_pad_is_flat`: sampled 0.1 rad out (5 m on the old planet, 40 m
  on the new one, outside the pad); now rings at 5, 9 and 12 m.
* `test_e_world`: every test that digs or stands far from the outpost first streams the area in
  (`stream_to`); the 400-dig stress test digs inside one streamed area instead of all over the
  planet; the artifact reward is checked as the money *delta* (streaming into caverns discovers
  them, which pays their own rewards); the helper-bot loot lies 14 m from the base in metres
  (it was 0.28 rad, i.e. 14 m on the old planet).
* `test_f_persistence`: streams the tunnel area in; the untouched control points are 35 m from
  the dig (on the small planet "elsewhere on the planet" was always loaded; here they must be
  loaded and outside every edited block); added the walk-away-and-return check.
* `test_g_planets`: streams the dig spot in before digging.
* `test_i_overhaul`: the prop field is a streamed cell grid now, so the test builds the cells
  around one focus for both fields and compares landmarks through `live_items()`; the dig that
  must not move crystals is 35 m from the pad (in the loaded area); new crystal flag keys keep
  the `/crystal_` namespace.

### What automated tests cannot tell you

They run headless: **nothing about how the game looks, sounds or feels is verified by them.**

## Rendering without touching the desktop

```bash
tools/shots.sh <scenario> <output_prefix> [planet] [WxH] [extra godot args]
tools/shots.sh tour C:/tmp/tour pipseed 1920x1080
tools/shots.sh base C:/tmp/fp pipseed 1920x1080 --rendering-method forward_plus
```

Scenarios (`tools/dev/shots.gd`): `spawn`, `dig`, `base`, `ui` (HUD, shop, purchase, gear,
journal, planets, pause, discovery card), `tools` (every tier in first person), `lineup` (every
tier bare and fully fitted, studio view), `purchase`, `tour` (quarry, tunnel, cavern, heart),
`surface`, `menu`, `action` (dig + scan with HUD), `motion` (eight-frame film strips of the
first-person animations with game time slowed; tile them with `sheet.tscn`), `vistas`
(horizon, traversal, distant landmark, three regions, a cave mouth), `nav` (relay, compass,
survey map), `borer` (the Auto-Borer at work). Every scenario streams the terrain in and waits
for the voxel engine to settle before each shot.

* **Windows:** `tools/offscreen.py` creates a separate desktop object and starts Godot on it.
  The window is rendered by the real GPU but can never take focus, appear on screen or receive
  your input. (Launching Godot normally with a "no focus" window setting still took the
  foreground for about two seconds in testing — do not do that.)
* **Linux:** `xvfb-run` with a software Vulkan driver (`xvfb`, `mesa-vulkan-drivers`).

Contact sheets and JPEG conversion: `res://tools/dev/sheet.tscn` (headless).

## Benchmarks and profiling

```bash
tools/perf.sh [WxH] [mobile|forward_plus] [planet]            # GPU frame times, off-screen, v-sync off
"$GODOT" --headless --path . res://tools/dev/bench.tscn      # CPU: load, editable radius, dig timings, save
python tools/perf_compare.py --before <old checkout> --res 3440x1440 --reps 3   # before/after, same code
tools/profile.sh [WxH] [planet] [only=traverse,relay] [off=props]               # Godot's own profiler
"$GODOT" --path . res://tools/dev/streamprobe.tscn -- pipseed plain|prestream|run 300   # streaming, per frame
"$GODOT" --headless --path <old> res://tools/dev/savecompat.tscn -- write <dir>  # then `check <dir>` here
```

* **Read `nvidia-smi` first.** The off-screen window shares the GPU with whatever the user is
  running; with a game on the visible desktop (92–96 % GPU load during pass 3.1) every build,
  v0.2 included, tops out around 120–140 FPS. `perf_compare.py` alternates the two checkouts
  and logs GPU load before each run; renderer CPU ms, draw calls, the profiler's script and
  physics time and streaming spike frames are far less affected than FPS.
* `perf.gd off=<systems>` switches whole systems off for A/B attribution (props, hud, audio,
  shadows, glow, msaa, sky_realtime, draw3d, ...). Never quote those numbers as the game's.
* `profile.sh` runs a headless stand-in for the editor debugger (`tools/dev/profiler_host.gd`)
  and the game with `--remote-debug`: per scenario it prints frame/process/physics/script time,
  the slowest 5 % of frames, per-pass render CPU/GPU timestamps and the top script functions.
  It adds overhead to every script call: attribute with it, measure with `perf`.
* `streamprobe` prints every frame after a long jump with the mesh/data block deltas, queued
  generation/meshing/main-thread tasks and the terrain's own update timings; `run` sprints with
  jets for N seconds and counts frames held waiting for ground.

`perf` prints load time, memory and video memory, then runs eight scenarios (mountain vista,
outpost, power shovel held down, eight 6.5 m blasts, crystal cavern, three bots hauling 150
chunks, a sprint + jetpack traversal while terrain streams, the first 240 frames after a 300 m
jump) with average FPS, p95/p99/max frame time and the renderer's CPU/GPU time, and finally the
time to save all terrain edits. Results: `docs/TECHNICAL.md`.
Caveats: the window is on a desktop that is not being composited, so presentation is
unthrottled; a decorated 1440-high window is clamped to 1421 pixels (the tool prints the size).

## Economy simulation

```bash
"$GODOT" --headless --path . res://tools/dev/econ.tscn -- 60 balanced
"$GODOT" --headless --path . res://tools/dev/econ.tscn -- 60 explorer   # works rich regions via relays
"$GODOT" --headless --path . res://tools/dev/econ.tscn -- 30 balanced glimmerock after=40   # 40 min Pipseed first
```

See `docs/BALANCE.md` for assumptions and results.

## Audio checks

```bash
python tools/audio_report.py --gains
```

Per-file peak/RMS/active level, crest factor, clipped samples, DC offset, a brightness
estimate, clicks at the ends and loop seams (relative to normal sample-to-sample steps). It
cannot say whether a sound is pleasant.

## Exported build

```bash
"$GODOT" --headless --path . --export-release "Windows Desktop" build/windows/LittlePlanetsBigHoles.exe
build/windows/LittlePlanetsBigHoles.exe --headless -- --smoke-test
```

`--smoke-test` starts a new game in `user://smoke_test`, waits for the planet, digs once
through `DigSystem`, saves, prints `SMOKE OK` / `SMOKE FAIL: …` and sets the exit code.

## What was actually verified in the v0.3 pass

**Looked at (GPU renders, see `docs/screenshots/v0.3/README.md` for the list and notes):** all
18 requested subjects including horizon, outpost, traversal, landmarks, three regions, surface
and deep excavation, a cave mouth, tunnel, grotto, the Heart, every tool tier in first person and
in a studio line-up, mining effects, scanner, map, compass, a relay, the Auto-Borer, Glimmerock,
the main menu, the workshop and shop screens, HUD, 3440×1421; eight v0.2-vs-v0.3 comparisons;
six motion strips. Looking found and led to fixing: egg-crate terrain in Stonebrake that the
player sank into, an inverted ground-cover mask, buried workshop geometry, an unreadable map.

**Measured, not seen or felt:** camera rotation and roll while moving (tests), frame times, load
times, memory, save times (perf), pacing (simulation), streaming readiness times.

**Not verified by anyone:** how traversal *feels* (the main goal; see `docs/PLAYTEST.md`), any
audio, whether the new identity reads as original and appealing, real pacing, Glimmerock
pacing, other hardware, the Linux build, gamepad.

## What was verified in the v0.2 pass

The v0.2 renders, strips and benchmarks are in `docs/screenshots/` (top level) and the v0.2
version of this file in git history.

## Writing a test

Add `tests/test_<letter>_<topic>.gd` extending `TestSuite`; every `test_*` method is discovered
and may `await`. Use `make_world()` / `free_world()` for a headless planet; **`stream_to()` before
touching anything far from the player** (the terrain is streamed; `place_player()` does it for
you); `wait_until()` for anything that depends on asynchronous meshing; and the `forced_move`,
`forced_sprint`, `forced_jump`, `forced_hold_jump`, `forced_use` hooks on `Player` /
`ToolController` to drive input.
