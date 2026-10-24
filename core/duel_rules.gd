class_name DuelRules

const T := PlayerAction.Type

const MAX_HP := 10
const ATTACK_DAMAGE := 2
const AMBUSH_DAMAGE := 4
const SHOVE_DAMAGE := 1
const PURSUE_DAMAGE := 2
const TURN_SECONDS := 10.0
## Focus is the conflict stamina, visible to both players. Out of conflict it refills by
## FOCUS_REGEN each turn.
const MAX_FOCUS := 3
const FOCUS_REGEN := 1

# Tuning knobs (settable so balance sims can A/B them).
## Turns after a flee during which that fighter can't flee again.
static var winded_turns := 3
static var pursue_enabled := true
static var focus_enabled := true


## Focus a conflict action costs; negative means it gives Focus back.
## Guarding (or being forced to wait) catches your breath.
static func focus_cost(type: int) -> int:
	if not focus_enabled:
		return 0
	match type:
		T.ATTACK:
			return 2
		T.SHOVE, T.PURSUE, T.RETREAT_BACK, T.RETREAT_LEFT, T.RETREAT_RIGHT, T.RETREAT_THROUGH:
			return 1
		T.GUARD, T.WAIT:
			return -1
	return 0
