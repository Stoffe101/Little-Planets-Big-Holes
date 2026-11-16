class_name Planet
extends Node3D
## A large spherical, fully excavatable planet built on Voxel Tools (VoxelLodTerrain + Transvoxel).
##
## Streaming: the terrain is an octree of LODs centred on the planet. A single VoxelViewer
## follows the player (`attach_viewer`); full-resolution voxels (LOD0, editable, collidable)
## exist within ~70 m of it, coarser LODs cover the rest of the planet down to a few blocks for
## the far side. Only voxel blocks that were edited are stored (SQLite stream with key cache);
## everything else is regenerated from the seed on demand. See docs/TECHNICAL.md.
##
## The planet always sits at the world origin with an identity transform, so planet-local
## metres == world metres. Voxel coordinates are world / voxel_size.
##
## Queries outside the loaded area fall back to the analytic original surface (`geology`), so
## code like bots and props can reason about far-away ground without forcing it to load.

signal loaded()

const TERRAIN_SHADER := preload("res://shaders/terrain.gdshader")
const COLLISION_LAYER := 1
const LOD0_DISTANCE := 96.0          ## voxels; measured editable radius ~70 m (docs/TECHNICAL.md)
const SPAWN_READY_RADIUS := 20.0     ## metres around the spawn that must be meshed before play

var config: Dictionary
var geology: Geology
var terrain: VoxelLodTerrain
var voxel_tool: VoxelTool
var viewer: VoxelViewer
var material: ShaderMaterial
var stream: VoxelStreamSQLite
var is_loaded := false
var half_extent_voxels := 128
var octree_size := 256
var lod_count := 4
var _load_started_ms := 0
var load_time_ms := 0
var _ready_cache: Dictionary = {}    ## Vector3i (16-voxel block) -> bool, cleared every physics frame
var _ready_cache_frame := -1


func setup(planet_config: Dictionary, terrain_db_path := "", seed_offset := 0) -> void:
	config = planet_config
	name = "Planet_" + str(config.get("id", "x"))
	geology = Geology.new(config, seed_offset)
	geology.bake()
	_build_terrain(terrain_db_path)


func _build_terrain(db_path: String) -> void:
	terrain = VoxelLodTerrain.new()
	terrain.name = "Terrain"
	terrain.generator = geology.build_generator()
	var mesher := VoxelMesherTransvoxel.new()
	terrain.mesher = mesher
	if db_path != "":
		stream = VoxelStreamSQLite.new()
		stream.database_path = db_path
		# Without the key cache every block load queries SQLite; with it, queues drain ~6x faster.
		stream.set_key_cache_enabled(true)
		terrain.stream = stream
	# Octree that contains the whole planet: block 16 voxels * 2^(lods-1) >= planet diameter.
	var extent_m := geology.max_surface_radius() + 8.0
	half_extent_voxels = int(ceil(extent_m * geology.inv_voxel / 16.0)) * 16
	octree_size = 16
	lod_count = 1
	while octree_size < half_extent_voxels * 2:
		octree_size *= 2
		lod_count += 1
	terrain.lod_count = lod_count
	terrain.voxel_bounds = AABB(Vector3.ONE * -octree_size / 2, Vector3.ONE * octree_size)
	terrain.lod_distance = LOD0_DISTANCE
	terrain.view_distance = octree_size
	terrain.mesh_block_size = 16
	terrain.streaming_system = 1          # Clipbox: measured 5-50x faster than Octree here
	terrain.generate_collisions = true
	terrain.collision_lod_count = 1
	terrain.collision_layer = COLLISION_LAYER
	terrain.collision_mask = 0
	terrain.lod_fade_duration = 0.0
	terrain.scale = Vector3.ONE * geology.voxel_size

	material = ShaderMaterial.new()
	material.shader = TERRAIN_SHADER
	geology.apply_to_material(material)
	terrain.material = material
	add_child(terrain)

	viewer = VoxelViewer.new()
	viewer.name = "Viewer"
	viewer.view_distance = octree_size
	viewer.requires_collisions = true
	viewer.requires_visuals = true
	add_child(viewer)
	viewer.position = geology.spawn_position()      # the planet sits at the origin, unrotated

	voxel_tool = terrain.get_voxel_tool()
	voxel_tool.channel = VoxelBuffer.CHANNEL_SDF
	_load_started_ms = Time.get_ticks_msec()
	set_process(true)


## Moves the terrain viewer under `node` (normally the player) so streaming follows it.
func attach_viewer(node: Node3D) -> void:
	if viewer.get_parent() != null:
		viewer.get_parent().remove_child(viewer)
	node.add_child(viewer)
	viewer.position = Vector3.ZERO


func _process(_dt: float) -> void:
	if is_loaded:
		set_process(false)
		return
	if is_area_ready(geology.spawn_position(), SPAWN_READY_RADIUS):
		is_loaded = true
		load_time_ms = Time.get_ticks_msec() - _load_started_ms
		loaded.emit()
		set_process(false)


