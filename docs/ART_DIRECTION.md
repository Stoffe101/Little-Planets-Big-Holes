# Art direction

*Little Planets, Big Holes* is a **clean, stylised 3D simulation**: a field-survey outpost on a
small, quiet world, and one person with increasingly serious excavation equipment. It should
look deliberately designed, warm and calm — never candy, never gritty.

This document is the rulebook. If a new model, colour or screen does not fit it, change the
asset, not the rules (or change the rules here first, on purpose).

**Since v0.3 the game has its own identity.** Earlier versions borrowed too much of one
reference game's look (see §2). This version keeps the *principles* we admired and replaces
every recognisable *design* with our own: enamelled field instruments instead of white
machinery, round forms instead of panelled boxes, bronze rings instead of dark frames,
perforated grilles instead of slatted vents, and jade instead of orange.

## 1. Design philosophy

1. **Restraint first.** Most of the frame is the planet: muted ground, calm sky. That is what
   lets the few accents mean something.
2. **Function explains form.** Every object looks like it does a job: a grille where a motor
   breathes, a dial where something is measured, a glove where a hand grips, legs where it stands.
3. **Light does the work.** Plain physically based shading under one sun and a soft sky. No toon
   ramps, no outlines, no rim glow, no blanket bloom.
4. **Simple is not empty.** Forms get bevels and rings that catch the light; ground gets fine
   relief and strata; silhouettes are a few clear masses.
5. **The dig is the star.** Nothing on screen may make a fresh hole harder to read.

## 2. Inspiration — and what we must not imitate

### Admired principles (keep)

Studied in pass 2: *Moon Sweepers* (DragDrop Games), from its public store screenshots only.
Nothing was ever downloaded, copied or traced. What it taught us, stated as general principles:

| Principle | How we apply it |
|---|---|
| A frame dominated by one calm terrain family | One desaturated ground family per planet; saturation rises with value. |
| Surface detail as relief, not colour noise | Procedural normal relief + sparse real props. |
| One low sun with long, readable shadows | Mid-morning sun that follows the player. |
| Emission reserved for screens and a hero object | Small status lights; the planet Heart is the one bright thing. |
| Machines with believable proportions and visible mechanisms | Every tool tier shows its working parts. |

### Designs we must not imitate (avoid)

These are recognisable traits of that game's equipment and architecture. **Do not use them**,
alone or in combination:

* Off-white / light-grey painted panels as the main machine colour.
* Dark graphite or black frames, bases and plinths around light bodies.
* Slatted louvre vents and rectangular panel-seam grids on boxes.
* Thin orange (or amber) belt lines and accent strips; orange-on-white livery.
* Boxy modular buildings, hangar complexes, rectangular kiosks with flat canopies.
* A tall, slender white rocket as the base centrepiece.
* Blue glazing as the only coloured element on a white machine.

`tests/test_k_identity.gd` guards the measurable parts of this (no near-white enamel, no
amber accent, warm frames, round station bodies, a squat lander). Whether the result *looks*
original is for a human to judge — see "Human evaluation" in the final report.

### Broader inspiration (ours)

* **Field and laboratory instruments**: theodolites and transits (enamel bodies, brass rings,
  levelling screws), pressure gauges, Geiger counters, sample canisters, bell jars.
* **Kilns, enamelware and ceramics**: fired terracotta, glazed cream, ribbed drums.
* **Mining heritage**: timber sets, narrow rails, storm lanterns (only in the Old Workings —
  never on our own kit).
* **Space-exploration hardware**: landing legs with dampers, gimbal rings, survey probes.
* **Geology**: copper and its verdigris (our accent is literally oxidised copper), strata, geodes.

## 3. Our shape language

* **Round, turned and ringed.** Stations are **drums** on stepped round plinths, with raised
  bronze **rib rings**, a glazed **label band** and a low **domed cap**. Lathed forms
  (`MeshKit.lathe`, `turned`, `torus`, `disc`) come first; boxes (`hbox`) are for internal
  structure, counters and blades.
* **Instruments, not appliances.** Round **dials** (bronze bezel, cream face, one needle),
  round **perforated grilles**, porthole read-outs, gimbal rings, tripod masts.
* **Exposed copper.** Fuel lines, conduits and coils are visible pipes, not hidden in panels.
* **Tripods and splayed legs** instead of plinths for anything that stands alone.
* **Natural things** stay faceted and irregular — `rock`, `crystal`, thin `leaf` blades.
* **Round** is the outpost's ground motif (pads, plinths, the landing ring, sell-pad arcs).
* Silhouette before detail: each asset reads from 20 m as two or three masses.

