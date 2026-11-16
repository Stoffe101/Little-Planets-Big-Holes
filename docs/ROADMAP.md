# Roadmap

## What the v0.3 pass delivered ("Bigger worlds, original identity")

* **Planets 8× larger** (Pipseed 400 m, Glimmerock 300 m) on streamed LOD terrain with
  editable/collidable full resolution near the player, persistence for streamed blocks, and a
  safe v2 → v3 save migration (docs/TECHNICAL.md).
* **Comfortable traversal**: the world turns under 1 °/s while walking (was 6.7 °/s), a smoothed
  camera horizon and comfort settings, measured by tests.
* **Planet design**: landforms (mountains, ridges, plateaus, craters, basins), 7 + 5 named
  regions with their own look, props and rich ore, new caverns (the Old Workings, the Low
  Geode), a survey probe artifact.
* **An original visual identity** (docs/ART_DIRECTION.md): enamelled field instruments, round
  architecture, a Seedpod lander, gloved hands, a real Mega Scooper bucket, a new UI palette.
* **Big-world play**: compass, survey map with waypoints, survey relays with travel and recall,
  contracts, the Auto-Borer, bot work zones that unload at relays.
* Streaming-aware economy simulator and GPU benchmark, 100+ automated tests.

## What the v0.3.1 pass delivered ("Performance, stability, gameplay quality")

* **Profiled, not guessed** (new `tools/profile.sh`, `streamprobe`, `perf_compare.py`): most of
  v0.3's reported 5–8× FPS drop was the benchmark sharing the GPU with a game on the visible
  desktop - v0.2 measured under the same conditions runs no faster. The real costs were
  never-edited voxel blocks regenerated on the main thread (every edit and voxel query) and
  per-mesh-block work after long jumps.
* **Fixes:** cached generated blocks (digs 1.6–12 ms → 0.5–0.7 ms), 32-voxel mesh blocks
  (render CPU −40 %, the unload frame after a relay jump 100–140 ms → 35–40 ms), a 4 ms voxel
  main-thread budget, accurate (trilinear) ground queries, one system set up per frame at the
  end of loading.
* **Relay transit:** jumps and recall are covered by a transit card from their first frame;
  the player is held until the destination is collidable and lands beside the mast, on the
  ground, looking out (it used to arrive inside the mast's legs).
* **Stability suite** (block corners, tunnels across blocks, save/load cycles, repeated relay
  travel, fast traversal on both planets), readiness fallback that does not need Voxel Tools'
  debug query, cross-version save check.
* Economy re-run incl. Glimmerock; Auto-Borer model, tree variety, compass label overlap.

## Known limitations

**Not verified by a person**

* **Nobody has played this build.** Traversal comfort is *measured* (rotation rates, no snaps or
  roll) but not *felt*; docs/PLAYTEST.md lists what a human should check. No audio was heard.
* **Pacing is modelled** (docs/BALANCE.md), not playtested. The model says Glimmerock pays 4–8×
  Pipseed's late rate and its shop runs out within ~15 minutes of landing.
* Whether the new look reads as original and appealing is a human judgement; the identity
  tests only guard measurable rules.
* The Linux export preset is untested.

**Performance and streaming**

* **No uncontended frame-rate numbers exist for v0.3.x yet**: every GPU benchmark in passes 3
  and 3.1 ran while another application kept the GPU 92–96 % busy. Run
  `python tools/perf_compare.py --before <v0.3.0 checkout> --res 3440x1440` on an idle PC.
* Streaming still costs frame time: sprinting with jets, p99 ~15 ms and worst frames 20–27 ms
  on the shared GPU; behind the transit card the longest frame is ~55 ms (not shown).
* Render CPU is still about twice v0.2's (more terrain blocks and props on a bigger world);
  props are batched per cell and kind, not across cells.
* The readiness check prefers `VoxelLodTerrain.debug_get_mesh_block_info`; a physics-ray
  fallback takes over if it disappears, but it is a weaker check (five probes).
* Edits are possible ~60 m around the player in every direction (up to ~110 m along some);
  the Auto-Borer and bots pause or fall back to the analytic surface beyond that.
* The dig survey still samples stored voxels (biased towards "solid" on the planet's upper
  side); yields are balanced on it. Switch to interpolated sampling only together with a
  rebalance.

**Design / implementation gaps**

* **v0.1/v0.2 dig sites do not carry over** to the new planets (progress does; the old terrain
  files are kept on disk). Crystal and prop flags from old saves no longer correspond to items.
* No vehicle. Relay travel and recall cover long distances; a hover vehicle was not built
  because it could not be made polished in this pass.
* Contracts are three generated kinds; there is no contract board UI beyond the HUD line.
* The map's relief is rendered once per session on a worker thread (~1 s); it shows regions
  and named landforms but not your own excavations.
* Region and relay names exist only in English. No localisation, no gamepad, one save slot.
* The Auto-Borer only digs straight down; bots never dig.
* Music and sounds are unchanged from v0.2 (nothing new was recorded or synthesised).

## Recommended next pass: "play it"

1. **Human playtest** using docs/PLAYTEST.md: comfort, the first 30 minutes, getting lost (or
   not), relay travel, the borer, contracts. Tune JSON from what is found.
2. **Measure on an idle GPU** (`perf_compare.py`, three resolutions) and, if render CPU matters
   there, batch props across cells.
3. **Glimmerock pacing**: something to buy there (Glimmerock-tier upgrades or sinks), then
   re-run `econ.tscn ... glimmerock after=40`; regional contracts there.
4. A **hover vehicle** for the far side once traversal feels right on foot; then conveyors or a
   rail from a borer shaft to a relay.
5. Map overlay of your own excavations and found deposits; contract board at the Depot.
6. Quality of life: key rebinding, more save slots, gamepad, a bundled font.
7. Co-op, following docs/TECHNICAL.md.
