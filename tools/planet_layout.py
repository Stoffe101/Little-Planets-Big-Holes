#!/usr/bin/env python3
"""Lays out the generation-2 planets in human units and writes their geography into
data/planets/<id>.json (only the keys listed in GEOGRAPHY; palettes, props, ores' materials and
everything else in the files are left as they are).

Places are given as (distance along the surface in metres, bearing in degrees) from the landing
site, which is the planet's +Y pole; bearing 0 points along +X, 90 along +Z. Run:

    python tools/planet_layout.py

then re-run the tests (they check the layout) and the economy simulator.
"""
import json
import math
import os

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")


def at(radius, metres, bearing_deg):
    """Unit direction `metres` along the surface from the +Y pole, at `bearing_deg`."""
    t = metres / radius
    b = math.radians(bearing_deg)
    return [round(math.sin(t) * math.cos(b), 5), round(math.cos(t), 5), round(math.sin(t) * math.sin(b), 5)]


def ang(radius, metres):
    return round(metres / radius, 5)


# ----------------------------------------------------------------------------------- Pipseed
def pipseed():
    R = 400.0
    A = lambda m, b: at(R, m, b)
    W = lambda m: ang(R, m)
    return {
        "radius": R,
        "generation": 2,
        "terrain": {
            "hill_amp": 7.0, "hill_freq": 3.0,
            "detail_amp": 1.6, "detail_freq": 14.0, "rough_freq": 16.0,
            "features": [
                {"type": "dome", "name": "Mount Pip", "dir": A(230, 20), "height": 52.0, "width": W(95)},
                {"type": "dome", "name": "Pip's Shoulder", "dir": A(300, 5), "height": 26.0, "width": W(70)},
                {"type": "dome", "name": "Copperfold basin", "dir": A(150, 125), "height": -9.0, "width": W(80)},
                {"type": "ridge", "name": "Stonebrake Ridge", "dir": A(210, 230), "dir2": A(380, 265), "height": 20.0, "width": W(16), "taper": W(25)},
                {"type": "plateau", "name": "The Table", "dir": A(300, 310), "height": 16.0, "radius": W(34), "edge": W(7)},
                {"type": "crater", "name": "Pockmark", "dir": A(470, 175), "radius": W(28), "depth": 13.0, "rim": 4.0},
                {"type": "crater", "name": "The Old Workings", "dir": A(120, 300), "radius": W(15), "depth": 7.0, "rim": 1.8},
                {"type": "dome", "name": "Low Hollow", "dir": A(850, 60), "height": -14.0, "width": W(120)},
                {"type": "dome", "name": "Far Peak", "dir": A(1050, 250), "height": 44.0, "width": W(110)},
            ],
            "crater_fields": [{"dir": A(470, 175), "radius": W(110), "count": 9, "min": W(5), "max": W(13), "seed": 3, "depth_ratio": 0.24}],
            "landing": {"dir": [0.0, 1.0, 0.0], "flat_radius": W(17), "blend": W(14), "height": 0.6},
        },
        "regions": [
            {"id": "homestead", "name": "Homestead Meadow", "dir": [0.0, 1.0, 0.0], "radius": W(60), "blend": W(30), "props": {"tree": 0.3, "boulder": 0.6}, "cover": 1.0,
             "desc": "Soft meadow around the lander. Good topsoil, a little copper."},
            {"id": "copperfold", "name": "Copperfold Vale", "dir": A(150, 125), "radius": W(70), "blend": W(30), "strata_lift": 1.5, "props": {"fern": 1.6, "shrub": 1.4, "tree": 0.6}, "cover": 0.75,
             "grass": ["#9aa05a", "#8c9a5c"], "desc": "A clay valley. Copper and iron sit close to the surface here."},
            {"id": "stonebrake", "name": "Stonebrake Ridge", "dir": A(295, 248), "radius": W(90), "blend": W(35), "strata_lift": 7.0, "rough": 2.6, "props": {"tree": 0.1, "boulder": 2.6, "tuft": 0.4, "crystal": 2.0}, "cover": 0.3,
             "grass": ["#7f8a6c", "#6f7b66"], "desc": "Bare bluestone pushed up by the ridge. Sungold runs shallow."},
            {"id": "pockmark", "name": "Pockmark Flats", "dir": A(470, 175), "radius": W(120), "blend": W(40), "strata_lift": 3.0, "props": {"boulder": 1.8, "crystal": 2.5, "tree": 0.2, "pebble": 1.6}, "cover": 0.45,
             "grass": ["#a69f68", "#958f62"], "desc": "Old impacts broke the crust open. Deep crystals come up in the craters."},
            {"id": "whisperwood", "name": "Whisperwood", "dir": A(330, 70), "radius": W(85), "blend": W(35), "props": {"tree": 4.0, "fern": 2.5, "shrub": 1.6}, "cover": 1.0,
             "grass": ["#5f8a5c", "#567d5d"], "desc": "The only real grove on Pipseed. Quiet, damp, full of cave mouths."},
            {"id": "workings", "name": "The Old Workings", "dir": A(120, 300), "radius": W(32), "blend": W(16), "strata_lift": 2.5, "props": {"boulder": 2.0, "tree": 0.0, "pebble": 2.0}, "cover": 0.2,
             "grass": ["#8a8466", "#7d785e"], "desc": "Somebody dug here long before you. They left in a hurry."},
            {"id": "lowhollow", "name": "Low Hollow", "dir": A(850, 60), "radius": W(140), "blend": W(50), "strata_lift": 4.0, "props": {"crystal": 2.0, "fern": 1.4, "tree": 1.5}, "cover": 0.8,
             "grass": ["#6f8a6a", "#64806a"], "desc": "A wide basin on the far side. Amethyst country."},
        ],
        "layers": [
            {"material": "topsoil", "thickness": 3.0},
            {"material": "clay", "thickness": 7.0},
            {"material": "stone", "thickness": 14.0},
            {"material": "hardrock", "thickness": 36.0},
            {"material": "corestone", "thickness": 999.0},
        ],
        "ores": [
            {"material": "starglass", "min_depth": 60.0, "max_depth": 230.0, "abundance": 0.025, "blob": 2.2},
            {"material": "amethyst", "min_depth": 26.0, "max_depth": 120.0, "abundance": 0.035, "blob": 3.0, "region": "pockmark", "boost": 3.0},
            {"material": "gold", "min_depth": 12.0, "max_depth": 60.0, "abundance": 0.04, "blob": 2.6, "region": "stonebrake", "boost": 3.0},
            {"material": "iron", "min_depth": 4.0, "max_depth": 30.0, "abundance": 0.06, "blob": 3.4, "region": "copperfold", "boost": 2.5},
            {"material": "copper", "min_depth": 0.7, "max_depth": 14.0, "abundance": 0.07, "blob": 2.8, "region": "copperfold", "boost": 3.5},
        ],
        "caves": {"min_depth": 8.0, "max_depth": 110.0, "period": 30.0, "width": 0.075},
        "cavities": [
            {"id": "crystal_grotto", "dir": A(230, 20), "depth": 34.0, "radius": 9.0, "lobes": 5, "discovery": "crystal_grotto", "decor": "crystals", "entrance": True, "entrance_slope": 1.1, "entrance_radius": 2.2},
            {"id": "mushroom_hollow", "dir": A(330, 70), "depth": 9.0, "radius": 6.5, "lobes": 4, "discovery": "mushroom_hollow", "decor": "mushrooms", "entrance": True},
            {"id": "echo_cavern", "dir": A(470, 175), "depth": 24.0, "radius": 8.0, "lobes": 5, "decor": "crystals"},
            {"id": "old_workings", "dir": A(120, 300), "depth": 14.0, "radius": 7.0, "lobes": 4, "discovery": "old_workings", "decor": "workings", "entrance": True, "entrance_slope": 0.9, "entrance_radius": 2.4},
            {"id": "deep_vault", "dir": A(470, 175), "depth": 72.0, "radius": 7.0, "lobes": 3, "discovery": "deep_vault", "decor": "vault"},
            {"id": "low_geode", "dir": A(850, 60), "depth": 40.0, "radius": 10.0, "lobes": 6, "discovery": "low_geode", "decor": "crystals", "entrance": True, "entrance_slope": 1.2, "entrance_radius": 2.4},
        ],
        "artifacts": [
            {"id": "dormant_bot", "dir": A(32, 200), "depth": 3.6, "pocket": 1.7, "model": "robot"},
            {"id": "time_capsule", "dir": A(70, 40), "depth": 2.8, "pocket": 1.4, "model": "capsule"},
            {"id": "star_chart_a", "dir": A(330, 70), "depth": 9.0, "pocket": 0.0, "model": "chart", "in_cavity": "mushroom_hollow"},
            {"id": "fossil_drill", "dir": A(260, 245), "depth": 16.0, "pocket": 1.8, "model": "drillbit"},
            {"id": "star_chart_b", "dir": A(230, 20), "depth": 34.0, "pocket": 0.0, "model": "chart", "in_cavity": "crystal_grotto"},
            {"id": "giant_seed", "dir": A(300, 310), "depth": 9.0, "pocket": 1.9, "model": "seed"},
            {"id": "old_helmet", "dir": A(120, 300), "depth": 14.0, "pocket": 0.0, "model": "helmet", "in_cavity": "old_workings"},
            {"id": "vault_idol", "dir": A(470, 175), "depth": 72.0, "pocket": 0.0, "model": "idol", "in_cavity": "deep_vault"},
            {"id": "survey_core", "dir": A(560, 150), "depth": 5.0, "pocket": 1.6, "model": "probe"},
        ],
        "core": {"chamber_radius": 10.0},
        # prop densities per 1000 m^2 (PropField streams them in cells around the player)
        "prop_density": {"tuft": 240, "fern": 15, "shrub": 4, "tree": 1.4, "boulder": 2.8, "pebble": 9, "crystal": 1.2},
        # survey relays: travel points, one per outlying region, each a short walk from its sights
        "relays": [
            {"id": "copperfold", "name": "Copperfold Relay", "dir": A(135, 112)},
            {"id": "whisperwood", "name": "Whisperwood Relay", "dir": A(300, 58)},
            {"id": "stonebrake", "name": "Stonebrake Relay", "dir": A(255, 232)},
            {"id": "workings", "name": "Workings Relay", "dir": A(138, 306)},
            {"id": "pockmark", "name": "Pockmark Relay", "dir": A(440, 190)},
            {"id": "lowhollow", "name": "Low Hollow Relay", "dir": A(800, 75)},
        ],
    }


