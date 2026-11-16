# Testing

Set `GODOT` to the Godot 4.7.2 executable (on Windows the `*_console.exe`; run the shell
scripts from Git Bash). Everything falls back to `godot` on PATH.

## Automated tests

```bash
"$GODOT" --headless --path . --import                              # after cloning / adding class_names
"$GODOT" --headless --path . res://tests/run_tests.tscn            # everything (~1 minute)
"$GODOT" --headless --path . res://tests/run_tests.tscn -- world   # only suites whose filename contains "world"
tools/check.sh                                                     # compile every script; fails if Godot did not run
```

The runner prints `[PASS]/[FAIL]` per test and exits with code 1 on any failure (CI uses this,
see `.github/workflows/tests.yml`, on Linux). Tests redirect all saves to
`user://test_sandbox/`, so they never touch a real save.

### What is covered (72 tests, 1,437 assertions)

| Suite | Checks |
|---|---|
| `test_a_data` | JSON databases load; every material/discovery/planet/gear reference resolves; every material can be dug by some purchasable tool |
| `test_b_state` | capacity, exact sell value, multipliers, tool tiers, mods, gear, lock reasons, objectives, discoveries, planet unlock + fare, serialisation, garbage-tolerant loading (numbers are read from the data tables) |
| `test_c_save` | round trip, backup rotation, recovery from a corrupted main file, truncated/tampered saves rejected, v1 migration, delete |
| `test_d_geology` | same seed → same planet, different seed → different, flat landing pad, harder with depth, starter shovel can dig the surface, ore abundance matches config, octahedral mapping, generator graph agrees with the CPU shape |
| `test_e_world` | spawn on ground; gravity/orientation at six points around the planet; walking follows curvature; jump; zero-g core; dig removes voxels **and collision follows**; yields; blocked by hard layers; selective dig; **walkable tunnel into a hillside**; pickups, full backpack; shovel through the real tool controller; pad protection; selling on the pad; crystal formation; scanner; cannon crater; helper bot hauling and selling; artifact, cavern and heart discoveries; 400-dig stress + task-queue drain |
| `test_f_persistence` | dig a tunnel + chamber, save, unload, reload: same SDF values, player can stand in it, progress restored; control slot proves the tunnel is not there by default |
| `test_g_planets` | Glimmerock loads from data, lower gravity, own materials and hardness |
| `test_h_main` | real `main.tscn`: menu → new game → play → shop → menu → continue with the purchase intact |
| `test_i_overhaul` | every tool tier and every attachment level builds a model and adds geometry; moving parts exist; MeshKit primitives (size, outward normals, per-vertex finish, deterministic rocks); palette / look data complete and within the emission budget; balance-table invariants; a first-build save with obsolete flags still loads; arrival point (outside the pad, on the ground, facing the outpost); **digging never moves or renumbers a crystal**; the outpost gains installations with purchases and everything it builds stands on shielded ground; landmarks are uprooted when dug under; nothing grows through the pads; the new-tool presentation fires for purchases of the held tool only (not for discoveries) and waits for menus to close; the Lucky Charm stays a perk; the shop builds every view |

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
first-person animations with game time slowed; tile them with `sheet.tscn`).

* **Windows:** `tools/offscreen.py` creates a separate desktop object and starts Godot on it.
  The window is rendered by the real GPU but can never take focus, appear on screen or receive
  your input. (Launching Godot normally with a "no focus" window setting still took the
  foreground for about two seconds in testing — do not do that.)
* **Linux:** `xvfb-run` with a software Vulkan driver (`xvfb`, `mesa-vulkan-drivers`).

Contact sheets and JPEG conversion: `res://tools/dev/sheet.tscn` (headless).

## Benchmarks

```bash
tools/perf.sh [WxH] [mobile|forward_plus] [planet]            # GPU frame times, off-screen, v-sync off
"$GODOT" --headless --path . res://tools/dev/bench.tscn      # CPU: load time, dig timings, save time
```

`perf` runs six scenarios (surface, outpost, power shovel held down, eight 6.5 m blasts,
crystal cavern, three bots hauling 150 chunks) and prints average FPS, p95/p99/max frame time
and the renderer's CPU/GPU time for the main viewport. Results: `docs/TECHNICAL.md`.
Caveats: the window is on a desktop that is not being composited, so presentation is
unthrottled; a decorated 1440-high window is clamped to 1421 pixels (the tool prints the size).

## Economy simulation

```bash
"$GODOT" --headless --path . res://tools/dev/econ.tscn -- 100 balanced
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

## What was actually verified in the v0.2 pass

**Looked at (GPU renders, 1920×1080 unless noted, Mobile renderer, RTX 5070):** arrival view;
outpost from 12 m, Workshop, Depot; open surface in three places; fresh holes and a quarry;
stone tunnel with ore under the headlamp; crystal cavern; both planet Hearts; Glimmerock
surface, quarry, tunnel and outpost; all 11 tool tiers in first person at rest and in a studio
line-up bare and fully fitted; HUD; Workshop screen (three families), after a purchase;
Outfitter; journal; destinations; pause/settings; discovery card; new-tool presentation; main
menu; HUD and shop at 3440×1440; Mobile vs Forward+ on three scenes; and **film strips**
(`docs/screenshots/motion/`) of the hand swing, power-shovel punch, tool switch, drill on fresh
ground, cannon shot with blast, and the new-purchase presentation. The strips led to three
fixes (a barely visible power punch, a presentation that filled the screen, a thick blast ring).

**Measured, not seen or heard:** frame times; dig, load and save timings; audio levels and
spectra; pacing (simulation).

**Not verified by anyone:** how motion *feels* at full speed (timing, weight, smoothness —
strips show poses, not rhythm); look sway and walk bob; bots flying; the menu planet turning; how any sound or the mix actually
sounds, including the new ambience and cave reverb; input feel; real play pacing; 4K (the UI
layout is resolution-independent for 16:9 and was checked at 1080p); gamepad; the Linux build.

## Writing a test

Add `tests/test_<letter>_<topic>.gd` extending `TestSuite`; every `test_*` method is discovered
and may `await`. Use `make_world()` / `free_world()` for a headless planet, `place_player()`,
`wait_until()` for anything that depends on asynchronous meshing, and the `forced_move`,
`forced_jump`, `forced_use` hooks on `Player` / `ToolController` to drive input.
