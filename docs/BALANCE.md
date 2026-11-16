# Balance and pacing

All numbers live in `data/*.json`. This document records **why** they are what they are and how
they were checked. Nothing here replaces a human playtest: the figures below come from a model.

## The simulator

```bash
godot --headless --path . res://tools/dev/econ.tscn -- [minutes] [balanced|rush] [planet]
```

`tools/dev/econ.gd` boots a real planet and lets a scripted player dig it through the real
`DigSystem` (so yields, hardness gates and ore distribution are the game's own), sell through
the real `GameState` and buy upgrades from a fixed priority list.

Assumptions (constants at the top of the script):

| Assumption | Value |
|---|---|
| Time per dig | tool cooldown × 1.2 (aiming, stepping) |
| Share of popped chunks actually collected | 92 % |
| Dig site | 20 m from the Depot; a pit that widens and deepens, new site when blocked or at 26 m |
| Trip to sell | walk there and back at 7 m/s × boots, plus climbing out (2 m of path per m of depth, 1.2 with jump jets), plus 6 s at the shops |
| Selling | whole backpack, every time it is full |
| Tool choice | the drill as soon as it is owned, otherwise the shovel; vacuum, cannon and bots are not modelled |
| Lucky Charm | rolled per dig with the game's own formula (`World.luck_roll_chance`) |
| Discoveries | none found (so no artifact rewards and nothing they unlock) |
| `balanced` policy | tools, backpack and a spread of gear/attachments in a sensible order; small purchases while saving |
| `rush` policy | tool tiers and backpack only |

The model player never hesitates, never gets lost and never stops to look at anything, so real
sessions will be **slower**; it also ignores artifacts and lucky gems, which make real sessions
**richer**. Treat the times as the fast end of plausible.

## What the first build's numbers did

Simulated with the original tables: the power shovel was bought at **4 min**, the drill at
**6 min**, the top shovel at **22 min** and nearly everything by **26 min**. Income went from
460 to 2,700 credits/min within ten minutes because dig volume grows with the cube of the bite
radius while prices only grew ~8× per step. Bulk rock made 54 % of all income, so finding ore
barely mattered, and each tier was in use for one to two minutes.

## Targets

| Moment | Target | Why |
|---|---|---|
| First sale | 1–2 min | see the whole loop immediately |
| Sturdy Spade | at the first sale | a ×3 jump in ground moved, clay and iron open up |
| Small conveniences (backpack, magnet, attachments) | every 1–2 min until ~8 min | always something affordable next |
| Thumper 3000 (first powered tool) | 8–12 min | the "it digs by itself" moment, early |
| Vacuum | soon after the Thumper | answers the mess a powered shovel makes |
| Burrow Drill | ~20 min | granite, amethyst, the deep |
| Boom Cannon | ~35 min | |
| Diamond Drill | ~1 h | |
| Mega Scooper | 1–1.5 h | |
| Time between sales | 50–150 s | regular, not constant, backtracking |
| Share of income from bulk soil/rock | under half | ore and crystals should be the reason to dig *there* |

## Result with the current tables (model, Pipseed)

| Purchase | balanced | rush |
|---|---|---|
| Sturdy Spade | 1.3 min | 1.3 min |
| Backpack 1 | 1.9 min | 1.9 min |
| Thumper 3000 | 11.0 min | 8.2 min |
| Slurp-o-Vac | 13.2 min | – |
| Burrow Drill | 18.4 min | 17.8 min |
| Boomer | 35.9 min | – |
| Diamond Drill | 58 min | 53.5 min |
| Mega Scooper | 73 min | – |

Income per minute (balanced): 90 → 220 → 800 in the first fifteen minutes, then roughly
600–1,400 during the Burrow Drill, 1,100–3,000 with the Diamond Drill. A sale every 50–75 s in
the first twenty minutes, every 150–300 s later. Ore and crystals are ~55 % of income.

## What was changed

* **Values per unit** are now small fractions for bulk (soil 0.5, clay 1, stone 1.4, granite
  2.5) and climb steeply with rarity (copper 5, iron 8, gold 18, amethyst 60, starglass 260).
  Sale lines are rounded to whole credits per material; the HUD's "worth" equals the payout.
* **Yields** of ore and crystal drop from 0.8 to 0.6 units/m³ (0.5 for exotics).
* **Backpack** 60 / 120 / 240 / 500 / 1,000 / 2,200 / 5,000 units, sized so that a well-kept
  backpack fills in about a minute of digging at every stage.
* **Prices** of mid and late items rise to follow income (drill 4,500, cannon 6,000, Diamond
  Drill 18,000, Mega Scooper 26,000, Mole Engine 150,000, Planet Cracker 200,000; Glimmerock's
  first-trip fuel 8,000). Early prices stay low.
* **Tutorial rewards** are a little larger so the first sale plus the first three objectives
  buy the spade; late objective and discovery rewards scale with late prices.
* **Lucky Charm.** With the old rule (chance scaling up to ×2 with bite volume, paying 1–2
  *amethyst*) a 260-credit charm would have out-earned the Thumper once gems were worth 60.
  The chance no longer grows beyond the listed percentage for big bites, and each planet names
  a modest `lucky_gem` (Pip Quartz, Moonsilver). Modelled share: ~10 % of all income with the
  charm bought at 7 min and upgraded at 27 min.
* Tool **stats were not changed**: the feel of each tool is exactly what it was.

`tests/test_i_overhaul.gd::test_balance_tables_are_sane` guards the invariants (rising costs,
every tier a real step in ground moved or in power, ore worth more than dirt, backpack steps).

## Not validated

* Any of this with a human at the controls.
* **Glimmerock.** Its values and its tools' late prices were scaled by the same rules but the
  simulator was only run on Pipseed, starting from a new game.
* The contribution of the vacuum, cannon, helper bots and discoveries.
* The very late game (Mole Engine, Planet Cracker, both Hearts).

When a playtest disagrees with the model, change the JSON, re-run the simulator to see what
moved, and update the tables above.

## Pass 3: big planets (model estimates, not playtests)

What changed for pacing: the planets are 8× larger; ores are **richer in their regions**
(Copperfold: copper ×3.5, iron ×2.5; Stonebrake: gold ×3; Pockmark: amethyst ×3); survey
relays make far regions reachable; contracts pay credits on top of sales; the Auto-Borer
(5,000 / 18,000 / 60,000 cr, unlocked by the Fossilised Drill Bit) digs on its own; prices and
tool stats are **unchanged**.

The simulator now moves the scripted player (the terrain viewer) to every dig site and waits
for the ground to load, and has a third policy:

| Policy | What it does |
|---|---|
| `balanced` | v0.2 behaviour: digs in a ring 20–60 m around the outpost |
| `explorer` | same purchases, but digs in the region whose boosted ore is worth most among those its current tool can break; walks there once (counted), brings the relay online, then sells by walking to the relay, jumping to the outpost (4 s per jump) and walking to the Depot, and back |

Pipseed, 60 simulated minutes (`econ.tscn -- 60 balanced|explorer pipseed`):

| | balanced | explorer |
|---|---|---|
| Thumper 3000 bought at | 10.2 min | 6.9 min |
| Burrow Drill | 16.7 min | 12.5 min |
| Boomer (cannon) | 35.0 min | 24.9 min |
| Diamond Drill | 56.6 min | 37.9 min |
| Mega Scooper | – | 48.6 min |
| Total earned in 60 min | 56,600 cr | 102,700 cr |
| Time spent travelling to sell | 4.2 min (7 %) | 7.2 min (12 %) |
| Regions worked | outpost ring | Copperfold from 0.3 min, Stonebrake from 7.5 min |
| Contracts completed | 0 | 2 (deliveries that happened along the way) |

Reading it:

* Exploring roughly **doubles** income over an hour in the model, mostly through gold in
  Stonebrake (40 % of the explorer's value). That is the intended pull outwards; whether it is
  *too* strong needs a person playing (the model never gets lost, never wastes a relay jump and
  walks straight to the richest region it can work).
* Travel costs ~12 % of the session with relays. Without relays the same trips would be
  ~250 m walks each way; relays are what make regional mining viable.
* Not modelled: the Auto-Borer, helper bots, contract bonuses beyond deliveries, artifacts,
  depth contracts, Glimmerock. Treat all times as the fast end of plausible.
* **Not rebalanced.** Prices and tool stats are v0.2's. The explorer's ~1.8× income is
  deliberate pull towards the regions but has not been tuned against play; if testers find the
  mid-game too fast, lower the regional `boost` values in `tools/planet_layout.py` first.
* Figures from the final terrain (after the roughness change in 714c1fd).
