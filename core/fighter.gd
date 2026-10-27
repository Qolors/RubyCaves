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
## Conflict stamina (see DuelRules.footing_cost). Public knowledge, like HP.
var footing := DuelRules.MAX_FOOTING
## Earned by a Guard that holds: the next conflict action costs no Footing.
var free_action := false


func _init(p_id: int, p_cell: MapCell, p_facing: int) -> void:
	id = p_id
	cell = p_cell
	facing = p_facing


## At 0 Footing: attacks are Telegraphed and guards can shatter.
func is_exhausted() -> bool:
	return footing <= 0


func is_dead() -> bool:
	return hp <= 0
