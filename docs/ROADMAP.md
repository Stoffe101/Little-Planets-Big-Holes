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

## Known limitations

**Not verified by a person**

* **Nobody has played this build.** Traversal comfort is *measured* (rotation rates, no snaps or
  roll) but not *felt*; docs/PLAYTEST.md lists what a human should check. No audio was heard.
* **Pacing is modelled** (docs/BALANCE.md), not playtested; Glimmerock is not modelled.
* Whether the new look reads as original and appealing is a human judgement; the identity
  tests only guard measurable rules.
* The Linux export preset is untested.

**Performance and streaming**

* Frame rate is ~80–120 FPS on the development PC and **CPU-bound** (was GPU-bound at 500+ FPS
  on the tiny planets). Not yet profiled per system.
* Streaming hitches: 99th-percentile frame ~27 ms while sprinting; 90–120 ms spikes right after
  a 300 m relay jump (behind the travel flash).
* The terrain readiness check relies on `VoxelLodTerrain.debug_get_mesh_block_info`; if a future
  Voxel Tools version changes it, `Planet.is_area_ready` must be revisited.
* Edits are only possible within ~70 m of the player (Voxel Tools LOD0 range); the Auto-Borer
  and bots pause or fall back to the analytic surface beyond that.

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
2. **Profile the CPU frame** (Godot profiler + Voxel Tools stats) and cut the cost of prop
   streaming and static prop bodies; spread mesh/collider activation after long jumps.
3. **Glimmerock pacing** in the simulator; regional contracts there.
4. A **hover vehicle** for the far side once traversal feels right on foot; then conveyors or a
   rail from a borer shaft to a relay.
5. Map overlay of your own excavations and found deposits; contract board at the Depot.
6. Quality of life: key rebinding, more save slots, gamepad, a bundled font.
7. Co-op, following docs/TECHNICAL.md.