# ----------------------------------------------------------------------------------- Glimmerock
def glimmerock():
    R = 300.0
    A = lambda m, b: at(R, m, b)
    W = lambda m: ang(R, m)
    return {
        "radius": R,
        "generation": 2,
        "terrain": {
            "hill_amp": 5.0, "hill_freq": 3.6,
            "detail_amp": 2.2, "detail_freq": 18.0, "rough_freq": 18.0,
            "features": [
                {"type": "dome", "name": "The Needle", "dir": A(160, 40), "height": 46.0, "width": W(40)},
                {"type": "dome", "name": "Needle's Sister", "dir": A(190, 62), "height": 30.0, "width": W(32)},
                {"type": "dome", "name": "Splinter", "dir": A(140, 75), "height": 22.0, "width": W(24)},
                {"type": "crater", "name": "The Shattered Rim", "dir": A(260, 200), "radius": W(48), "depth": 20.0, "rim": 7.0},
                {"type": "dome", "name": "Silver Mare", "dir": A(150, 280), "height": -8.0, "width": W(85)},
                {"type": "ridge", "name": "Glass Spine", "dir": A(90, 120), "dir2": A(260, 140), "height": 16.0, "width": W(10), "taper": W(18)},
                {"type": "plateau", "name": "Bell Mesa", "dir": A(560, 330), "height": 18.0, "radius": W(40), "edge": W(6)},
            ],
            "crater_fields": [{"dir": A(150, 280), "radius": W(90), "count": 11, "min": W(4), "max": W(11), "seed": 7, "depth_ratio": 0.26}],
            "landing": {"dir": [0.0, 1.0, 0.0], "flat_radius": W(17), "blend": W(12), "height": 0.4},
        },
        "regions": [
            {"id": "flats", "name": "Lander Flats", "dir": [0.0, 1.0, 0.0], "radius": W(50), "blend": W(25), "props": {"boulder": 0.6}, "cover": 0.9,
             "desc": "Fine glimmer dust over glass crust."},
            {"id": "spires", "name": "The Spires", "dir": A(165, 55), "radius": W(70), "blend": W(30), "strata_lift": 5.0, "rough": 2.0, "props": {"crystal": 3.0, "boulder": 1.6, "shrub": 0.4}, "cover": 0.25,
             "grass": ["#8d93ab", "#7f86a0"], "desc": "Glass crust shoved up into needles. Tide crystal grows in the cracks."},
            {"id": "mare", "name": "Silver Mare", "dir": A(150, 280), "radius": W(95), "blend": W(35), "strata_lift": 1.0, "props": {"boulder": 0.5, "pebble": 1.6}, "cover": 0.7,
             "grass": ["#a7acc0", "#9aa0b6"], "desc": "A smooth, cratered plain. Moonsilver lies just beneath the dust."},
            {"id": "rim", "name": "The Shattered Rim", "dir": A(260, 200), "radius": W(70), "blend": W(30), "strata_lift": 9.0, "rough": 1.5, "props": {"crystal": 2.5, "boulder": 2.2}, "cover": 0.15,
             "grass": ["#7c8299", "#70768c"], "desc": "A giant impact that exposed geode rock. Blush quartz everywhere."},
            {"id": "bells", "name": "Bell Country", "dir": A(560, 330), "radius": W(130), "blend": W(40), "strata_lift": 2.0, "props": {"shrub": 1.6, "crystal": 1.5}, "cover": 0.6,
             "grass": ["#959ab2", "#868ca6"], "desc": "The far side. Hollow ground that rings when you walk on it."},
        ],
        "layers": [
            {"material": "glimdust", "thickness": 2.5},
            {"material": "glasscrust", "thickness": 9.0},
            {"material": "geoderock", "thickness": 30.0},
            {"material": "prismcore", "thickness": 999.0},
        ],
        "ores": [
            {"material": "voidopal", "min_depth": 40.0, "max_depth": 170.0, "abundance": 0.025, "blob": 2.2},
            {"material": "rosequartz", "min_depth": 14.0, "max_depth": 90.0, "abundance": 0.045, "blob": 3.0, "region": "rim", "boost": 3.0},
            {"material": "aquamarine", "min_depth": 4.0, "max_depth": 40.0, "abundance": 0.055, "blob": 3.2, "region": "spires", "boost": 3.0},
            {"material": "moonsilver", "min_depth": 0.6, "max_depth": 14.0, "abundance": 0.07, "blob": 2.6, "region": "mare", "boost": 3.0},
        ],
        "caves": {"min_depth": 6.0, "max_depth": 100.0, "period": 24.0, "width": 0.1},
        "cavities": [
            {"id": "grand_geode", "dir": A(160, 40), "depth": 30.0, "radius": 11.0, "lobes": 6, "discovery": "grand_geode", "decor": "crystals", "entrance": True, "entrance_slope": 1.1, "entrance_radius": 2.4},
            {"id": "bell_chamber", "dir": A(560, 330), "depth": 14.0, "radius": 7.0, "lobes": 4, "discovery": "bell_chamber", "decor": "crystals", "entrance": True},
            {"id": "geode_b", "dir": A(260, 200), "depth": 34.0, "radius": 8.0, "lobes": 5, "decor": "crystals"},
            {"id": "geode_c", "dir": A(150, 280), "depth": 24.0, "radius": 7.0, "lobes": 5, "decor": "crystals"},
            {"id": "geode_d", "dir": A(420, 120), "depth": 18.0, "radius": 6.0, "lobes": 4, "decor": "crystals"},
        ],
        "artifacts": [
            {"id": "echo_bell", "dir": A(560, 330), "depth": 14.0, "pocket": 0.0, "model": "bell", "in_cavity": "bell_chamber"},
            {"id": "prism_lens", "dir": A(160, 40), "depth": 30.0, "pocket": 0.0, "model": "lens", "in_cavity": "grand_geode"},
            {"id": "glass_bird", "dir": A(60, 150), "depth": 4.5, "pocket": 1.6, "model": "bird"},
        ],
        "core": {"chamber_radius": 9.0},
        "prop_density": {"tuft": 0, "fern": 7, "shrub": 0, "tree": 0, "boulder": 7.5, "pebble": 19, "crystal": 4.5},
        "relays": [
            {"id": "spires", "name": "Spires Relay", "dir": A(130, 65)},
            {"id": "mare", "name": "Mare Relay", "dir": A(150, 260)},
            {"id": "rim", "name": "Rim Relay", "dir": A(200, 190)},
            {"id": "bells", "name": "Bell Relay", "dir": A(520, 320)},
        ],
    }


