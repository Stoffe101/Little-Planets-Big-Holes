# v0.3 screenshots

Rendered from the running game by `tools/shots.sh` (Mobile renderer, RTX 5070, off-screen
desktop; 1920×1080 unless noted). Every image below was looked at after rendering; notes say what
was checked. Older sets: `../` (v0.2) and `../before` (v0.1).

| # | Subject | Files | What was checked |
|---|---|---|---|
| 1 | Larger planetary horizon | `01_horizon.jpg`, `16b_glimmerock_horizon.jpg` | From the shoulder of Mount Pip: long view, props thinning into the distance, outpost small far below; horizon no longer far below eye level |
| 2 | Starting outpost | `02_outpost.jpg`, `02b_arrival.jpg` | Seedpod lander, drum stations, round plinths, lanterns; arrival view faces the outpost |
| 3 | Normal surface traversal | `03_traverse.jpg` | Mid-stride on the meadow, Mount Pip on the horizon, gloved hand |
| 4 | Distant landmarks | `04_landmark.jpg` | Mount Pip from ~180 m (the standing stones on its shoulder are too small to make out at this size) |
| 5 | Regional variation | `05_region_whisperwood.jpg`, `05b_region_stonebrake.jpg`, `05c_region_pockmark.jpg` | Grove vs bare stony ridge vs cratered flats with patchy cover. (Stonebrake first rendered broken - see below) |
| 6 | Surface excavation | `06_surface_excavation.jpg` | Fresh hole with debris, HUD, contract line |
| 7 | Deep excavation | `07_deep_excavation.jpg` | Stepped quarry from the rim (about 20 m deep; reads shallower from this angle) |
| 8 | Cave entrance | `08_cave_entrance.jpg` | Natural cave mouth with its pair of cairns |
| 9 | Underground | `09_underground_tunnel.jpg`, `09b_underground_grotto.jpg`, `09c_planet_heart.jpg` | Tunnel with copper and gold in stone; the deep grotto (dark hardrock walls, gold and amethyst on the walls, entrance tunnel top left); the Heart |
| 10 | New equipment models | `10_equipment_lineup.jpg` | Every tier fully fitted, studio view (no hands in previews) |
| 11 | Tool upgrades | `11_tool_upgrades_first_person.jpg`, `19b_purchase.jpg` | Every tier in first person with gloves; new-equipment banner |
| 12 | Mining effects | `06_surface_excavation.jpg`, `motion/*.jpg` | Debris in material colours, blast ring |
| 13 | Scanner | `13_scanner.jpg` | Ore markers with names and distances |
| 14 | Map / navigation | `14_map.jpg`, `15b_survey_relay.jpg` | Survey map with regions, relays, waypoint, travel list; compass strip; relay mast with region banner |
| 15 | Machinery | `15_auto_borer.jpg` | Auto-Borer rig with drill string and spoil |
| 16 | Glimmerock | `16_glimmerock.jpg`, `16b_glimmerock_horizon.jpg`, `16c_glimmerock_quarry.jpg` | Same outpost on lilac dust, crystal fields, glass crust in the quarry |
| 17 | Main menu | `17_main_menu.jpg` | New UI palette (bronze surfaces, jade actions) |
| 18 | Workshop | `18_workshop.jpg`, `18b_workshop_screen.jpg`, `18c_outfitter_screen.jpg` | Drum workshop with curved counter and canopy; shop screens |
| – | HUD, ultrawide | `19_hud.jpg`, `20_ultrawide_3440.jpg` (3440×1421) | HUD layout; ultrawide adds space at the sides |

**Before / after (v0.2 left, v0.3 right):** `compare_outpost.jpg`, `compare_arrival.jpg`,
`compare_workshop.jpg`, `compare_shop.jpg`, `compare_mega_scooper.jpg`, `compare_quarry.jpg`,
`compare_glimmerock.jpg`, `compare_menu.jpg`.

**Motion strips** (`motion/`, eight frames each, game time slowed): hand swing, Thumper punch,
tool switch, drill, cannon shot, new-tool presentation. They show poses, not how the motion
feels at full speed.

## Problems found by looking

* **Stonebrake rendered with a giant tilted sheet and see-through ground**: the camera was
  *inside* the terrain, because the player had sunk into it (reproduced headless: up to 7.6 m
  below the surface while walking). Loaded voxels matched the generator and offline meshes were
  clean; the collider was present above the sunken player. The symptom was removed by lowering
  the regional roughness frequency (bumps every ~9 m with 2.6 m amplitude → ~25 m); the likely
  mechanism is the capsule controller embedding itself in those steep, short bumps, but that was
  not proven. Regression tests now walk the rough regions of both planets.
  `05b_region_stonebrake.jpg` is the render after the change.
* **The meadow rendered as bare dirt**: the regional ground-cover mask was inverted in the
  terrain shader. Fixed.
* **The workshop counter and canopy were underground** (prism orientation) and the screenshot
  cameras stood inside the new buildings. Fixed.
* The map was too zoomed out and noisy for a 400 m planet: zoom and smoother relief added.

## Originality

The equipment and architecture were checked against the "must not imitate" list in
`docs/ART_DIRECTION.md`: no white panels, no dark frames, no slatted vents, no orange stripes, no
boxy kiosks, no tall white rocket. Whether the result reads as original and appealing is a human
judgement and has not been made by a person yet.
