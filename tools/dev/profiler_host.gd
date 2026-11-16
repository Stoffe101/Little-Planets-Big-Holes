extends Node
## Dev tool: a minimal stand-in for the editor's remote debugger that records Godot's own
## profilers ("servers" = frame/process/physics time + per-server timings, "scripts" = per
## function self/total time) from a game started with `--remote-debug tcp://127.0.0.1:<port>`.
## Frames are grouped by the scenario labels the game sends with
## `EngineDebugger.send_message("perf:mark", [label])` (tools/dev/perf.gd does this).
## Run through tools/profile.sh. Prints a per-scenario breakdown and the top script functions.
##
##   <godot> --headless --path . res://tools/dev/profiler_host.tscn -- [port] [top_n]

var _server := TCPServer.new()
var _peer: StreamPeerTCP
var _buf := PackedByteArray()
var _sigs := {}  # id -> signature
var _label := "(startup)"
var _order: Array[String] = []
var _agg := {}  # label -> Dictionary
var _msg_counts := {}
var _top := 25
var _idle_since := 0
var _connected_once := false


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var port := int(args[0]) if args.size() > 0 else 6010
	_top = int(args[1]) if args.size() > 1 else 25
	var err := _server.listen(port, "127.0.0.1")
	print("profiler_host: listening on %d (%s)" % [port, error_string(err)])
	_idle_since = Time.get_ticks_msec()


func _process(_dt: float) -> void:
	if _peer == null:
		if _server.is_connection_available():
			_peer = _server.take_connection()
			_peer.set_no_delay(true)
			_connected_once = true
			print("profiler_host: game connected")
			# the editor enables these when its profiler is started
			_send("profiler:servers", [true, []])
			_send("profiler:visual", [true, []])
		elif Time.get_ticks_msec() - _idle_since > 180000:
			print("profiler_host: nobody connected, giving up")
			get_tree().quit(1)
		return
	_peer.poll()
	var st := _peer.get_status()
	if st != StreamPeerTCP.STATUS_CONNECTED:
		_finish()
		return
	var avail := _peer.get_available_bytes()
	if avail > 0:
		var got: Array = _peer.get_data(avail)
		if got[0] == OK:
			_buf.append_array(got[1])
	while _buf.size() >= 4:
		var n := _buf.decode_u32(0)
		if _buf.size() < 4 + n:
			break
		var msg: Variant = bytes_to_var(_buf.slice(4, 4 + n))
		_buf = _buf.slice(4 + n)
		if msg is Array:
			_handle(msg)


func _send(cmd: String, data: Array) -> void:
	var bytes := var_to_bytes([cmd, 1, data])
	_peer.put_u32(bytes.size())
	_peer.put_data(bytes)


func _handle(msg: Array) -> void:
	var cmd := str(msg[0])
	var data: Array = msg[msg.size() - 1] if msg[msg.size() - 1] is Array else []
	_msg_counts[cmd] = int(_msg_counts.get(cmd, 0)) + 1
	match cmd:
		"perf:mark":
			_label = str(data[0])
			if not _agg.has(_label):
				_order.append(_label)
		"debug_enter":
			# a script error would otherwise stop the game waiting for the debugger
			print("profiler_host: game hit a script error/breakpoint: ", data)
			_send("continue", [])
		"servers:function_signature":
			# [signature, id] pairs ("res://path.gd::line::Class.func")
			for k in range(0, data.size() - 1, 2):
				_sigs[int(data[k + 1])] = str(data[k])
		"servers:profile_frame":
			_frame(data)
		"visual:profile_frame":
			_visual(data)
		"output":
			pass
		"error":
			pass


func _bucket() -> Dictionary:
	if not _agg.has(_label):
		_agg[_label] = {"frames": 0, "frame": 0.0, "process": 0.0, "physics": 0.0, "physics_frame": 0.0,
			"script": 0.0, "servers": {}, "funcs": {}, "worst": 0.0, "worst_funcs": {}, "rows": []}
		if not _order.has(_label):
			_order.append(_label)
	return _agg[_label]


## ServersProfilerFrame::serialize(): frame_number, frame_time, process_time, physics_time,
## physics_frame_time, script_time, server count, [name, 2*n, (fname, time)...]..., 4*m,
## (sig_id, calls, self, total, internal)... (all times in seconds)
func _frame(a: Array) -> void:
	if a.size() < 7:
		return
	var b := _bucket()
	b["frames"] += 1
	var ft := float(a[1])
	b["frame"] += ft
	b["process"] += float(a[2])
	b["physics"] += float(a[3])
	b["physics_frame"] += float(a[4])
	b["script"] += float(a[5])
	(b["rows"] as Array).append(PackedFloat64Array([ft, float(a[2]), float(a[3]), float(a[5])]))
	var i := 6
	var nserv := int(a[i]); i += 1
	var servers: Dictionary = b["servers"]
	for s in nserv:
		var sname := str(a[i]); i += 1
		var cnt := int(a[i]); i += 1
		for k in range(0, cnt, 2):
			var key := sname + "/" + str(a[i])
			servers[key] = float(servers.get(key, 0.0)) + float(a[i + 1])
			i += 2
	if i >= a.size():
		return
	var nf := int(a[i]); i += 1
	var funcs: Dictionary = b["funcs"]
	var this_frame := {}
	for k in range(0, nf, 5):
		var sid := int(a[i]); var calls := int(a[i + 1]); var self_t := float(a[i + 2]); var tot := float(a[i + 3])
		i += 5
		var f: Array = funcs.get(sid, [0, 0.0, 0.0, 0.0])
		f[0] += calls; f[1] += self_t; f[2] += tot; f[3] = maxf(float(f[3]), self_t)
		funcs[sid] = f
		this_frame[sid] = self_t
	if ft > float(b["worst"]):
		b["worst"] = ft
		b["worst_funcs"] = this_frame


