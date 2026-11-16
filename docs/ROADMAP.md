# Roadmap

## What the v0.2 pass delivered

A new visual identity (docs/ART_DIRECTION.md) applied to terrain, sky, lighting, props, the
outpost, all tools, discoveries, effects and the whole interface; smoother, class-specific
tool animation and purchase presentation; a simulated and rebalanced economy
(docs/BALANCE.md); a level-normalised audio mix with cave acoustics and ambience; Windows
export presets and a verified build; GPU benchmarks; an off-desktop render harness; nine new
regression tests. Details and evidence: docs/TESTING.md, docs/TECHNICAL.md.

## Known limitations

**Not verified by a person**

* **Nobody has played or listened to this build.** Stills and slowed film strips of the tool
  animations were rendered on a real GPU and reviewed; real-time feel, input and all audio
  (including the new ambience beds and cave reverb) are unreviewed. Expect to adjust animation amounts and the mix.
* **Pacing is modelled, not playtested**, and only on Pipseed. Glimmerock's economy and the
  late game are scaled by rule, not measured.
* 4K was not rendered (the UI is resolution-independent at 16:9; 3440×1440 was checked).
* The Linux export preset is untested; CI covers headless tests on Linux only.

**Visual**

* The **Mega Scooper** bucket is the weakest tool model: its proportions read as a wedge.
  The power-shovel heads are small in first person; their bite is better communicated by the
  hole than by the tool.
* Tool models show no hands or arms.
* Open lawns are deliberately plain; at close range the grass is a shaded surface plus sparse
  blades, not dense geometry.
* Crystal formations are simple prisms; the cavern composition is seeded, not hand-placed.
* The typeface comes from the system (Bahnschrift on Windows). Other systems get their own
  sans-serif, so text metrics differ slightly. Shipping a bundled DIN-style font (for example
  Barlow or Inter, both OFL) would fix that.
* Label3D lettering on curved hulls can clip.

**Design / implementation gaps**

* Loose chunks on the ground and bot cargo in flight are not saved; you arrive at the outpost.
* One save slot. No key-rebinding UI (actions are registered in `Settings.ACTIONS`).
* No gamepad support. No localisation.
* Helper bots hover and cannot reach chunks inside sealed tunnels (they give up after ~14 s).
* Dug-up props are re-derived from "is the ground still there" on reload.
* Surface crystals moved in v0.2 (they are now seeded per item); crystals harvested in an
  older save reappear once.
* Terrain materials are a function of position, so material cannot be *added* (no building).
* Ambience is two synthesised noise beds; there are no positional environment sounds.
* The music tracks were not regenerated (no ffmpeg on the development machine).

## Recommended next pass: "hands on"

The game now looks the part; the next pass should be driven by a person playing it.

1. **Play the first 30 minutes several times** with the F3 overlay, fix what motion and sound
   reveal: swing weight, drill push, recoil, purchase inspect length, particle timing, the mix.
   Replace any sound that grates; add positional ambience (wind in grass, cave drips).
2. **Check the pacing against the model** (docs/BALANCE.md) and tune the JSON; then model and
   tune Glimmerock.
3. **First-person hands** and a second modelling pass on the Mega Scooper and power-shovel
   heads; denser grass near the camera.
4. **Mid-game variety on Pipseed**: deposits that need a specific attachment, a second vault,
   discoveries with more mechanical value, a reason to use the cannon and vacuum together.
5. **Quality of life**: key rebinding, multiple save slots, gamepad, a bundled font,
   photo mode.
6. **Machines** (the fantasy's end-game): a rideable digger using `dig_capsule`, a placeable
   auto-drill, a conveyor from pit to Depot; robots that dig.
7. **More planets** once the two existing ones are fun for an hour each.
8. **Co-op**, following the notes in docs/TECHNICAL.md.
