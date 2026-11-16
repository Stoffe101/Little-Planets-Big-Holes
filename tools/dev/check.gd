extends Node
## Loads every script in the project so parse/compile errors show up in one headless run.
func _ready() -> void:
	var bad := 0
	for path in _collect("res://src") + _collect("res://tests") + _collect("res://tools"):
		var s: Variant = load(path)
		if s == null or not (s as GDScript).can_instantiate():
			bad += 1
			print("FAILED: ", path)
	print("check complete, failures=", bad)
	get_tree().quit(1 if bad > 0 else 0)

func _collect(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(dir_path)
	if d == null:
		return out
	for f in d.get_files():
		if f.ends_with(".gd"):
			out.append(dir_path.path_join(f))
	for sub in d.get_directories():
		out.append_array(_collect(dir_path.path_join(sub)))
	return out
