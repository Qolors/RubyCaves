class_name FootingPips
extends Control
## Row of square Footing pips: gold when full, dark when spent; outlined red when Exhausted.

const ON := Color(1.0, 0.82, 0.2)
const OFF := Color(0.22, 0.18, 0.08, 0.9)
const EXHAUSTED := Color(0.9, 0.15, 0.1)
const PIP := 9
const GAP := 3

var value := DuelRules.MAX_FOOTING:
	set(v):
		value = v
		queue_redraw()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _get_minimum_size() -> Vector2:
	return Vector2(DuelRules.MAX_FOOTING * (PIP + GAP) - GAP, PIP)


func _draw() -> void:
	for i in DuelRules.MAX_FOOTING:
		var r := Rect2(i * (PIP + GAP), 0, PIP, PIP)
		draw_rect(r.grow(1), EXHAUSTED if value <= 0 else Color.BLACK)
		draw_rect(r, ON if i < value else OFF)
