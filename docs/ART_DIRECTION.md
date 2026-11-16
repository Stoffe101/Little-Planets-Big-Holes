# Art direction

*Little Planets, Big Holes* is a **clean, stylised 3D simulation**: a small survey outpost on a
small quiet world, and one person with increasingly serious excavation equipment. It should
look deliberately designed, friendly and calm — never candy, never gritty.

This document is the rulebook. If a new model, colour or screen does not fit it, change the
asset, not the rules (or change the rules here first, on purpose).

## 1. Design philosophy

1. **Restraint first.** Most of the frame is neutral: muted ground, off-white machines, a calm
   sky. That is what lets the few accents mean something.
2. **Function explains form.** Every object should look like it does a job: vents where a motor
   would get hot, a handle where a hand goes, legs where it stands.
3. **Light does the work.** Plain physically based shading under one sun and a soft sky. No toon
   ramps, no outlines, no rim glow, no blanket bloom.
4. **Simple is not empty.** Flat faces get bevels that catch the light; ground gets fine relief
   and strata; silhouettes are composed of a few clear masses.
5. **The dig is the star.** Nothing on screen may make a fresh hole harder to read.

## 2. Reference

The reference for *level of polish and restraint* is **Moon Sweepers** (DragDrop Games):
<https://store.steampowered.com/app/5335510/Moon_Sweepers/>. The official store screenshots
were studied in a browser; nothing was downloaded, copied or traced, and no asset, logo,
character or layout of that game is reproduced here.

What those screenshots do, and what we take from them:

| Observation in the reference | Principle we adopt |
|---|---|
| The whole environment is one near-neutral family (grey regolith, dark sky). | Common terrain stays within one desaturated family per planet. |
| Buildings and vehicles are off-white painted panels on dark bases, with louvred vents, panel seams and thin belt lines. | Our machines: off-white hull, graphite frames/vents, one belt line. |
| One accent hue (orange) appears only on trim, bristles and markings; blue only as glazing. | One signal colour for "ours / interactive", one for energy and screens. |
| Fine ground detail is relief (small craters, pebbles), not colour patches. | Surface detail is a procedural **normal**, plus sparse real props. |
| A single hard sun gives long, crisp shadows; shaded sides stay readable. | Low mid-morning sun, sky-driven ambient, soft-edged shadows. |
| Emission is reserved for screens and one holographic prop. | Emission only for status lights, screens, exotic minerals and the Heart. |
| Machinery has believable proportions and visible mechanisms. | Tools and stations show their working parts. |

What we deliberately do **differently**, so the game has its own identity: living, green and
stone worlds instead of a dead moon; hexagonal pads and a lander instead of a hangar complex;
amber + teal instead of orange + blue glass; first-person tools as the hero assets; real
volumetric holes with visible geology as the main spectacle.

## 3. Shape language

* **Manufactured things** are boxes and turned (lathed) forms with small, consistent bevels —
  `MeshKit.hbox`, `prism`, `lathe`, `tube`, `louvre`, `spiral`. Bevel size 1–2 cm on tools,
  3–10 cm on buildings. No blobby "inflated" shapes on anything man-made.
* **Natural things** are faceted and irregular — `MeshKit.rock` (jittered, flat shaded),
  `crystal`, thin `leaf` blades. Foliage masses are low and wide, never spherical lollipops.
* **Hexagons** are the outpost's ground motif (landing pad, station pads, bot dock, vault dais).
* Silhouette before detail: each asset should read from 20 m as two or three masses.

## 4. Colour hierarchy

All model colours live in **`src/core/palette.gd` (`Pal`)**; UI colours in `UiTheme`; terrain
and sky colours in the planet JSON. No hex codes in model code.

| Level | Share of a typical frame | Colours | Used for |
|---|---|---|---|
| Ground & sky | ~75 % | planet palette: muted greens / cool stone, soft blue to space | terrain, sky, rocks, vegetation |
| Equipment neutrals | ~20 % | `HULL`, `HULL_SHADE`, `GRAPHITE`, `CHARCOAL`, `STEEL`, `RUBBER`, `CONCRETE` | tools, stations, lander, bots |
| Signal | < 4 % | `AMBER` | belt lines, grips and triggers, pad markings, primary UI action |
| Energy / information | < 1 % | `TEAL` | status lights, screens, scanner, energy parts on top tiers |
| Value | rare | material colours (copper, gold, amethyst, starglass…) | ore in the rock, loot, crystals |
| Alarm / confirm | rare | `RED`, `GREEN` | "too hard", loss / sell pad edge, gain |

