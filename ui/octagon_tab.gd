class_name OctagonTab
extends BaseButton
## Octagonal tab button from the UI sketch (red sword = combat, blue feet = movement).

enum Glyph { SWORD, FEET }

var icon_glyph := Glyph.SWORD
var base_color := Color.RED
var selected := false
## Pulses the tab to draw attention (e.g. ambush available).
var alert := false
var _time := 0.0


func _ready() -> void:
	custom_minimum_size = Vector2(58, 58)
	focus_mode = Control.FOCUS_NONE


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	var s := minf(size.x, size.y)
	var o := Vector2((size.x - s) / 2.0, (size.y - s) / 2.0)
	var k := roundf(s * 0.29)
	var pts := PackedVector2Array([
		o + Vector2(k, 0), o + Vector2(s - k, 0), o + Vector2(s, k), o + Vector2(s, s - k),
		o + Vector2(s - k, s), o + Vector2(k, s), o + Vector2(0, s - k), o + Vector2(0, k),
	])

	var col := base_color
	if disabled:
		col = Color(0.35, 0.35, 0.35)
	elif not selected:
		col = col.darkened(0.45)
	if alert and not disabled:
		col = col.lerp(Color.WHITE, 0.35 * (0.5 + 0.5 * sin(_time * 10.0)))
	draw_colored_polygon(pts, col)

	if selected and not disabled:
		var outline := pts.duplicate()
		outline.append(pts[0])
		draw_polyline(outline, Color.WHITE, 2.0)

	var ink := Color(0.6, 0.6, 0.6) if disabled else Color.WHITE
	var P := func(x: float, y: float) -> Vector2: return o + Vector2(x * s, y * s)
	if icon_glyph == Glyph.SWORD:
		draw_line(P.call(0.36, 0.64), P.call(0.76, 0.24), ink, s * 0.11)  # blade
		draw_colored_polygon(PackedVector2Array([P.call(0.72, 0.20), P.call(0.80, 0.20), P.call(0.80, 0.28)]), ink)  # tip
		draw_line(P.call(0.25, 0.55), P.call(0.45, 0.75), ink, s * 0.07)  # guard
		draw_line(P.call(0.35, 0.65), P.call(0.22, 0.78), ink, s * 0.07)  # grip
		draw_circle(P.call(0.20, 0.80), s * 0.05, ink)  # pommel
	else:
		for foot in [Vector2(0.36, 0.56), Vector2(0.66, 0.30)]:
			draw_circle(P.call(foot.x, foot.y), s * 0.075, ink)
			draw_circle(P.call(foot.x - 0.05, foot.y + 0.11), s * 0.05, ink)
		draw_circle(P.call(0.30, 0.82), s * 0.03, ink)
		draw_circle(P.call(0.74, 0.58), s * 0.03, ink)
