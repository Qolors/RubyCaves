extends SceneTree
## Packs the enemy idle animations (art_src/Enemy/<dir>/frame_000..007.png, transparent pixel art)
## into one horizontal strip per direction: assets/sprites/enemy_<dir>.png.
## Every frame of every direction is cropped to the same rect (the union of what they use, kept
## centred on the canvas), so the character's scale and feet line match whichever strip is shown.
##
## Run:  Godot_console.exe --headless --path . --script res://tools/process_sprites.gd

const SRC := "res://art_src/Enemy/%s/frame_%03d.png"
const DST := "res://assets/sprites/enemy_%s.png"
const DIRECTIONS := ["front", "rear", "left", "right"]
const FRAMES := 8


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://assets/sprites"))
	var frames := {}
	var used := Rect2i()
	var canvas := Vector2i.ZERO
	for d in DIRECTIONS:
		frames[d] = []
		for i in FRAMES:
			var img := Image.load_from_file(ProjectSettings.globalize_path(SRC % [d, i]))
			img.convert(Image.FORMAT_RGBA8)
			frames[d].append(img)
			canvas = img.get_size()
			var r := img.get_used_rect()
			used = r if used.size == Vector2i.ZERO else used.merge(r)

	# Widen symmetrically about the canvas centre so the character's horizontal pivot is unchanged.
	var half := maxi(canvas.x / 2 - used.position.x, used.end.x - canvas.x / 2)
	var crop := Rect2i(canvas.x / 2 - half, used.position.y, half * 2, used.size.y)

	for d in DIRECTIONS:
		var sheet := Image.create_empty(crop.size.x * FRAMES, crop.size.y, false, Image.FORMAT_RGBA8)
		for i in FRAMES:
			sheet.blit_rect(frames[d][i], crop, Vector2i(crop.size.x * i, 0))
		sheet.save_png(ProjectSettings.globalize_path(DST % d))
		print("%s -> %s (%d frames of %dx%d)" % [d, DST % d, FRAMES, crop.size.x, crop.size.y])
	quit()
