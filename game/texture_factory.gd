class_name TextureFactory
## Procedural low-res placeholder textures until real art lands.

const SIZE := 32


static func cave_wall() -> ImageTexture:
	var img := Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var mortar := Color(0.10, 0.08, 0.11)
	var brick_h := 8
	var brick_w := 16
	for y in SIZE:
		var course := y / brick_h
		var offset := (course % 2) * (brick_w / 2)
		for x in SIZE:
			var bx := (x + offset) % SIZE
			var brick := (bx / brick_w) + course * 7
			if y % brick_h == 0 or bx % brick_w == 0:
				img.set_pixel(x, y, mortar)
				continue
			var tone := 0.30 + _hash(brick, 11) * 0.12 + (_hash(x, y) - 0.5) * 0.07
			# Top-left bevel highlight, bottom-right shade.
			if y % brick_h == 1 or bx % brick_w == 1:
				tone += 0.06
			if y % brick_h == brick_h - 1 or bx % brick_w == brick_w - 1:
				tone -= 0.06
			img.set_pixel(x, y, Color(tone * 0.95, tone * 0.85, tone * 1.05))
	# A few ruby specks embedded in the stone.
	for i in 4:
		var rx := int(_hash(i, 91) * (SIZE - 3)) + 1
		var ry := int(_hash(i, 37) * (SIZE - 3)) + 1
		if ry % brick_h == 0:
			ry += 1
		img.set_pixel(rx, ry, Color(0.85, 0.10, 0.22))
		img.set_pixel(rx + 1, ry, Color(0.55, 0.05, 0.15))
		img.set_pixel(rx, ry + 1, Color(0.55, 0.05, 0.15))
		img.set_pixel(rx + 1, ry + 1, Color(1.0, 0.45, 0.55))
	return ImageTexture.create_from_image(img)


static func cave_floor() -> ImageTexture:
	var img := Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var cobble := 8
	for y in SIZE:
		for x in SIZE:
			var lx := x % cobble
			var ly := y % cobble
			var gap := lx == 0 or ly == 0 or (lx == cobble - 1 and ly == cobble - 1)
			var tone := 0.08 if gap else 0.22 + _hash(x / cobble, (y / cobble) * 5) * 0.10 + (_hash(x * 3, y * 7) - 0.5) * 0.06
			img.set_pixel(x, y, Color(tone * 1.05, tone * 0.92, tone * 0.78))
	return ImageTexture.create_from_image(img)


static func cave_ceiling() -> ImageTexture:
	var img := Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	for y in SIZE:
		for x in SIZE:
			var n := _hash(x / 4, y / 4) * 0.6 + _hash(x, y) * 0.4
			var tone := 0.10 + n * 0.12
			img.set_pixel(x, y, Color(tone * 0.9, tone * 0.85, tone))
	return ImageTexture.create_from_image(img)


## 16px dithered smoke puff (white, tinted by the sprite's modulate).
static func puff() -> ImageTexture:
	var n := 16
	var img := Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var dx := (x + 0.5 - n / 2.0) / (n / 2.0)
			var dy := (y + 0.5 - n / 2.0) / (n / 2.0)
			var d := sqrt(dx * dx + dy * dy)
			# Solid core, checkerboard-dithered rim for a chunky pixel look.
			var on := d < 0.6 or (d < 1.0 and (x + y) % 2 == 0 and _hash(x, y) > d - 0.2)
			var shade := 0.75 + _hash(x * 7, y * 3) * 0.25
			img.set_pixel(x, y, Color(shade, shade, shade, 1.0) if on else Color(0, 0, 0, 0))
	return ImageTexture.create_from_image(img)


## Crops a texture to its non-transparent pixels.
static func crop_to_content(tex: Texture2D) -> AtlasTexture:
	var img := tex.get_image()
	if img.is_compressed():
		img.decompress()
	var rect := img.get_used_rect()
	if rect.size.x == 0 or rect.size.y == 0:
		rect = Rect2i(Vector2i.ZERO, img.get_size())
	var atlas := AtlasTexture.new()
	atlas.atlas = tex
	atlas.region = Rect2(rect.position, rect.size)
	return atlas


static func _hash(x: int, y: int) -> float:
	var h := (x * 374761393 + y * 668265263) & 0xFFFFFFFF
	h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
	h ^= h >> 16
	return (h & 0xFFFF) / 65535.0
