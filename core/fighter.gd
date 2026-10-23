class_name Fighter
extends RefCounted

var id: int
var cell: MapCell
var facing: int
var hp := DuelRules.MAX_HP
## Off balance: this fighter's next action is forced to Wait.
var staggered := false
## Last turn number on which this fighter is still winded (can't flee).
var winded_until := -1


func _init(p_id: int, p_cell: MapCell, p_facing: int) -> void:
	id = p_id
	cell = p_cell
	facing = p_facing


func is_dead() -> bool:
	return hp <= 0
