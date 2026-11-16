class_name Planet
extends Node3D
## A spherical, fully excavatable planet built on Voxel Tools (VoxelTerrain + Transvoxel).
##
## The planet always sits at the world origin with an identity transform, so planet-local
## metres == world metres. Voxel coordinates are world / voxel_size.

signal loaded()

const TERRAIN_SHADER := preload("res://shaders/terrain.gdshader")
const COLLISION_LAYER := 1

var config: Dictionary
var geology: Geology
var terrain: VoxelTerrain
var voxel_tool: VoxelTool
var viewer: VoxelViewer
var material: ShaderMaterial
var stream: VoxelStreamSQLite
var is_loaded := false
var half_extent_voxels := 128
var _load_started_ms := 0
var load_time_ms := 0


func setup(planet_config: Dictionary, terrain_db_path := "", seed_offset := 0) -> void:
	config = planet_config
	name = "Planet_" + str(config.get("id", "x"))
	geology = Geology.new(config, seed_offset)
	geology.bake()
	_build_terrain(terrain_db_path)


func _build_terrain(db_path: String) -> void:
	terrain = VoxelTerrain.new()
	terrain.name = "Terrain"
	terrain.generator = geology.build_generator()
	var mesher := VoxelMesherTransvoxel.new()
	terrain.mesher = mesher
	if db_path != "":
		stream = VoxelStreamSQLite.new()
		stream.database_path = db_path
		terrain.stream = stream
	var extent_m := geology.max_surface_radius() + 6.0
	half_extent_voxels = int(ceil(extent_m * geology.inv_voxel / 16.0)) * 16
	var h := half_extent_voxels
	terrain.bounds = AABB(Vector3(-h, -h, -h), Vector3(2 * h, 2 * h, 2 * h))
	terrain.max_view_distance = 4 * h
	terrain.mesh_block_size = 16
	terrain.generate_collisions = true
	terrain.collision_layer = COLLISION_LAYER
	terrain.collision_mask = 0
	terrain.scale = Vector3.ONE * geology.voxel_size

	material = ShaderMaterial.new()
	material.shader = TERRAIN_SHADER
	geology.apply_to_material(material)
	terrain.material_override = material
	add_child(terrain)

	# One viewer at the planet centre keeps the whole (small) planet loaded, meshed and collidable.
	viewer = VoxelViewer.new()
	viewer.name = "Viewer"
	viewer.view_distance = 3 * h
	viewer.requires_collisions = true
	viewer.requires_visuals = true
	add_child(viewer)

	voxel_tool = terrain.get_voxel_tool()
	voxel_tool.channel = VoxelBuffer.CHANNEL_SDF
	_load_started_ms = Time.get_ticks_msec()
	set_process(true)


func _process(_dt: float) -> void:
	if is_loaded:
		set_process(false)
		return
	if _check_loaded():
		is_loaded = true
		load_time_ms = Time.get_ticks_msec() - _load_started_ms
		loaded.emit()
		set_process(false)


func _check_loaded() -> bool:
	if terrain == null:
		return false
	var h := half_extent_voxels
	if not voxel_tool.is_area_editable(AABB(Vector3(-h, -h, -h), Vector3(2 * h, 2 * h, 2 * h))):
		return false
	# Require the mesh (and therefore collision) around the landing site before letting the player in.
	var spawn_v := geology.spawn_position() * geology.inv_voxel
	var box := AABB(spawn_v - Vector3(20, 20, 20), Vector3(40, 40, 40)).intersection(terrain.bounds)
	return terrain.is_area_meshed(box)


## Rough loading progress in [0, 1] for the loading screen.
func load_progress() -> float:
	if is_loaded:
		return 1.0
	var h := half_extent_voxels
	var steps := 4
	var ok := 0
	var size := float(2 * h) / float(steps)
	for ix in steps:
		for iy in steps:
			for iz in steps:
				var o := Vector3(-h + ix * size, -h + iy * size, -h + iz * size)
				if voxel_tool.is_area_editable(AABB(o, Vector3(size, size, size))):
					ok += 1
	return float(ok) / float(steps * steps * steps) * 0.95


# ------------------------------------------------------------------ queries

func to_voxel(p: Vector3) -> Vector3:
	return p * geology.inv_voxel


## Signed distance (in voxels, clamped) at a world position. < 0 means solid ground.
func sdf_at(p: Vector3) -> float:
	return voxel_tool.get_voxel_f((p * geology.inv_voxel).floor())


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
func ground_point(dir: Vector3, from_radius := -1.0) -> Vector3:
	var r := from_radius if from_radius > 0.0 else geology.max_surface_radius() + 2.0
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