Rules:

* Common materials are desaturated; **saturation rises with value**. A gold seam must be the
  most colourful thing in a tunnel.
* Do not give an object its own accent colour. If it needs an accent it is `AMBER`.
* **Emission budget:** bulk terrain ≤ 0.12, ore ≤ 0.05 (ore reads through metallic gloss and
  flecks, not glow), crystals ≈ 0.2, exotics ≈ 0.5. Lights on machines are small. The planet
  Heart is the one object allowed to be bright.
* Glow post-processing is thresholded so that only the sun disc, status lights and exotic
  minerals bloom.

## 5. Materials

`shaders/prop.gdshader` is plain PBR driven by per-vertex data written by `MeshKit`
(colour, roughness, metallic, emission). Finishes, set before adding parts:

| Call | Roughness / metal | Use |
|---|---|---|
| `paint()` | 0.48 / 0 | painted panels (satin) |
| `matte()` | 0.86 / 0 | stone, wood, cloth, foliage |
| `bare()` | 0.34 / 0.62 | machined steel |
| `cast()` | 0.58 / 0.6 | cast or worn metal, dark housings |
| `rubber()` | 0.93 / 0 | grips, hoses, tyres |
| `gloss()` | 0.10 / 0 | glass, lenses, crystals |

Terrain (`shaders/terrain.gdshader`) decides *what* a fragment is exactly as gameplay does,
then renders it with: natural base colour, a fine procedural relief normal that fades with
distance, sediment tone bands and thin bedding lines on cut walls only, a darker damp band
under the turf, crisp-edged ore bodies with a dark contact line and brighter flecks, faceted
normals for crystalline ore, and ambient occlusion that deepens with depth below the original
surface so a hole always reads as a hole.

## 6. Lighting

* One sun at ~40° elevation (34° on Glimmerock) that follows the player around the planet;
  four-split soft shadows. Long shadows give small props and holes their form.
* Ambient comes from the sky shader itself (75 %) plus a little flat colour, so shaded faces
  are cooler and never dead. The sky's below-horizon colour used for lighting is the ground
  colour, not the sky behind the planet.
* AgX tonemapping, exposure 1.0, slight contrast. Colours are authored in sRGB and converted
  in the shader, so palette values mean what they say.
* Underground the sky's contribution fades to ~30 %, a light fog adds depth, the headlamp
  comes on (wide, soft) and each cavern has one key light placed high and off-centre so it has
  a lit side and a shaded side. Ore gloss and crystal facets answer the headlamp — light helps
  you find things.

## 7. Sky and atmosphere

A thin atmosphere over open space: horizon haze → clear mid blue → deep space with a few stars
at the zenith. The gradient is measured from the planet's real limb (on a 48 m world the
horizon sits well below eye level). Small sun disc with a tight halo. One neighbouring world
and a small moon hang in the sky, shown at a pleasant phase and tinted by the air in front of
them. Glimmerock is nearly airless: dark sky, full star field, a faint nebula band.

## 8. Environment

* **Density follows meaning.** Ground-cover tufts thin out on open lawns and thicken in damp
  zones; ferns gather in meadows; trees stand in a few groves; boulders are scattered sparsely.
* **Landmarks are placed on purpose:** a ring of standing stones (basalt columns on
  Glimmerock) on each mountain's shoulder, and a pair of cairns at every natural cave mouth so
  entrances can be recognised and found again.
* Vegetation stays in the ground's colour family. The only flower-like accent on Pipseed is a
  small muted bud on one fern variant.
* Never fill a surface just because it is empty. Open ground is where the player digs.

## 9. Tools

Tools are the hero assets; the player looks at them for the whole game.

* **Read from behind, above and the left** (that is the first-person view), so detail goes on
  top and on the −X side. They are drawn with a fixed 62° field of view, independent of the
  game FOV setting.
