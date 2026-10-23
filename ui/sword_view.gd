class_name SwordView
extends TextureRect
## First-person weapon overlay: idle sway, walk bob, attack swing and guard pose.

var _tex_size := Vector2.ZERO
var _time := 0.0
var _bob := 0.0
var _swing := 0.0
var _swing_power := 1.0
var _guard := 0.0


func _ready() -> void:
	var cropped := TextureFactory.crop_to_content(load("res://assets/sword.png"))
	texture = cropped
	_tex_size = cropped.region.size
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func bob() -> void:
	var t := create_tween()
	_bob = 0.0
	t.tween_method(func(v: float): _bob = v, 0.0, 1.0, 0.42)
	t.tween_callback(func(): _bob = 0.0)


func swing(heavy: bool) -> void:
	_swing_power = 1.5 if heavy else 1.0
	var t := create_tween()
	t.tween_method(func(v: float): _swing = v, 0.0, 1.0, 0.12).set_ease(Tween.EASE_OUT)
	t.tween_method(func(v: float): _swing = v, 1.0, 0.0, 0.3).set_trans(Tween.TRANS_SINE)


## Raises the blade across the body to block.
func guard() -> void:
	var t := create_tween()
	t.tween_method(func(v: float): _guard = v, 0.0, 1.0, 0.1)
	t.tween_interval(0.35)
	t.tween_method(func(v: float): _guard = v, 1.0, 0.0, 0.25)


func _process(delta: float) -> void:
	_time += delta
	var parent := get_parent() as Control
	if parent == null or _tex_size.y == 0:
		return

	var h := parent.size.y * 0.58
	var w := h * _tex_size.x / _tex_size.y
	size = Vector2(w, h)
	pivot_offset = Vector2(w * 0.8, h)

	var sway := Vector2(sin(_time * 1.3) * 2.0, sin(_time * 2.6) * 1.5)
	var bob_off := Vector2(sin(_bob * TAU) * 9.0, absf(sin(_bob * TAU)) * 8.0)
	var swing_off := Vector2(-70.0, -25.0) * _swing * _swing_power
	var guard_off := Vector2(-parent.size.x * 0.3, -h * 0.15) * _guard
	position = Vector2(parent.size.x - w * 0.95, parent.size.y - h + 12.0) + sway + bob_off + swing_off + guard_off
	rotation = -0.55 * _swing * _swing_power - 0.9 * _guard
