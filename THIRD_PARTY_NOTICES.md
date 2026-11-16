# Third-party notices

| Component | Version | Where | Licence |
|---|---|---|---|
| [Voxel Tools for Godot](https://github.com/Zylann/godot_voxel) by Marc "Zylann" Gilleron | 1.7 (GDExtension build, tag `v1.7x`) | `addons/zylann.voxel/` | MIT — full text in `addons/zylann.voxel/LICENSE.md` |
| [Fredoka](https://github.com/hafontia/Fredoka-One) typeface, The Fredoka Project Authors | Google Fonts v17 static instances (Regular, SemiBold, Bold) | `assets/fonts/` | SIL Open Font License 1.1 — full text in `assets/fonts/OFL.txt` |
| [Godot Engine](https://godotengine.org) | 4.7.2 stable | not vendored (required to run) | MIT |

Voxel Tools itself bundles third-party code (FastNoiseLite, SQLite, LZ4, meshoptimizer and
others); their licences are reproduced in `addons/zylann.voxel/LICENSE.md`.

## Original content

* **Audio** — every sound effect and music loop in `assets/audio/` is synthesised from scratch
  by `tools/gen_audio.py` in this repository. No samples or third-party recordings are used.
* **Models** — all 3D models (tools, rocket, shops, props, robots, artifacts) are generated at
  runtime by code in `src/` using `src/core/mesh_kit.gd`. There are no imported model files.
* **Icons** — drawn in code (`src/ui/ui_icon.gd`).

No assets were copied or extracted from Moon Sweepers or any other commercial game.