## True when the area around `center` is editable at full resolution AND its collision is live.
## Use this before teleporting a player or editing far away.
##
## Under Clipbox streaming a LOD0 block's collider is only switched on once every coarser block
## above it in the LOD octree has been meshed too (Voxel Tools activates LODs top-down), so
## "meshed" alone is not enough: on a fresh start the first colliders appear ~2 s after the
## spawn area is meshed. So: voxels editable, LOD0 meshing finished (`is_area_meshed` also
## accounts for blocks without any surface, which never get a mesh block), and every LOD0 mesh
## block that does exist in the area reports an active collider.
func is_area_ready(center: Vector3, radius_m: float) -> bool:
	var c := center * geology.inv_voxel
	var r := radius_m * geology.inv_voxel
	var box := AABB(c - Vector3.ONE * r, Vector3.ONE * r * 2.0).intersection(terrain.voxel_bounds)
	if not voxel_tool.is_area_editable(box) or not terrain.is_area_meshed(box, 0):
		return false
	var lo := Vector3i((box.position / 16.0).floor())
	var hi := Vector3i((box.end / 16.0).floor())
	for x in range(lo.x, hi.x + 1):
		for y in range(lo.y, hi.y + 1):
			for z in range(lo.z, hi.z + 1):
				var info: Dictionary = terrain.debug_get_mesh_block_info(Vector3(x, y, z), 0)
				if info.has("transition_mask") and not bool(info.get("collision_active", false)):
					return false
	return true


## Rough loading progress in [0, 1] for the loading screen.
func load_progress() -> float:
	if is_loaded:
		return 1.0
	var spawn := geology.spawn_position()
	var ok := 0
	var radii := [4.0, 8.0, 12.0, 16.0, SPAWN_READY_RADIUS]
	for r: float in radii:
		if is_area_ready(spawn, r):
			ok += 1
	return float(ok) / float(radii.size()) * 0.95


# ------------------------------------------------------------------ queries

func to_voxel(p: Vector3) -> Vector3:
	return p * geology.inv_voxel


## True if the voxel data at `p` is in memory (full resolution).
func is_loaded_at(p: Vector3) -> bool:
	var f := Engine.get_physics_frames()
	if f != _ready_cache_frame:
		_ready_cache.clear()
		_ready_cache_frame = f
	var v := (p * geology.inv_voxel).floor()
	var key := Vector3i(v / 16.0)
	if _ready_cache.has(key):
		return _ready_cache[key]
	var ok := voxel_tool.is_area_editable(AABB(v, Vector3.ONE))
	_ready_cache[key] = ok
	return ok


## Signed distance (in voxels, clamped) at a world position. < 0 means solid ground.
## Where the terrain is not loaded at full resolution this is the distance to the ORIGINAL
## surface (no caves, no edits) - good enough for steering and placement far away.
func sdf_at(p: Vector3) -> float:
	if is_loaded_at(p):
		return voxel_tool.get_voxel_f((p * geology.inv_voxel).floor())
	var r := p.length()
	if r < 0.001:
		return -100.0
	return clampf((r - geology.surface_radius(p / r)) * geology.inv_voxel, -100.0, 100.0)


func is_solid(p: Vector3) -> bool:
	return sdf_at(p) < 0.0


func up_at(p: Vector3) -> Vector3:
	var l := p.length()
	return p / l if l > 0.001 else Vector3.UP


func altitude(p: Vector3) -> float:
	return -geology.depth_at(p)


## Gravity vector at a position. Fades out inside the core chamber so the heart floats you gently.
func gravity_at(p: Vector3) -> Vector3:
	var r := p.length()
	if r < 0.01:
		return Vector3.ZERO
	var g := float(config.get("gravity", 17.0))
	var fade := smoothstep(geology.core_radius * 0.55, geology.core_radius * 1.25, r)
	return -(p / r) * g * fade


func material_at(p: Vector3) -> int:
	return geology.material_at(p)


## Finds the ground position below/above a direction by marching the real (edited) SDF.
## Digging only removes material, so the original surface is an upper bound for solid ground:
## the march starts just above it (or at `from_radius` when given).
func ground_point(dir: Vector3, from_radius := -1.0) -> Vector3:
	# start above both the baked map and the exact surface (the map can under-read sharp relief)
	var r := from_radius if from_radius > 0.0 else maxf(geology.surface_radius(dir), geology.surface_radius_exact(dir)) + 2.0
	var step := geology.voxel_size * 0.5
	var prev := r
	while r > geology.core_radius:
		if is_solid(dir * r):
			# refine between prev (air) and r (solid)
			var a := prev
			var b := r
			for i in 5:
				var m := (a + b) * 0.5
				if is_solid(dir * m):
					b = m
				else:
					a = m
			return dir * a
		prev = r
		r -= step
	return dir * geology.core_radius


# ------------------------------------------------------------------ persistence

## Asks Voxel Tools to write every modified block to the SQLite stream.
## Returns a VoxelSaveCompletionTracker (or null when the planet has no stream).
func save_terrain() -> Variant:
	if terrain == null or stream == null:
		return null
	return terrain.save_modified_blocks()


## Blocks until pending terrain saves are flushed to disk (used on quit / planet change).
func save_terrain_blocking(timeout_ms := 8000) -> bool:
	var tracker: Variant = save_terrain()
	if tracker == null:
		return true
	var t0 := Time.get_ticks_msec()
	while not tracker.is_complete():
		if Time.get_ticks_msec() - t0 > timeout_ms:
			return false
		OS.delay_msec(4)
	stream.flush()
	return not tracker.is_aborted()


func set_scan_pulse(origin: Vector3, pulse_radius: float, strength: float) -> void:
	material.set_shader_parameter("scan_origin", origin)
	material.set_shader_parameter("scan_radius", pulse_radius)
	material.set_shader_parameter("scan_strength", strength)