## 4. Colour hierarchy

All model colours live in **`src/core/palette.gd` (`Pal`)**; UI colours in `UiTheme`; terrain
and sky colours in the planet JSON. No hex codes in model code.

| Level | Share of frame | Colours | Used for |
|---|---|---|---|
| Ground & sky | ~75 % | planet palette | terrain, sky, rocks, vegetation |
| Equipment body | ~15 % | `ENAMEL` (kiln terracotta), `ENAMEL_SHADE` | drums, housings, the lander belly, bot shells |
| Equipment structure | ~6 % | `BRONZE`, `DEEP`, `STEEL`, `RUBBER`, `CONCRETE` | rings, legs, bases, working metal, grips, pads |
| Ceramic | ~2 % | `CREAM` | lander dome, dial faces, sign plates, label bands, insulators |
| Hardware | ~1 % | `COPPER`, `BRASS` | pipes, coils, tier-3 trim |
| Signal | < 1 % | `JADE` (verdigris) | handles, triggers, cuffs, hopper rim, pad markings, primary UI action |
| Energy / information | < 1 % | `ION` | status lights, screens, scanner, energy parts |
| Value | rare | material colours | ore in the rock, loot, crystals |
| Alarm / confirm | rare | `RED`, `GREEN` | "too hard", gain |

Rules:

* Common materials are desaturated; **saturation rises with value**. A gold seam must be the
  most colourful thing in a tunnel.
* Don't give an object its own accent colour. If it needs an accent it is `JADE`.
* Terracotta and jade are complementary; keep jade small so it stays a signal.
* **Emission budget:** bulk terrain ≤ 0.12, ore ≤ 0.05, crystals ≈ 0.2, exotics ≈ 0.5.
  Lights on machines are small. The planet Heart is the one object allowed to be bright.

## 5. Materials

`shaders/prop.gdshader` is plain PBR driven by per-vertex data written by `MeshKit`.
Finishes, set before adding parts:

| Call | Roughness / metal | Use |
|---|---|---|
| `paint()` | 0.48 / 0 | fired enamel (satin) |
| `matte()` | 0.86 / 0 | stone, wood, leather, canvas, foliage |
| `bare()` | 0.34 / 0.62 | machined steel, copper pipe |
| `cast()` | 0.58 / 0.6 | bronze rings, cast housings |
| `rubber()` | 0.93 / 0 | grips, hoses, feet |
| `gloss()` | 0.10 / 0 | glazed ceramic, glass, lenses, crystals |

Terrain (`shaders/terrain.gdshader`) decides *what* a fragment is exactly as gameplay does,
then renders it: base colour, fine relief that fades with distance, strata bands on cut walls
only, a damp band under the turf, crisp ore bodies with a dark contact line, faceted crystal
ore, and depth-darkened occlusion so a hole always reads as a hole. Regions recolour the turf
and thin it into patches where the region's `cover` is low.

## 6. Lighting

* One sun at ~40° (34° on Glimmerock) that follows the player; four-split soft shadows.
* Ambient comes from the sky shader (75 %) plus a little flat colour.
* AgX tonemapping, exposure 1.0, slight contrast. sRGB authoring, converted in the shader.
* Underground the sky contribution fades, light fog adds depth, the headlamp comes on and
  each cavern has one key light high and off-centre.

## 7. Sky and atmosphere

A thin atmosphere over open space: horizon haze → clear blue → space with a few stars. On
400 m worlds the horizon sits close to eye level again (it was far below it on the 48 m
planets), so the sky reads like a sky. One neighbouring world hangs in the sky. Glimmerock is
nearly airless: dark sky, full star field, a faint nebula band.

## 8. Environment

* **Regions** give every part of a planet its own character: turf colour and coverage, which
  props grow (Whisperwood has trees, Stonebrake bare boulders, the Spires crystals), how high
  the strata are pushed up, which ore is rich. Region names appear on the map and as you enter.
* **Landmarks are placed on purpose:** standing stones (basalt columns on Glimmerock) on each
  tall dome's shoulder; a pair of cairns at every natural cave mouth; craters and ridges are
  visible from far away because LOD terrain draws the whole planet.
* **Density follows meaning.** Props are streamed per region at densities per 1000 m².
* Never fill a surface just because it is empty. Open ground is where the player digs.

## 9. Our equipment (tools)

Tools are the hero assets; the player looks at them for the whole game.

