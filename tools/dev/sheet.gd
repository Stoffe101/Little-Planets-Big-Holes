extends Node
## Dev tool: tiles screenshots into one contact sheet (used for before/after comparisons).
## Usage: godot --headless --path . res://tools/dev/sheet.tscn -- <out.jpg|png> <columns> <tile_width> <image>...
func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 4:
		print("usage: sheet.tscn -- <out> <columns> <tile_width> <image>...")
		get_tree().quit(1)
		return
	var out: String = args[0]
	var cols := int(args[1])
	var tile_w := int(args[2])
	var tiles: Array[Image] = []
	var tile_h := 0
	for i in range(3, args.size()):
		var img := Image.load_from_file(args[i])
		if img == null:
			print("missing: ", args[i])
			continue
		img.convert(Image.FORMAT_RGB8)
		var h := int(round(float(img.get_height()) * float(tile_w) / float(img.get_width())))
		img.resize(tile_w, h, Image.INTERPOLATE_LANCZOS)
		tile_h = maxi(tile_h, h)
		tiles.append(img)
	if tiles.is_empty():
		get_tree().quit(1)
		return
	var gap := 4
	var rows := int(ceil(float(tiles.size()) / float(cols)))
	var sheet := Image.create(cols * tile_w + (cols + 1) * gap, rows * tile_h + (rows + 1) * gap, false, Image.FORMAT_RGB8)
	sheet.fill(Color(0.07, 0.07, 0.09))
	for i in tiles.size():
		var t := tiles[i]
		sheet.blit_rect(t, Rect2i(0, 0, t.get_width(), t.get_height()),
			Vector2i(gap + (i % cols) * (tile_w + gap), gap + (i / cols) * (tile_h + gap)))
	var err := sheet.save_jpg(out, 0.9) if out.ends_with(".jpg") else sheet.save_png(out)
	print("sheet ", out, " ", sheet.get_size(), " err=", err)
	get_tree().quit(0 if err == OK else 1)
