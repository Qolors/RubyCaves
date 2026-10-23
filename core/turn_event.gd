class_name TurnEvent
extends RefCounted
## Something that happened during resolution. Actor/target are fighter ids (-1 when not applicable).

enum Kind {
	MOVED,
	TURNED,
	WAITED,
	BUMPED,
	AMBUSHED,
	ATTACKED,
	ATTACK_DODGED,
	## Both attacked: blades meet, nobody is hurt.
	CLASHED,
	## Actor guarded target's attack; target is staggered.
	BLOCKED,
	## Actor shoved through target's guard; target takes damage and is staggered.
	GUARD_BROKEN,
	## Actor shoved an unguarded (waiting or charging) target.
	SHOVED,
	## Both shoved: they push off each other.
	SHOVES_CANCELLED,
	STAGGERED,
	RETREATED,
	## Actor pursued target's flee, followed them and landed a hit; the conflict goes on.
	CAUGHT,
	## Actor pursued someone who stood their ground and over-committed (staggered).
	OVEREXTENDED,
	CONFLICT_STARTED,
	CONFLICT_ENDED,
	DIED,
}

var kind: int
var actor: int
var target: int
var amount: int


func _init(p_kind: int, p_actor: int, p_target := -1, p_amount := 0) -> void:
	kind = p_kind
	actor = p_actor
	target = p_target
	amount = p_amount