* **Read from behind, above and the left**, drawn with a fixed 62° FOV.
* **Hands are part of the tool.** A leather work glove (`LEATHER`) closes around each grip,
  with a canvas cuff, a jade tab and the suit sleeve leading off-screen. Two-handed tools show
  both hands (shovels: shaft and grip; power shovels: pistol grip and side grip). Shop
  previews show the bare tool.
* **Each tier adds construction, not paint.** Shovels: hand scoop → forged spade → pneumatic
  breaker with a big blued-steel head on a reciprocating carrier → hydraulic **curved bucket**
  (an arc of slats between side plates, open to the front, toothed lip) on twin rams. Drills,
  vacuums and cannons follow the same rule.
* **Every attachment bolts something on** (asserted by a test).
* Livery: terracotta enamel housings held by bronze rib rings, round perforated vents, steel
  where it works, rubber where a hand goes, a jade trigger. Ion light = stored energy.
* The starter scoop is the exception: wood, cloth tape, rust, a chipped edge.
* **Animation:** hand tools are swung across the body; powered tools are shouldered and their
  *mechanism* moves. Secondary motion is small and smoothed.

## 10. Outpost architecture

The base is a field-survey camp on round stone plinths:

* **The lander "Seedpod"** — a squat terracotta pod with a glazed cream dome, two bronze girth
  rings, copper fuel lines, a porthole, an arched hatch with a ramp, two dials and a grille,
  four splayed legs with copper dampers, and a survey mast with a gimbal ring.
* **Workshop** — a tall drum with a curved steel counter wrapped around its front, a pegboard
  in the opening, a half-disc canopy on bronze arms and a lit turntable with the next tool.
* **Outfitter** — a drum flanked by two canister lockers, with a glass bell jar showing the pack.
* **Depot** — a squat drum under a funnel hopper with a jade rim, a copper chimney, a round
  porthole read-out and a round cream sign; the sell pad carries jade arcs pointing at it.
* **Bot dock** — a round dish with an ion ring and a tripod beacon mast.
* Lanterns hang from bronze crook posts; the site marker is a round cream plate on a tripod.
* The outpost **grows with the player**: sample canisters per backpack level, a solar array,
  a survey dish, a lit dock, a pennant when the Heart is found.

## 11. UI

A field notebook on an instrument panel (`src/ui/ui_theme.gd`):

* Warm dark bronze surfaces, hairline borders, 6–10 px radii. No thick outlines.
* Cream text; jade = the action / the selection; ion blue = information; gold = credits only;
  green / red = gain / loss.
* DIN-style typeface (Bahnschrift on Windows; Inter / Roboto / Noto / DejaVu elsewhere).
* HUD: small chips at the edges, a compass strip at the top, the world in the middle.
* Layout is anchored and width-capped: 16:9 at any resolution is identical and ultrawide only
  adds space in the middle (checked at 3440×1440).

## 12. Particles and VFX

* Debris is small faceted chunks in the colour of what was dug, plus a low-alpha dust puff.
* Strong effects only for strong events: a cannon blast, a shattered formation, the Heart.

## 13. Planet individuality

| | Pipseed (r = 400 m) | Glimmerock (r = 300 m) |
|---|---|---|
| Ground | sage and moss over warm soil and clay; regional turf tints | lilac-grey dust over teal glass crust |
| Regions | Homestead Meadow, Copperfold Vale, Stonebrake Ridge, Pockmark Flats, Whisperwood, the Old Workings, Low Hollow | Lander Flats, the Spires, Silver Mare, the Shattered Rim, Bell Country |
| Landforms | Mount Pip, Stonebrake ridge, The Table, Pockmark craters, Low Hollow basin, Far Peak | the Needle spires, Shattered Rim crater, Silver Mare, Glass Spine, Bell Mesa |
| Sky | soft daytime blue to space | near-black, stars, nebula band |
| Life | tufts, ferns, shrubs, flat-topped trees (a grove in Whisperwood) | pale frost-lichen only |
| Value colours | copper, iron red, gold, amethyst | moonsilver, aquamarine, rose quartz, void opal |
| Heart | a glowing seed in a ribbed husk | a burst of long crystal prisms |

## 14. Consistency checklist

- [ ] Colours come from `Pal` / the planet palette / `UiTheme`.
- [ ] Nothing from the "must not imitate" list in §2.
- [ ] Manufactured → turned and ringed forms with a finish set; natural → faceted.
- [ ] Any accent is `JADE`; any light is small; emission is within the budget.
- [ ] It reads as a few clear masses from 20 m and has a believable function.
- [ ] A purchase changes the model, not only a number.
- [ ] You rendered it (`tools/shots.sh`) and **looked at the image** before describing it.
