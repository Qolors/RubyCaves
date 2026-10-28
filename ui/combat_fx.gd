class_name CombatFx
extends Control
## Anime-style 2D overlay for fight turns, drawn over the world view: cinematic letterbox, the VS card,
## the verdict stamp, speed lines, slash streaks, impact sparks and damage numbers.
## Points are fractions of the view (0..1), so callers don't care about the layout size.

const YOU_COLOR := Color(0.25, 0.55, 1.0)
const FOE_COLOR := Color(0.85, 0.15, 0.15)
const BAR_HEIGHT := 30.0
const STAMP_SIZE := 64

var _bars := 0.0
var _lines_time := 0.0
var _lines_color := Color.WHITE
var _lines_seed := 0
var _lines_refresh := 0.0
## Live streaks and spark bursts: {"p": Vector2 (px), "dir": Vector2, "t": age, "life": s, "color": Color}.
var _slashes: Array = []
var _bursts: Array = []

var _versus: Control
var _you_slab: Slab
var _foe_slab: Slab
var _vs: Label
var _stamp: Control
var _stamp_word: Label
var _stamp_result: Slab
var _stamp_verdict: Label


## A slanted panel: the anime cut-in strip that names a fighter or the result.
class Slab:
	extends Control
	var color := Color.BLACK
	var skew := 18.0
	var edge := Color(1, 1, 1, 0.7)

	func _draw() -> void:
		var pts := PackedVector2Array([Vector2(skew, 0), Vector2(size.x, 0), Vector2(size.x - skew, size.y), Vector2(0, size.y)])
		draw_colored_polygon(pts, color)
		draw_line(pts[0], pts[1], edge, 2.0)
		draw_line(pts[3], pts[2], edge, 2.0)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_versus()
	_build_stamp()


func _build_versus() -> void:
	_versus = Control.new()
	_versus.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_versus.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_versus.visible = false
	add_child(_versus)
	_you_slab = _fighter_slab(YOU_COLOR, true)
	_foe_slab = _fighter_slab(FOE_COLOR, false)
	_vs = _big_label("VS", 56, Color(1.0, 0.9, 0.3))
	_versus.add_child(_vs)


func _fighter_slab(color: Color, left: bool) -> Slab:
	var slab := Slab.new()
	slab.color = Color(color.darkened(0.45), 0.92)
	slab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", -6)
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 26
	box.offset_right = -26
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	slab.add_child(box)
	var who := _big_label("YOU" if left else "ENEMY", 22, color.lightened(0.5))
	var what := _big_label("", 40, Color.WHITE)
	for l in [who, what]:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if left else HORIZONTAL_ALIGNMENT_RIGHT
		box.add_child(l)
	slab.set_meta("what", what)
	_versus.add_child(slab)
	return slab


func _build_stamp() -> void:
	_stamp = Control.new()
	_stamp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stamp.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_stamp.visible = false
	add_child(_stamp)
	_stamp_word = _big_label("", STAMP_SIZE, Color.WHITE)
	_stamp.add_child(_stamp_word)
	_stamp_result = Slab.new()
	_stamp_result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var result_label := _big_label("", 28, Color.BLACK)
	result_label.add_theme_constant_override("outline_size", 0)
	result_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_stamp_result.add_child(result_label)
	_stamp_result.set_meta("label", result_label)
	_stamp.add_child(_stamp_result)
	_stamp_verdict = _big_label("", 22, Color.WHITE)
	_stamp_verdict.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_stamp.add_child(_stamp_verdict)


static func _big_label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 8)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
	return l


# ---------- cut-ins ----------

## Cinematic black bars slide in (or out).
func letterbox(on: bool, seconds := 0.18) -> void:
	create_tween().tween_property(self, "_bars", 1.0 if on else 0.0, seconds).set_trans(Tween.TRANS_QUAD)


