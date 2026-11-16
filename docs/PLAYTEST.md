# Human playtest guide (v0.3)

Automated tests measure camera rotation, streaming and persistence; they cannot tell whether the
game *feels* right. These checks need a person at the keyboard. Each takes a few minutes; note
the time, what you did and what you felt. Run with v-sync on, the window focused, F3 for the
performance overlay.

Start with **New game** (it deletes the save in slot 1 — back up `%APPDATA%\Godot\app_userdata\
Little Planets, Big Holes\saves` first if you want to keep it).

## 1. Comfort (the main goal of this pass)

1. Walk in a straight line across the meadow for 30 s, then sprint for 30 s. Does the world
   feel like it is *rotating* under you, or like solid ground? Any sense of the horizon tilting?
2. Strafe in circles while turning the mouse. Any roll or wobble of the horizon?
3. Jump repeatedly while running; later buy the jetpack and fly 50 m. Any snaps on take-off or
   landing?
4. Settings → Comfort: set *Horizon smoothing* to 0 and to 1.0. Which feels better? Is 0.25
   (default) right?
5. Dig a tunnel and walk through it; climb out of a deep pit.
6. If anything causes discomfort: what were you doing, and does reducing view bob / camera
   shake / sprint widening help?

## 2. Scale and exploration

1. From the outpost, can you see landmarks worth walking to (Mount Pip, the ridge, trees)?
2. Walk to Copperfold Vale without the map. Did you get lost? Did the compass help?
3. Open the map (M). Is it understandable? Set a waypoint and follow the compass marker.
4. Bring a relay online, recall to the outpost, travel back. Since v0.3.1 the view cuts to a
   "Relay transit" card for ~1.5–2.5 s while the destination streams in, then fades in with you
   standing beside the mast looking out over the region. Is the card's length acceptable? Does
   the hard cut feel abrupt? Any hitch or pop-in *after* the fade? Do you know where you are?
5. Walk 300 m in one direction. Does terrain or vegetation visibly pop in? Any holes, seams or
   floating trees at LOD boundaries?

## 3. Digging and machines

1. Dig with each tool. Does the hand-and-glove viewmodel look right in motion (swing weight,
   power-shovel punch, the new Mega Scooper bucket)?
2. Dig a hole, walk 150 m away, come back. Is the hole still there? Quit and continue: still
   there?
3. Find the Fossilised Drill Bit, buy the Auto-Borer, press G away from the outpost. Watch it
   for a minute; walk away and back. Is it satisfying? Is the spoil easy to collect? (v0.3.1:
   braced legs, a wellhead drum, a turning crown and a spoil heap that grows every 2 m - does
   it now read as a working machine rather than a telescope on a tripod?)
4. With helper bots: press B in a region near a relay. Do the bots work there and unload at
   the relay?

## 4. Pacing

1. Play 30 minutes and note when you bought the Thumper, the drill and the cannon, and how many
   contracts you completed. Compare with docs/BALANCE.md (model: Thumper 7–10 min, drill
   13–17 min).
2. Did contracts give you useful goals, or feel like chores?
3. If you reach Glimmerock: the model says it pays 4–8× Pipseed's late rate and the shop runs
   out within ~15 minutes there. Does it? Is there still something to want?

## 5. Look and sound

1. Does the outpost and equipment read as its own design (terracotta enamel, bronze rings,
   cream ceramic, jade accents) — and *not* as a copy of another game?
2. Do Stonebrake, Whisperwood and Pockmark feel like different places? Does Whisperwood's grove
   still look like one tree copied (v0.3.1 added round-crowned and tiered trees)?
3. Listen: digging, the borer, relays, ambience. Anything grating or missing?

## 6. Old saves

If you have a v0.2 save: back it up, then *Continue*. You should keep credits, tools,
attachments, gear, inventory and discoveries; see a one-time "resurveyed" notice; and find
`progress.v2.json` and your old `terrain_pipseed.sqlite` untouched in the save folder.
