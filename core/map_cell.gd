class_name MapCell
extends RefCounted
## One box-shaped room on the rail grid. Openings exist only where the map defines an edge.

var id: String
var col: int
var row: int
var _links: Array = [null, null, null, null]


func _init(p_id: String, p_col: int, p_row: int) -> void:
	id = p_id
	col = p_col
	row = p_row


func is_open(d: int) -> bool:
	return _links[d] != null


func neighbor(d: int) -> MapCell:
	return _links[d]


func link(d: int, other: MapCell) -> void:
	_links[d] = other


func open_count() -> int:
	return 4 - _links.count(null)


func _to_string() -> String:
	return id