## VisualProfilerFrame: frame_number, 3*n, (area name, cpu ms, gpu ms)... - the renderer's own
## CPU/GPU timestamps per pass (shadows, sky, opaque, post...).
func _visual(a: Array) -> void:
	if a.size() < 2:
		return
	var b := _bucket()
	var vis: Dictionary = b.get("visual", {})
	b["visual"] = vis
	b["vframes"] = int(b.get("vframes", 0)) + 1
	var n := int(a[1])
	for k in range(0, n, 3):
		var nm := str(a[2 + k])
		var v: Vector2 = vis.get(nm, Vector2.ZERO)
		vis[nm] = v + Vector2(float(a[3 + k]), float(a[4 + k]))


func _sig(id: int) -> String:
	var s: String = _sigs.get(id, "#%d" % id)
	return s.replace("res://", "")


func _finish() -> void:
	print("profiler_host: game disconnected; messages: ", _msg_counts)
	for label in _order:
		var b: Dictionary = _agg.get(label, {})
		var n := int(b.get("frames", 0))
		if n == 0:
			continue
		var fn := float(n)
		print("\n=== %s  (%d profiled frames)" % [label, n])
		print("  per frame ms: frame %.2f  process %.2f  physics %.2f  physics_frame %.2f  script %.2f  worst frame %.1f" % [
			b["frame"] / fn * 1000.0, b["process"] / fn * 1000.0, b["physics"] / fn * 1000.0,
			b["physics_frame"] / fn * 1000.0, b["script"] / fn * 1000.0, float(b["worst"]) * 1000.0])
		# what the slowest 5 % of frames spend their time on (all ms)
		var rows: Array = b["rows"]
		rows.sort_custom(func(x: PackedFloat64Array, y: PackedFloat64Array) -> bool: return x[0] < y[0])
		var p50: float = rows[rows.size() / 2][0]
		var cut := int(rows.size() * 0.95)
		var acc := PackedFloat64Array([0, 0, 0, 0])
		for r: PackedFloat64Array in rows.slice(cut):
			for j in 4:
				acc[j] += r[j]
		var ns := float(maxi(1, rows.size() - cut))
		print("  median frame %.2f ms; slowest 5%%: frame %.2f  process %.2f  physics %.2f  script %.2f" % [p50 * 1000.0,
			acc[0] / ns * 1000.0, acc[1] / ns * 1000.0, acc[2] / ns * 1000.0, acc[3] / ns * 1000.0])
		var servers: Dictionary = b["servers"]
		var skeys := servers.keys()
		skeys.sort_custom(func(x: String, y: String) -> bool: return servers[x] > servers[y])
		for k in skeys.slice(0, 14):
			print("  server  %-48s %7.3f ms/frame" % [k, float(servers[k]) / fn * 1000.0])
		var vis: Dictionary = b.get("visual", {})
		var vn := float(maxi(1, int(b.get("vframes", 0))))
		for nm: String in vis:
			var v: Vector2 = vis[nm]
			if v.x / vn > 0.02 or v.y / vn > 0.02:
				print("  render  %-48s cpu %6.3f  gpu %6.3f ms/frame" % [nm, v.x / vn, v.y / vn])
		var funcs: Dictionary = b["funcs"]
		var fkeys := funcs.keys()
		fkeys.sort_custom(func(x: int, y: int) -> bool: return funcs[x][1] > funcs[y][1])
		print("  %-70s %9s %9s %9s %8s" % ["script function (self time)", "self ms/f", "total ms/f", "calls/f", "max ms"])
		for k in fkeys.slice(0, _top):
			var f: Array = funcs[k]
			print("  %-70s %9.3f %9.3f %9.1f %8.2f" % [_sig(k).right(70), f[1] / fn * 1000.0, f[2] / fn * 1000.0, float(f[0]) / fn, float(f[3]) * 1000.0])
		var wf: Dictionary = b["worst_funcs"]
		var wk := wf.keys()
		wk.sort_custom(func(x: int, y: int) -> bool: return wf[x] > wf[y])
		var parts: Array[String] = []
		for k in wk.slice(0, 6):
			parts.append("%s %.1f" % [_sig(k).get_slice("::", 2), float(wf[k]) * 1000.0])
		print("  worst frame's top functions (ms): ", ", ".join(parts))
	print("profiler_host: done")
	get_tree().quit()
