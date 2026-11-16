extends Node
## Prototype: a large planet on VoxelLodTerrain. Measures streaming and checks which VoxelTool
## operations work. Run headless: godot --headless --path . res://tools/dev/lodproto.tscn -- [radius]

var terrain: VoxelLodTerrain
var viewer: VoxelViewer
var geo: Geology
var vt: VoxelTool


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var radius := float(args[0]) if args.size() > 0 else 400.0
	var full := args.size() > 1 and args[1] == "full"
	var phase := args[2] if args.size() > 2 else "dig"
	var db := ProjectSettings.globalize_path("user://lodproto_terrain.sqlite")
	if phase == "dig" and FileAccess.file_exists(db):
		DirAccess.remove_absolute(db)
	var cfg: Dictionary = GameData.planet("pipseed").duplicate(true)
	cfg["radius"] = radius
	var t: Dictionary = cfg["terrain"]
	t["hill_amp"] = 14.0
	for m: Dictionary in t["mountains"]:
		m["height"] = float(m["height"]) * 5.0
	var t0 := Time.get_ticks_msec()
	geo = Geology.new(cfg, 0)
	geo.bake()
	print("geology bake ms ", Time.get_ticks_msec() - t0)
	terrain = VoxelLodTerrain.new()
	terrain.generator = geo.build_generator()
	terrain.mesher = VoxelMesherTransvoxel.new()
	var vox_r := int(ceil((geo.max_surface_radius() + 8.0) * geo.inv_voxel))
	var octree := 16
	var lods := 1
	while octree < vox_r * 2:
		octree *= 2
		lods += 1
	terrain.lod_count = lods
	terrain.voxel_bounds = AABB(Vector3.ONE * -octree / 2, Vector3.ONE * octree)
	terrain.lod_distance = 48.0
	terrain.view_distance = octree
	terrain.mesh_block_size = 16
	terrain.generate_collisions = true
	terrain.collision_lod_count = 1
	terrain.scale = Vector3.ONE * geo.voxel_size
	terrain.streaming_system = int(args[3]) if args.size() > 3 else 1
	terrain.lod_distance = float(args[4]) if args.size() > 4 else 48.0
	print("streaming_system ", terrain.streaming_system, " lod_distance ", terrain.lod_distance)
	terrain.full_load_mode_enabled = full
	var stream := VoxelStreamSQLite.new()
	stream.database_path = db
	if args.size() > 5 and args[5] == "cache":
		stream.set_key_cache_enabled(true)
	print("key cache ", stream.is_key_cache_enabled())
	terrain.stream = stream
	print("full_load_mode ", full, " phase ", phase)
	add_child(terrain)
	print("radius ", radius, " voxel radius ", vox_r, " octree ", octree, " lods ", lods)
	viewer = VoxelViewer.new()
	viewer.view_distance = octree
	viewer.requires_collisions = true
	add_child(viewer)
	var spawn := geo.spawn_position()
	viewer.global_position = spawn
	vt = terrain.get_voxel_tool()
	vt.channel = VoxelBuffer.CHANNEL_SDF
	t0 = Time.get_ticks_msec()
	var box := AABB(spawn * geo.inv_voxel - Vector3.ONE * 24, Vector3.ONE * 48)
	while not (vt.is_area_editable(box) and terrain.is_area_meshed(box, 0)):
		await get_tree().process_frame
		if Time.get_ticks_msec() - t0 > 60000:
			print("TIMEOUT waiting for spawn area")
			break
	print("spawn area editable+meshed after ms ", Time.get_ticks_msec() - t0)
	await _settle("initial")
	var c := spawn - spawn.normalized() * 1.0
	var bigc := spawn.normalized().rotated(Vector3(0, 0, 1), 30.0 / radius)
	bigc = bigc * (geo.surface_radius(bigc) - 2.0)
	if phase == "dig":
		vt.mode = VoxelTool.MODE_REMOVE
		vt.do_sphere(c * geo.inv_voxel, 3.0)
		vt.do_sphere(bigc * geo.inv_voxel, 16.0)
		print("dug: sdf small ", vt.get_voxel_f((c * geo.inv_voxel).floor()), " big ", vt.get_voxel_f((bigc * geo.inv_voxel).floor()))
		var far := spawn.normalized().rotated(Vector3(1, 0, 0), 0.6)
		far = far * geo.surface_radius(far)
		for dm in [10, 20, 30, 40, 50, 60, 70, 80]:
			var d2 := spawn.normalized().rotated(Vector3(1, 0, 0), float(dm) / radius)
			d2 = d2 * geo.surface_radius(d2)
			print("  editable at %d m: %s" % [dm, str(vt.is_area_editable(AABB(d2 * geo.inv_voxel - Vector3.ONE * 2, Vector3.ONE * 4)))])
		print("far editable? ", vt.is_area_editable(AABB(far * geo.inv_voxel, Vector3.ONE * 4)), " sdf there ", vt.get_voxel_f((far * geo.inv_voxel).floor()))
		for step in 4:
			var dir := spawn.normalized().rotated(Vector3(1, 0, 0.3).normalized(), float(step + 1) * 120.0 / radius)
			viewer.global_position = dir * geo.surface_radius(dir)
			var t1 := Time.get_ticks_msec()
			var box2 := AABB(viewer.global_position * geo.inv_voxel - Vector3.ONE * 16, Vector3.ONE * 32)
			while not (vt.is_area_editable(box2) and terrain.is_area_meshed(box2, 0)):
				await get_tree().process_frame
			print("jump %d ready after %d ms" % [step, Time.get_ticks_msec() - t1])
		await _settle("far away")
		print("from far: small hole editable? ", vt.is_area_editable(AABB(c * geo.inv_voxel - Vector3.ONE * 4, Vector3.ONE * 8)), " sdf ", vt.get_voxel_f((c * geo.inv_voxel).floor()))
		viewer.global_position = spawn
		var t2 := Time.get_ticks_msec()
		while not vt.is_area_editable(AABB(c * geo.inv_voxel - Vector3.ONE * 4, Vector3.ONE * 8)):
			await get_tree().process_frame
		print("back after ms ", Time.get_ticks_msec() - t2, " sdf small ", vt.get_voxel_f((c * geo.inv_voxel).floor()), " big ", vt.get_voxel_f((bigc * geo.inv_voxel).floor()))
		var tr := terrain.save_modified_blocks()
		var t3 := Time.get_ticks_msec()
		while tr != null and not tr.is_complete():
			OS.delay_msec(2)
		stream.flush()
		print("saved in ms ", Time.get_ticks_msec() - t3, " db bytes ", FileAccess.get_file_as_bytes(db).size())
	else:
		print("reload: sdf small ", vt.get_voxel_f((c * geo.inv_voxel).floor()), " big ", vt.get_voxel_f((bigc * geo.inv_voxel).floor()))
	var dump := "user://lodproto_dump.tscn"
	terrain.debug_dump_as_scene(dump, false)
	_inspect_custom(dump)
	get_tree().quit()


