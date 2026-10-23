class_name PlayerAction
extends RefCounted
## One choice for one tick. Veer only matters for moves that land in a T-junction.

enum Group { MOVEMENT, COMBAT }

enum Type {
	WAIT,
	# Movement
	MOVE_FORWARD,
	MOVE_LEFT,
	MOVE_RIGHT,
	STEP_BACK,
	TURN_LEFT,
	TURN_RIGHT,
	TURN_AROUND,
	# Combat
	AMBUSH,
	ATTACK,
	GUARD,
	SHOVE,
	## Chase a flee: catches any retreat, loses to everything else.
	PURSUE,
	RETREAT_BACK,
	RETREAT_LEFT,
	RETREAT_RIGHT,
	## Slip past the enemy to the cell beyond them.
	RETREAT_THROUGH,
}

## Which way an auto-corner turn should go when a move lands in a T-junction.
enum Veer { NONE, LEFT, RIGHT }

var type: int
var veer: int


func _init(p_type: int = Type.WAIT, p_veer: int = Veer.NONE) -> void:
	type = p_type
	veer = p_veer


static func wait() -> PlayerAction:
	return PlayerAction.new(Type.WAIT)


func equals(o: PlayerAction) -> bool:
	return o != null and type == o.type and veer == o.veer


func group() -> int:
	return Group.COMBAT if type >= Type.AMBUSH else Group.MOVEMENT


func is_retreat() -> bool:
	return type in [Type.RETREAT_BACK, Type.RETREAT_LEFT, Type.RETREAT_RIGHT, Type.RETREAT_THROUGH]


static func type_from_name(n: String) -> int:
	# Accepts the C#-style names used by the dev flags, e.g. "MoveForward" or "RetreatThrough".
	var key := n.to_snake_case().to_upper()
	return Type.get(key, Type.WAIT)


func label() -> String:
	var base: String
	match type:
		Type.WAIT: base = "WAIT"
		Type.MOVE_FORWARD: base = "FORWARD"
		Type.MOVE_LEFT: base = "MOVE L"
		Type.MOVE_RIGHT: base = "MOVE R"
		Type.STEP_BACK: base = "STEP BACK"
		Type.TURN_LEFT: base = "TURN L"
		Type.TURN_RIGHT: base = "TURN R"
		Type.TURN_AROUND: base = "TURN 180"
		Type.AMBUSH: base = "AMBUSH!"
		Type.ATTACK: base = "ATTACK"
		Type.GUARD: base = "GUARD"
		Type.SHOVE: base = "SHOVE"
		Type.PURSUE: base = "PURSUE"
		Type.RETREAT_BACK: base = "RETREAT"
		Type.RETREAT_LEFT: base = "FLEE L"
		Type.RETREAT_RIGHT: base = "FLEE R"
		Type.RETREAT_THROUGH: base = "DASH PAST"
		_: base = Type.keys()[type]
	match veer:
		Veer.LEFT: return base + " >L"
		Veer.RIGHT: return base + " >R"
	return base


func _to_string() -> String:
	return label()
