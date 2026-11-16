# Dependencies

## Voxel Tools (terrain engine)

| | |
|---|---|
| Project | Zylann's Voxel Tools for Godot — <https://github.com/Zylann/godot_voxel> |
| Docs | <https://voxel-tools.readthedocs.io/> |
| Version | **1.7** (reports `(1, 7, 0)`, edition `GDExtension`) |
| Release | <https://github.com/Zylann/godot_voxel/releases/tag/v1.7x> |
| Download | `GodotVoxelExtension.zip` — SHA-256 `600737572a5e25541ba6f503e842a3717ba19afafa5474510a6ceff995a1d2d8` |
| Licence | MIT (`addons/zylann.voxel/LICENSE.md`) |
| Engine compatibility | declares `compatibility_minimum = "4.4.1"`; verified here on **Godot 4.7.2 stable** |

### What is vendored

`addons/zylann.voxel/` contains the upstream `voxel.gdextension`, its icons and licence, and
**only** these binaries from the release zip (≈42 MB):

```
bin/libvoxel.linux.editor.x86_64.so
bin/libvoxel.linux.template_release.x86_64.so
bin/libvoxel.windows.editor.x86_64.dll
bin/libvoxel.windows.template_release.x86_64.dll
```

The macOS, iOS, Android and Linux-arm64 binaries were left out to keep the repository small.
`voxel.gdextension` is unmodified, so to add a platform just copy the matching file from the
release zip into `addons/zylann.voxel/bin/`.

### Verifying the install

```bash
godot --headless --path . --import
godot --headless --path . res://tests/run_tests.tscn
```

The suite exercises the extension for real: it compiles a generator graph, streams and meshes a
planet, edits voxels, waits for collision meshes to rebuild, saves through `VoxelStreamSQLite`
and reloads. If the extension failed to load, `Planet` could not even be parsed and every world
test would fail.

### Updating

1. Download the new `GodotVoxelExtension.zip` from the releases page.
2. Replace `addons/zylann.voxel/` (keep the four binaries listed above, or more).
3. Run the test suite. API notes worth re-checking after an update:
   * `VoxelGraphFunction.NODE_SDF_SPHERE` takes `radius` as input port 3 (not a parameter).
   * `NODE_DISTANCE_3D` ignores constant default inputs in 1.7 (we carve cavities with a
     translated `SdfSphere` + `SdfSmoothSubtract` instead — see `Geology.build_generator`).
   * Mesh blocks are separate instances offset from the terrain origin, so shaders must use
     world space (`MODEL_MATRIX * VERTEX`), not raw `VERTEX`.

### Why Voxel Tools

Requirements were: true 3D editable volume (tunnels, caves, overhangs — so no heightmaps),
smooth meshing, collision that follows edits, persistence, and good performance without
writing a voxel engine. Voxel Tools provides all of that natively (C++, multithreaded
generation/meshing, Transvoxel, SQLite streaming) and has an MIT licence. A hand-written
GDScript marching-cubes terrain was considered and rejected: meshing a 288³-voxel planet and
re-meshing edits in script would be orders of magnitude slower.

`VoxelTerrain` (fixed LOD) is used instead of `VoxelLodTerrain` because these planets are small
(≈50 m radius at 0.5 m voxels): the whole planet stays loaded, edits are simpler and there are
no LOD seams. Much bigger planets should switch to `VoxelLodTerrain`; `Planet` is the only class
that would change.

## Fonts

Fredoka (SIL OFL 1.1), static TTF instances from Google Fonts, in `assets/fonts/`.

## Tooling (optional, development only)

* Python 3 + numpy — `tools/gen_audio.py` (regenerates `assets/audio/`); ffmpeg for OGG music.
* Xvfb + Mesa (`libgl1-mesa-dri`, `mesa-vulkan-drivers`) — `tools/shots.sh` renders screenshots
  on a machine without a GPU.