GEOGRAPHY = ["radius", "generation", "terrain", "regions", "layers", "ores", "caves", "cavities", "artifacts", "relays"]


def write(pid, layout):
    path = os.path.join(ROOT, "data", "planets", pid + ".json")
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    for key in GEOGRAPHY:
        data[key] = layout[key]
    core = dict(data.get("core", {}))
    core.update(layout["core"])
    data["core"] = core
    props = dict(data.get("props", {}))
    props.update(layout["prop_density"])
    data["props"] = props
    # keep a stable, readable key order: identity first, geography, then look and content
    order = ["id", "name", "tagline", "order", "seed", "radius", "generation", "voxel_size", "gravity", "unlock", "unlock_hint", "travel_cost"]
    out = {k: data[k] for k in order if k in data}
    for k in data:
        if k not in out:
            out[k] = data[k]
    text = json.dumps(out, indent=2, ensure_ascii=False)
    # collapse short numeric arrays onto one line
    import re
    text = re.sub(r"\[\s+(-?[0-9.]+),\s+(-?[0-9.]+),\s+(-?[0-9.]+)\s+\]", r"[\1, \2, \3]", text)
    text = re.sub(r"\[\s+(\"[^\"]+\"),\s+(\"[^\"]+\")\s+\]", r"[\1, \2]", text)
    text = re.sub(r"\[\s+(\"[^\"]+\"),\s+(\"[^\"]+\"),\s+(\"[^\"]+\")\s+\]", r"[\1, \2, \3]", text)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(text + "\n")
    print("wrote", path)


if __name__ == "__main__":
    write("pipseed", pipseed())
    write("glimmerock", glimmerock())
