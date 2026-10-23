extends SceneTree
## Converts the raw enemy art (JPG on white) into game-ready sprites:
## white background keyed out, downscaled so the character is TARGET_H px tall,
## cropped, and padded so the feet are horizontally centered (the sprite's pivot).
##
## Run:  Godot_console.exe --headless --path . --script res://tools/process_sprites.gd

const TARGET_H := 176
const SOURCES := {
	"res://art_src/enemy-front.jpg": "res://assets/sprites/enemy_front.png",
	"res://art_src/enemy-r-side.jpg": "res://assets/sprites/enemy_side.png",
	"res://art_src/enemy-rear.jpg": "res://assets/sprites/enemy_rear.png",
	"res://art_src/enemy-attack.jpg": "res://assets/sprites/enemy_attack.png",
}


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://assets/sprites"))
	for src in SOURCES:
		_convert(src, SOURCES[src])
	quit()


func _is_bg(c: Color) -> bool:
	var hi := maxf(c.r, maxf(c.g, c.b))
	var lo := minf(c.r, minf(c.g, c.b))
	return lo > 0.62 and hi - lo < 0.14


## True if a strongly saturated (glowing) opaque pixel lies within 4 px of (x, y) along dir.
func _glow_within(img: Image, x: int, y: int, dir: Vector2i) -> bool:
	for step in range(1, 5):
		var p := Vector2i(x, y) + dir * step
		if p.x < 0 or p.y < 0 or p.x >= img.get_width() or p.y >= img.get_height():
			return false
		var c := img.get_pixelv(p)
		if c.a > 0.0 and maxf(c.r, maxf(c.g, c.b)) - minf(c.r, minf(c.g, c.b)) > 0.35 and c.r > 0.6:
			return true
	return false


func _convert(src: String, dst: String) -> void:
	var img := Image.load_from_file(ProjectSettings.globalize_path(src))
	img.convert(Image.FORMAT_RGBA8)

	# Rough content height on a cheap 1/8 preview, to pick a scale that normalises character size.
	var probe := img.duplicate() as Image
	probe.resize(img.get_width() / 8, img.get_height() / 8, Image.INTERPOLATE_NEAREST)
	var top := probe.get_height()
	var bottom := 0
	for y in probe.get_height():
		for x in probe.get_width():
			if not _is_bg(probe.get_pixel(x, y)):
				top = mini(top, y)
				bottom = maxi(bottom, y)
	var content_h := float(bottom - top + 1) * 8.0
	var scale := TARGET_H / content_h
	img.resize(int(img.get_width() * scale), int(img.get_height() * scale), Image.INTERPOLATE_LANCZOS)

	var w := img.get_width()
	var h := img.get_height()
	var original := img.duplicate() as Image
	# Flood-fill the background from the borders so interior highlights stay opaque.
	var seen := PackedByteArray()
	seen.resize(w * h)
	var stack: Array[int] = []
	for x in w:
		stack.append(x)
		stack.append((h - 1) * w + x)
	for y in h:
		stack.append(y * w)
		stack.append(y * w + w - 1)
	while not stack.is_empty():
		var i: int = stack.pop_back()
		if seen[i] == 1:
			continue
		var px := i % w
		var py := i / w
		if not _is_bg(img.get_pixel(px, py)):
			continue
		seen[i] = 1
		img.set_pixel(px, py, Color(0, 0, 0, 0))
		if px > 0: stack.append(i - 1)
		if px < w - 1: stack.append(i + 1)
		if py > 0: stack.append(i - w)
		if py < h - 1: stack.append(i + w)

	# Background pockets enclosed by the silhouette (e.g. between the legs) aren't reached from the
	# border; clear any remaining white region big enough not to be a highlight.
	for start in w * h:
		if seen[start] == 1 or not _is_bg(img.get_pixel(start % w, start / w)):
			continue
		var region: Array[int] = []
		var todo: Array[int] = [start]
		var rim_sat := 0.0
		var rim_count := 0
		seen[start] = 1
		while not todo.is_empty():
			var i: int = todo.pop_back()
			region.append(i)
			var px := i % w
			var py := i / w
			for n in [i - 1 if px > 0 else -1, i + 1 if px < w - 1 else -1, i - w if py > 0 else -1, i + w if py < h - 1 else -1]:
				if n < 0 or seen[n] == 1:
					continue
				var nc := img.get_pixel(n % w, n / w)
				if _is_bg(nc):
					seen[n] = 1
					todo.append(n)
				elif nc.a > 0.0:
					rim_sat += maxf(nc.r, maxf(nc.g, nc.b)) - minf(nc.r, minf(nc.g, nc.b))
					rim_count += 1
		# A white core ringed by saturated colour is a glow (the saber blade), not background.
		var is_glow := rim_count > 0 and rim_sat / rim_count > 0.3
		if region.size() >= 25 and not is_glow:
			for i in region:
				img.set_pixel(i % w, i / w, Color(0, 0, 0, 0))

	# The saber's white-hot core touches the background through the faint glow at its tip, so the
	# flood clears it. Restore cleared pixels that sit between glowing pixels a few px either side.
	var restore: Array[int] = []
	var dirs := [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, -1)]
	for y in h:
		for x in w:
			if img.get_pixel(x, y).a > 0.0:
				continue
			for d in dirs:
				if _glow_within(img, x, y, d) and _glow_within(img, x, y, -d):
					restore.append(y * w + x)
					break
	for i in restore:
		img.set_pixel(i % w, i / w, original.get_pixel(i % w, i / w))

	# Strip the light anti-aliased halo left around the silhouette.
	var halo: Array[Vector2i] = []
	for y in range(1, h - 1):
		for x in range(1, w - 1):
			var c := img.get_pixel(x, y)
			if c.a == 0.0:
				continue
			var lum := (c.r + c.g + c.b) / 3.0
			var sat := maxf(c.r, maxf(c.g, c.b)) - minf(c.r, minf(c.g, c.b))
			if lum > 0.55 and sat < 0.2:
				for n in [Vector2i(x - 1, y), Vector2i(x + 1, y), Vector2i(x, y - 1), Vector2i(x, y + 1)]:
					if img.get_pixelv(n).a == 0.0:
						halo.append(Vector2i(x, y))
						break
	for p in halo:
		img.set_pixelv(p, Color(0, 0, 0, 0))

	var used := img.get_used_rect()
	img = img.get_region(used)
	w = img.get_width()
	h = img.get_height()

	# Feet centroid (bottom 15% of rows) becomes the horizontal center of the sprite.
	var sum := 0.0
	var count := 0
	for y in range(int(h * 0.85), h):
		for x in w:
			if img.get_pixel(x, y).a > 0.0:
				sum += x
				count += 1
	var cx := sum / maxf(count, 1)
	var half := int(ceil(maxf(cx, w - cx)))
	var out := Image.create_empty(half * 2, h, false, Image.FORMAT_RGBA8)
	out.blit_rect(img, Rect2i(0, 0, w, h), Vector2i(half - int(round(cx)), 0))
	out.save_png(ProjectSettings.globalize_path(dst))
	print("%s -> %s (%dx%d)" % [src, dst, out.get_width(), out.get_height()])
