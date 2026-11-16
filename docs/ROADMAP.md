# Roadmap

## Known limitations

**Not verified**

* No human has played this build. Everything was exercised by headless tests and by scripted
  still screenshots rendered on a software rasteriser. Frame rate, input feel, animation timing
  and difficulty pacing are untested on real hardware.
* Audio was synthesised and checked numerically (levels, no clipping) but never listened to.
  Expect to rebalance volumes and probably replace some sounds.
* Economy numbers are reasoned estimates, not playtested. All of them live in `data/*.json`.
* The Forward+ renderer could not be validated (see `docs/TECHNICAL.md` → Rendering).
* Windows: binaries for Windows x86_64 are vendored and nothing in the project is
  platform-specific, but the project has only been run on Linux.

**Design / implementation gaps**

* Loose chunks on the ground and bot cargo in flight are not saved; you respawn at the rocket.
* One save slot.
* Helper bots hover and cannot reach chunks inside sealed tunnels (they give up after ~14 s).
* Dug-up props are not individually saved; on reload they are re-derived from "is the ground
  still there" — props on untouched ground reappear, props over holes do not.
* Terrain materials are a function of position, so material cannot be *added* (no building,
  no dirt dumping) without storing a material channel.
* Key rebinding has no UI (actions are registered in `Settings.ACTIONS`).
* No gamepad support. No localisation.
* Exports: `data/*.json` must be added to the export preset's include filter
  (non-resource files are skipped by default). No export preset is committed.
* Software rendering shows visible steps on thin ore silhouettes at 0.5 m voxel resolution
  when viewed from a few centimetres.

## Next priorities

1. **Play it on a real PC** and fix what that shows: feel of the swing, drill and cannon,
   audio mix, pacing of the first 15 minutes, any Forward+ / Windows issue.
2. **Economy pass** with real session data; consider an in-game "credits per minute" readout.
3. **Mid-game variety on Pipseed**: more formation types, a second vault, timed "gem rush"
   events, deposits that need specific attachments.
4. **Vehicles & big machines** (the fantasy's end-game): a rideable digger using
   `dig_capsule`, a placeable auto-drill, conveyor from pit to Sell-o-Matic.
5. **Robots that dig** (reuse `DigSystem` commands) and a bot upgrade tree.
6. **More planets**: hollow world with an inner surface, bouncy planet, mechanical planet.
   Each needs only a JSON file plus any new mechanic.
7. **Orbital headquarters** as the hub between planets (museum for artifacts, hangar).
8. **Co-op** following the notes in `docs/TECHNICAL.md`.
9. Quality of life: multiple save slots, rebinding UI, gamepad, photo mode, export presets.
