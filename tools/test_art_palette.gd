extends RefCounted
# Every generated blue sprite must match its current source: same file hash in the manifest and the
# same silhouette the same way round (not mirrored). Catches stale derivatives after art edits.
# Fix a failure with: godot_console --headless --path . -s tools/prepare_assets.gd, then --import.
const SIZE := 48

static func mask(path: String) -> PackedByteArray:
	var img := Image.load_from_file(path)
	if img.is_compressed(): img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	img.resize(SIZE,SIZE,Image.INTERPOLATE_BILINEAR)
	var out := PackedByteArray()
	out.resize(SIZE*SIZE)
	for y: int in range(SIZE):
		for x: int in range(SIZE): out[y*SIZE+x] = 1 if img.get_pixel(x,y).a > 0.3 else 0
	return out

static func run(t) -> void:
	# One check for every sprite (producer 2026-11-18: keep quick_test under 50 checks); failures are listed.
	var manifest = JSON.parse_string(FileAccess.get_file_as_string("res://assets/generated-palette/manifest.json"))
	if not manifest is Dictionary or manifest.is_empty():
		t.check(false,"palette manifest exists")
		return
	var stale: Array = []
	var wrong_shape: Array = []
	# Decoding ~600 large PNGs took ~30 s; a pair whose source and derivative hashes were already
	# compared is skipped (cache in user://, rebuilt automatically when either file changes).
	var cache_path := "user://art_palette_verified.json"
	var cache = JSON.parse_string(FileAccess.get_file_as_string(cache_path)) if FileAccess.file_exists(cache_path) else {}
	if not cache is Dictionary: cache = {}
	for kind: String in manifest:
		var entry: Dictionary = manifest[kind]
		var generated := "res://assets/generated-palette/"+kind+".png"
		var source_sha := FileAccess.get_sha256(entry.source)
		if source_sha != entry.sha256: stale.append(kind)
		var pair := source_sha+"|"+FileAccess.get_sha256(generated)
		if cache.get(kind,"") == pair: continue
		var a := mask(entry.source)
		var b := mask(generated)
		var same := 0
		var mirrored := 0
		for y: int in range(SIZE):
			for x: int in range(SIZE):
				if a[y*SIZE+x] == b[y*SIZE+x]: same += 1
				if a[y*SIZE+x] == b[y*SIZE+SIZE-1-x]: mirrored += 1
		if not (same >= SIZE*SIZE*0.97 and same >= mirrored): wrong_shape.append(kind)
		else: cache[kind] = pair
	var f := FileAccess.open(cache_path,FileAccess.WRITE)
	if f != null: f.store_string(JSON.stringify(cache))
	t.check(stale.is_empty() and wrong_shape.is_empty(),"blue sprites match their current source, same way round (stale: %s, wrong silhouette: %s; rerun tools/prepare_assets.gd)" % [str(stale),str(wrong_shape)])
