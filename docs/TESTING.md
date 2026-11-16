# Testing

## Running

```bash
godot --headless --path . --import                              # after cloning / adding class_names
godot --headless --path . res://tests/run_tests.tscn            # everything (~1 minute)
godot --headless --path . res://tests/run_tests.tscn -- world   # only suites whose filename contains "world"
tools/check.sh                                                  # compile every script, print errors
```

The runner prints `[PASS]/[FAIL]` per test and exits with code 1 on any failure (CI uses this,
see `.github/workflows/tests.yml`). Tests redirect all saves to `user://test_sandbox/`, so they
never touch a real save.

## What is covered (63 tests)

| Suite | Checks |
|---|---|
| `test_a_data` | JSON databases load; every material/discovery/planet/gear reference resolves; every material can be dug by some purchasable tool |
| `test_b_state` | capacity, exact sell value, multipliers, tool tiers, mods, gear, lock reasons, objectives, discoveries, planet unlock + fare, serialisation, garbage-tolerant loading |
| `test_c_save` | round trip, backup rotation, recovery from a corrupted main file, truncated/tampered saves rejected, v1 migration, delete |
| `test_d_geology` | same seed → same planet, different seed → different, flat landing pad, harder with depth, starter shovel can dig the surface, ore abundance matches config, octahedral mapping, generator graph agrees with the CPU shape |
| `test_e_world` | spawn on ground; gravity/orientation at six points around the planet; walking follows curvature; jump; zero-g core; dig removes voxels **and collision follows**; yields; blocked by hard layers; selective dig; **walkable tunnel into a hillside**; pickups, full backpack; shovel through the real tool controller; pad protection; selling on the pad; crystal formation; scanner; cannon crater; helper bot hauling and selling; artifact, cavern and heart discoveries; 400-dig stress + task-queue drain |
| `test_f_persistence` | dig a tunnel + chamber, save, unload, reload: same SDF values, player can stand in it, progress restored; control slot proves the tunnel is not there by default |
| `test_g_planets` | Glimmerock loads from data, lower gravity, own materials and hardness |
| `test_h_main` | real `main.tscn`: menu → new game → play → shop → menu → continue with the purchase intact |

## What automated tests cannot tell you

They run headless: **nothing about how the game looks, sounds or feels is verified by them.**
Frame rate, particle looks, audio quality and input feel need a person at a real PC.

## Screenshot harness (visual checks without a GPU)

```bash
tools/shots.sh <scenario> <output_prefix> [planet] [WxH]
# scenarios (tools/dev/shots.gd): spawn, dig, base, ui, tools, tour, surface, menu
tools/shots.sh tour /tmp/tour pipseed 1280x720
```

Needs `xvfb` and a software Vulkan driver (`mesa-vulkan-drivers`). It renders with the project
renderer through llvmpipe at well under 1 fps — fine for stills, useless for judging smoothness.

## Benchmark

```bash
godot --headless --path . res://tools/dev/bench.tscn
```

Prints planet load time, voxel memory, dig timings by radius, edit→collision latency and save
time. Results from the development VM are recorded in `docs/TECHNICAL.md`.

## Writing a test

Add `tests/test_<letter>_<topic>.gd` extending `TestSuite`; every `test_*` method is discovered
and may `await`. Use `make_world()` / `free_world()` for a headless planet, `place_player()`,
`wait_until()` for anything that depends on asynchronous meshing, and the `forced_move`,
`forced_jump`, `forced_use` hooks on `Player` / `ToolController` to drive input.
