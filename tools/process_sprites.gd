extends SceneTree
## Packs the enemy art (art_src/Enemy, transparent pixel art) into horizontal strips:
##   assets/sprites/enemy_<dir>.png   8-frame idle loop per direction
##   assets/sprites/enemy_actions.png front-view combat frames, in ACTION_FRAMES order
## The combat art sits on a smaller canvas than the idle art, so each set is lined up by its feet
## (bottom edge and left foot) before cropping. Every strip uses the same crop rect (the union of
## what all frames use, kept centred on the idle canvas), so scale and feet line match across strips.
##
## Run:  Godot_console.exe --headless --path . --script res://tools/process_sprites.gd

const SRC := "res://art_src/Enemy/%s.png"
const DST := "res://assets/sprites/enemy_%s.png"
const DIRECTIONS := ["front", "rear", "left", "right"]
const IDLE_FRAMES := 8
## Front-view combat frames, packed in this order. WorldView.CLIPS indexes into it.
const ACTION_FRAMES := [
	"attack/swing_in_00", "attack/swing_in_01", "attack/swing_out_00", "attack/swing_out_01",
	"block/block_in_00", "block/block_in_01", "block/block_out_00", "block/block_out_01",
	"block-hit/block_hit_00", "block-hit/block_hit_01",
	"hit/hit_00", "hit/hit_01", "hit/hit_02",
]
## Working canvas, big enough for any frame plus its alignment shift.
const PAD := 128
## Rows above the feet used to find the left foot.
const FEET_ROWS := 6


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://assets/sprites"))
	var strips := {}
	for d in DIRECTIONS:
		strips[d] = []
		for i in IDLE_FRAMES:
			strips[d].append(_load("%s/frame_%03d" % [d, i]))
	strips["actions"] = ACTION_FRAMES.map(_load)

	# Place everything on the padded canvas, idle art centred, combat art shifted onto its feet.
	var idle_canvas: Vector2i = strips["front"][0].get_size()
	var origin := Vector2i(PAD, PAD) / 2 - idle_canvas / 2
	var idle_feet := _feet(strips["front"])
	var placed := {}
	var used := Rect2i()
	for key in strips:
		var shift := origin + (idle_feet - _feet(strips[key]) if key == "actions" else Vector2i.ZERO)
		placed[key] = []
		for img: Image in strips[key]:
			var canvas := Image.create_empty(PAD, PAD, false, Image.FORMAT_RGBA8)
			canvas.blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), shift)
			placed[key].append(canvas)
			var r := canvas.get_used_rect()
			used = r if used.size == Vector2i.ZERO else used.merge(r)

	# Widen symmetrically about the centre so the character's horizontal pivot is unchanged.
	var half := maxi(PAD / 2 - used.position.x, used.end.x - PAD / 2)
	var crop := Rect2i(PAD / 2 - half, used.position.y, half * 2, used.size.y)

	for key in placed:
		var frames: Array = placed[key]
		var sheet := Image.create_empty(crop.size.x * frames.size(), crop.size.y, false, Image.FORMAT_RGBA8)
		for i in frames.size():
			sheet.blit_rect(frames[i], crop, Vector2i(crop.size.x * i, 0))
		sheet.save_png(ProjectSettings.globalize_path(DST % key))
		print("%s -> %s (%d frames of %dx%d)" % [key, DST % key, frames.size(), crop.size.x, crop.size.y])
	quit()


static func _load(name: String) -> Image:
	var img := Image.load_from_file(ProjectSettings.globalize_path(SRC % name))
	img.convert(Image.FORMAT_RGBA8)
	return img


## Where a set of frames stands: leftmost foot pixel near the bottom, and the lowest opaque row.
static func _feet(frames: Array) -> Vector2i:
	var left := 1 << 20
	var bottom := 0
	for img: Image in frames:
		var r := img.get_used_rect()
		bottom = maxi(bottom, r.end.y)
		for y in range(r.end.y - FEET_ROWS, r.end.y):
			for x in img.get_width():
				if img.get_pixel(x, y).a > 0.5:
					left = mini(left, x)
					break
	return Vector2i(left, bottom)
