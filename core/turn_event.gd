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
	## Both attacked with nobody holding the initiative: blades meet, nobody is hurt.
	CLASHED,
	## Actor guarded target's attack; amount is the Footing stripped from target.
	BLOCKED,
	## Actor's guard punished target's Telegraphed attack for chip damage.
	PUNISHED,
	## Actor's attack shattered target's Exhausted guard; target takes damage and is stunned.
	GUARD_SHATTERED,
	## Actor shoved through target's guard.
	GUARD_BROKEN,
	## Actor shoved an off-balance (waiting) target.
	SHOVED,
	## Actor's shove drove target out of the tile; the conflict breaks.
	SHOVED_AWAY,
	## Actor's shove slammed target into a wall; target is stunned.
	PINNED,
	## Both shoved: they push off each other.
	SHOVES_CANCELLED,
	STAGGERED,
	RETREATED,
	## Actor's attack caught target's flee: followed them and landed a hit; the conflict goes on.
	CAUGHT,
	## Actor's guard turned the pair around the tile (target is the new facing).
	REPOSITIONED,
	## Actor now holds the initiative; actor -1 means nobody does any more.
	INITIATIVE,
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