* **Each tier adds construction, not paint.** Shovels: hand scoop → forged spade → pneumatic
  breaker with a reciprocating head → hydraulic bucket with rams and an accumulator. Drills:
  single twist bit → planetary three-bit head with a carry handle → shoulder-braced boring
  head. Vacuums gain a cyclone separator and turbines. Cannons gain heat sinks, coils and vanes.
* **Every attachment bolts something on:** teeth and a carbide strip, a trench keel,
  counterweight collars or pressure canisters, intercooler blocks, a shaft collar, carbide
  studs, nozzle collars, chamber bands, an auto-loader rail. A test asserts that each mod level
  adds geometry.
* Livery: off-white housing, graphite caps, one amber band, rubber where a hand goes, amber
  trigger. Teal light = stored energy, used only from the powered tiers up.
* The starter scoop is the exception: wood, cloth tape, rust, a chipped edge. It should look
  cheap and still be appealing.
* **Animation:** hand tools are carried across the body and swung; powered tools are shouldered
  straight ahead and their *mechanism* moves (head, bit, barrel). Secondary motion (sway, bob,
  landing dip) is smoothed and small. A new purchase is held up and turned over once.

## 10. Industrial architecture

The base is a compact survey outpost: the lander on a hexagonal pad, the Workshop (service
window, steel counter, flat canopy, lit turntable showing the next tool), the Outfitter (locker
wall, display case), the Depot (hopper, status screen, chevron-marked sell pad) and the bot
dock, each on its own pad. Shared rules: off-white module on a dark plinth, one amber belt
line, graphite louvres, printed lettering without outlines, slim pole lamps with warm light.
The outpost **grows with the player**: cargo crates per backpack level, a solar array with the
first powered tool, a survey dish with the scanner, a lit dock with helper bots, a pennant when
the Heart is found.

## 11. UI

An instrument panel, not a toy box (`src/ui/ui_theme.gd`):

* Dark slate surfaces, hairline borders, 6–10 px radii, a short soft shadow. No thick outlines.
* Typeface: a DIN-style grotesque from the system (Bahnschrift on Windows; Inter / Roboto /
  Noto Sans / DejaVu elsewhere, engine default as last resort). Small letter-spaced capitals
  for section labels, regular weight for body, bold only for names and numbers.
* Colour: amber = the action / the selection; teal = information; green / red = gain / loss.
* Flat buttons; one primary (amber) per view.
* HUD: small chips in the corners, the world in the middle. Text over the world gets a thin
  dark edge and a soft drop shadow instead of a heavy outline.
* Layout is anchored and width-capped, so 16:9 at any resolution is identical and ultrawide
  only adds space in the middle (checked at 3440×1440).
* Feedback is short and quiet: fades and small slides, never bounces.

## 12. Particles and VFX

* Debris is small faceted chunks **in the colour of the material that was dug**, with a
  low-alpha dust puff. Sparks are few, small and warm; ore adds a handful in its own colour.
* Strong effects are reserved for strong events: a cannon blast, a shattered formation, the
  Heart. Selling and purchases use a short flash and a number, not confetti.
* Shock rings are thin lines. Scanner markers are small diamonds with a name and a distance.

## 13. Planet individuality

| | Pipseed | Glimmerock |
|---|---|---|
| Ground | sage and moss greens over warm soil and clay | cool lilac-grey dust over teal glass crust |
| Sky | soft daytime blue to space | near-black, stars, nebula band |
| Light | warm sun, 40° | cool white sun, 34°, lower ambient |
| Life | tufts, ferns, shrubs, flat-topped trees | pale frost-lichen rosettes only |
| Landmarks | standing stones, cairns | basalt columns, cairns |
| Value colours | copper, iron red, gold, amethyst | moonsilver, aquamarine, rose quartz, void opal |
| Heart | a glowing seed in a ribbed husk | a burst of long crystal prisms |

Both share the same outpost, tools, UI and lighting model, so they are clearly one game.

## 14. Consistency checklist

Before adding or changing a visual:

- [ ] Colours come from `Pal` / the planet palette / `UiTheme`.
- [ ] Manufactured → hard-surface primitives with a finish set; natural → faceted.
- [ ] Any accent is `AMBER`; any light is small; emission is within the budget above.
- [ ] It reads as a few clear masses from 20 m and has a believable function.
- [ ] A purchase changes the model, not only a number.
- [ ] You rendered it (`tools/shots.sh`) and **looked at the image** before describing it.