func _settle(label: String) -> void:
	var t0 := Time.get_ticks_msec()
	for i in 600:
		await get_tree().process_frame
		var tk: Dictionary = VoxelEngine.get_stats().get("tasks", {})
		if int(tk.get("streaming", 0)) + int(tk.get("generation", 0)) + int(tk.get("meshing", 0)) == 0 and i > 30:
			break
	print("[%s] queues drained after %d ms" % [label, Time.get_ticks_msec() - t0])
	var st: Dictionary = VoxelEngine.get_stats()
	var mem: Dictionary = st.get("memory_pools", {})
	print("[%s] data blocks %d mesh blocks %d voxel mem %.1f MB static mem %.0f MB tasks %s" % [label, terrain.debug_get_data_block_count(), terrain.debug_get_mesh_block_count(),
		float(mem.get("voxel_used", 0)) / 1048576.0, OS.get_static_memory_usage() / 1048576.0, str(st.get("tasks", {}))])
	print("   terrain stats ", terrain.get_statistics())


func _inspect_custom(path: String) -> void:
	var ps: PackedScene = load(path)
	if ps == null:
		print("no dump")
		return
	var root := ps.instantiate()
	var seen := {}
	var meshes := 0
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for ch in n.get_children():
			stack.append(ch)
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var m := (n as MeshInstance3D).mesh
			meshes += 1
			for s in m.get_surface_count():
				var arr := m.surface_get_arrays(s)
				var cu: Variant = arr[Mesh.ARRAY_CUSTOM0]
				if cu == null:
					continue
				var f := cu as PackedFloat32Array
				for i in range(3, f.size(), 4):
					var bits := PackedFloat32Array([f[i]]).to_byte_array().decode_s32(0)
					var key := "cell=%d vert=%d trans=%d" % [bits & 63, (bits >> 8) & 63, (bits >> 16) & 0xff]
					seen[key] = int(seen.get(key, 0)) + 1
	print("meshes in dump ", meshes, " distinct custom0 patterns ", seen.size())
	var keys := seen.keys()
	keys.sort_custom(func(a: String, b: String) -> bool: return int(seen[a]) > int(seen[b]))
	for k in keys.slice(0, 30):
		print("   ", k, " x", seen[k])
	var trans := {}
	for k: String in seen:
		trans[k.split("trans=")[1]] = true
	print("transition field values ", trans.keys())
	root.free()