## Both picks slam in from opposite sides with a VS between them.
func versus(my_verb: String, foe_verb: String) -> void:
	_you_slab.get_meta("what").text = my_verb
	_foe_slab.get_meta("what").text = foe_verb
	var w := size.x
	var h := Vector2(w * 0.78, 84)
	_you_slab.size = h
	_foe_slab.size = h
	var y := size.y * 0.22
	_versus.visible = true
	_versus.modulate.a = 1.0
	_you_slab.position = Vector2(-w, y)
	_foe_slab.position = Vector2(w, y + 104)
	var t := create_tween().set_parallel()
	t.tween_property(_you_slab, "position:x", -10.0, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(_foe_slab, "position:x", w - h.x + 10.0, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(0.06)
	# VS slams down between them.
	_vs.size = Vector2(120, 60)
	_vs.position = Vector2(w / 2 - 60, y + 74)
	_vs.pivot_offset = _vs.size / 2
	_vs.scale = Vector2.ONE * 3.0
	_vs.modulate.a = 0.0
	t.tween_property(_vs, "scale", Vector2.ONE, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN).set_delay(0.14)
	t.tween_property(_vs, "modulate:a", 1.0, 0.08).set_delay(0.14)
	# Slow drift while it holds, so the card never sits dead still.
	t.tween_property(_you_slab, "position:x", 4.0, 0.6).set_delay(0.16)
	t.tween_property(_foe_slab, "position:x", w - h.x - 4.0, 0.6).set_delay(0.22)


func hide_versus() -> void:
	var w := size.x
	var t := create_tween().set_parallel()
	t.tween_property(_you_slab, "position:x", w, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_property(_foe_slab, "position:x", -w, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_property(_vs, "modulate:a", 0.0, 0.1)
	t.chain().tween_callback(func(): _versus.visible = false)


## The verdict: a big word slammed onto the screen, a WIN/LOSE strip, and the rule that decided it.
## outcome: 1 won the exchange, -1 lost it, 0 even.
func stamp(word: String, color: Color, outcome: int, verdict: String) -> void:
	var w := size.x
	var font := get_theme_font("font", "Label")
	var fs := STAMP_SIZE
	while fs > 30 and font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > w * 0.9:
		fs -= 4
	_stamp_word.add_theme_font_size_override("font_size", fs)
	_stamp_word.text = word
	_stamp_word.add_theme_color_override("font_color", color)
	var y := size.y * 0.24
	_stamp_word.size = Vector2(w, fs + 10)
	_stamp_word.position = Vector2(0, y)
	_stamp_word.pivot_offset = _stamp_word.size / 2

	var result: String = ["EVEN", "YOU WIN THE EXCHANGE", "YOU LOSE THE EXCHANGE"][outcome if outcome >= 0 else 2]
	var label: Label = _stamp_result.get_meta("label")
	label.text = result
	_stamp_result.color = color if outcome != 0 else Color(0.85, 0.85, 0.85)
	_stamp_result.size = Vector2(w * 0.86, 34)
	_stamp_result.position = Vector2(w * 0.07, y + fs + 14)
	_stamp_result.queue_redraw()

	_stamp_verdict.text = verdict
	_stamp_verdict.size = Vector2(w - 24, 50)
	_stamp_verdict.position = Vector2(12, y + fs + 54)

	_stamp.visible = true
	_stamp.modulate.a = 1.0
	_stamp_word.scale = Vector2.ONE * 3.2
	_stamp_word.rotation = -0.25
	_stamp_word.modulate.a = 0.0
	_stamp_result.scale = Vector2(0.0, 1.0)
	_stamp_result.pivot_offset = _stamp_result.size / 2
	_stamp_verdict.modulate.a = 0.0
	var t := create_tween().set_parallel()
	t.tween_property(_stamp_word, "scale", Vector2.ONE, 0.13).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_property(_stamp_word, "rotation", -0.06, 0.13)
	t.tween_property(_stamp_word, "modulate:a", 1.0, 0.06)
	t.tween_property(_stamp_result, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(0.13)
	t.tween_property(_stamp_verdict, "modulate:a", 1.0, 0.15).set_delay(0.2)
	# Slow creep toward the viewer while it holds.
	t.tween_property(_stamp_word, "scale", Vector2.ONE * 1.08, 0.8).set_delay(0.13)
	burst(Vector2(0.5, (y + fs * 0.5) / maxf(1.0, size.y)), color, 14, 0.35)


func hide_stamp() -> void:
	var t := create_tween().set_parallel()
	t.tween_property(_stamp, "modulate:a", 0.0, 0.14)
	t.tween_property(_stamp_word, "scale", Vector2.ONE * 1.6, 0.14)
	t.chain().tween_callback(func(): _stamp.visible = false)


# ---------- impacts ----------

## Radial speed lines rushing in from the screen edges.
func speed_lines(seconds: float, color: Color) -> void:
	_lines_time = seconds
	_lines_color = color


## A blade streak through a point (0..1 of the view).
func slash(point: Vector2, color := Color.WHITE) -> void:
	var dir := Vector2(1, -0.55 + randf() * 0.3).normalized()
	if randf() < 0.5:
		dir.x = -dir.x
	_slashes.append({"p": point * size, "dir": dir, "t": 0.0, "life": 0.28, "color": color})


## A star of sparks at a point (0..1 of the view).
func burst(point: Vector2, color: Color, count := 12, life := 0.3) -> void:
	var rays := []
	for i in count:
		rays.append([randf() * TAU, 0.5 + randf() * 0.8])
	_bursts.append({"p": point * size, "rays": rays, "t": 0.0, "life": life, "color": color})


## A damage number that pops at a point (0..1 of the view) and floats up.
func pop_number(text: String, point: Vector2, color: Color) -> void:
	var l := _big_label(text, 46, color)
	l.size = Vector2(120, 50)
	l.position = point * size - l.size / 2
	l.pivot_offset = l.size / 2
	l.scale = Vector2.ONE * 2.2
	add_child(l)
	var t := l.create_tween().set_parallel()
	t.tween_property(l, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(l, "position:y", l.position.y - 40, 0.9).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(l, "modulate:a", 0.0, 0.3).set_delay(0.7)
	t.chain().tween_callback(l.queue_free)


## Clears everything (new match).
func reset() -> void:
	_bars = 0.0
	_lines_time = 0.0
	_slashes.clear()
	_bursts.clear()
	_versus.visible = false
	_stamp.visible = false


func _process(delta: float) -> void:
	_lines_time = maxf(0.0, _lines_time - delta)
	_lines_refresh -= delta
	if _lines_refresh <= 0.0:
		_lines_refresh = 0.05
		_lines_seed += 1
	for list in [_slashes, _bursts]:
		for fx in list:
			fx["t"] += delta
		list.assign(list.filter(func(fx): return fx["t"] < fx["life"]))
	queue_redraw()


func _draw() -> void:
	var c := size / 2
	if _lines_time > 0.0:
		var rng := RandomNumberGenerator.new()
		rng.seed = _lines_seed
		var reach := c.length()
		var a := minf(1.0, _lines_time * 4.0)
		for i in 44:
			var dir := Vector2.from_angle(rng.randf() * TAU)
			var inner := reach * rng.randf_range(0.5, 0.85)
			var col := _lines_color.lerp(Color.WHITE, 0.5)
			col.a = 0.45 * a
			draw_line(c + dir * inner, c + dir * reach * 1.1, col, rng.randf_range(1.0, 3.0))

	for fx in _slashes:
		var k: float = fx["t"] / fx["life"]
		var length := size.x * 0.75 * minf(1.0, k * 4.0)
		var width := 10.0 * (1.0 - k)
		var p: Vector2 = fx["p"]
		var d: Vector2 = fx["dir"]
		var n := Vector2(-d.y, d.x)
		var glow: Color = fx["color"]
		glow.a = 0.6 * (1.0 - k)
		draw_colored_polygon(PackedVector2Array([p - d * length, p + n * width * 1.8, p + d * length, p - n * width * 1.8]), glow)
		draw_colored_polygon(PackedVector2Array([p - d * length, p + n * width * 0.6, p + d * length, p - n * width * 0.6]), Color(1, 1, 1, 1.0 - k))

	for fx in _bursts:
		var k: float = fx["t"] / fx["life"]
		var col: Color = fx["color"].lerp(Color.WHITE, 0.4)
		col.a = 1.0 - k
		var p: Vector2 = fx["p"]
		for ray in fx["rays"]:
			var dir := Vector2.from_angle(ray[0])
			var r0: float = 10.0 + 60.0 * ray[1] * k
			var r1: float = r0 + 26.0 * ray[1] * (1.0 - k)
			draw_line(p + dir * r0, p + dir * r1, col, 3.0)

	if _bars > 0.0:
		var hgt := BAR_HEIGHT * _bars
		draw_rect(Rect2(0, 0, size.x, hgt), Color.BLACK)
		draw_rect(Rect2(0, size.y - hgt, size.x, hgt), Color.BLACK)
