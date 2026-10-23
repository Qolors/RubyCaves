class_name MiniMap
extends Control
## Debug overlay showing the whole map and both fighters (a cheat, off by default).

const CELL := 18.0
const FLOOR := Color(0.45, 0.4, 0.45)

var state: DuelState


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if state == null:
		return
	var map := state.map
	var cols := map.max_col() - map.min_col() + 1
	var rows := map.max_row() - map.min_row() + 1
	custom_minimum_size = Vector2(cols * CELL + 8, rows * CELL + 8)
	draw_rect(Rect2(Vector2.ZERO, custom_minimum_size), Color(0, 0, 0, 0.7))

	var origin := func(c: MapCell) -> Vector2:
		return Vector2((c.col - map.min_col()) * CELL + 4, (c.row - map.min_row()) * CELL + 4)
	for c in map.cells:
		var o: Vector2 = origin.call(c)
		draw_rect(Rect2(o + Vector2(3, 3), Vector2(CELL - 6, CELL - 6)), FLOOR)
		if c.is_open(Dirs.EAST):
			draw_rect(Rect2(o + Vector2(CELL - 3, 6), Vector2(6, CELL - 12)), FLOOR)
		if c.is_open(Dirs.SOUTH):
			draw_rect(Rect2(o + Vector2(6, CELL - 3), Vector2(CELL - 12, 6)), FLOOR)

	for i in 2:
		var f := state.fighters[i]
		var center: Vector2 = origin.call(f.cell) + Vector2(CELL / 2, CELL / 2)
		if i == 1 and state.fighters[0].cell == f.cell:
			center += Vector2(3, 3)
		var fwd := Vector2(Dirs.delta(f.facing))
		var side := Vector2(-fwd.y, fwd.x)
		var col := Color(0.3, 1.0, 0.4) if i == 0 else Color(1.0, 0.3, 0.3)
		draw_colored_polygon(PackedVector2Array([center + fwd * 6, center - fwd * 4 + side * 4, center - fwd * 4 - side * 4]), col)
