class_name DuelRules

const T := PlayerAction.Type

const MAX_HP := 10
const ATTACK_DAMAGE := 2
## A Telegraphed (0 Footing) attack, and the hit an Exhausted guard takes when it shatters.
const WEAK_DAMAGE := 1
## What a Telegraphed attack costs its owner when it runs into a Guard.
const CHIP_DAMAGE := 1
const AMBUSH_DAMAGE := 4
const SHOVE_DAMAGE := 1
const TURN_SECONDS := 10.0
## Footing is the conflict stamina, visible to both players. At 0 a fighter is Exhausted.
const MAX_FOOTING := 3
## Out of conflict: standing still or turning recovers more than walking.
const FOOTING_REGEN_STILL := 2
const FOOTING_REGEN_MOVING := 1
## Guarding a real attack: the guard's own gain, and how much it strips from the attacker.
const BLOCK_GAIN := 2
const BLOCK_STRIP := 1
## Chance an Exhausted guard shatters under a normal (non-Telegraphed) attack.
const SHATTER_CHANCE := 0.5

# Tuning knobs (settable so balance sims can A/B them).
## Turns after a flee during which that fighter can't flee again.
static var winded_turns := 3


## Footing a conflict action costs; negative means it gives Footing back.
## Guarding (or being forced to wait) catches your breath.
static func footing_cost(type: int) -> int:
	match type:
		T.ATTACK, T.SHOVE, T.RETREAT_BACK, T.RETREAT_LEFT, T.RETREAT_RIGHT, T.RETREAT_THROUGH:
			return 1
		T.GUARD, T.WAIT:
			return -1
	return 0


## Attack and Guard can always be picked (at 0 Footing they turn Telegraphed / brittle);
## Shove and fleeing need the Footing to pay for them.
static func needs_footing(type: int) -> bool:
	return type not in [T.ATTACK, T.GUARD, T.WAIT]


## Out-of-conflict recovery for the action just taken.
static func regen_for(type: int) -> int:
	match type:
		T.WAIT, T.TURN_LEFT, T.TURN_RIGHT, T.TURN_AROUND:
			return FOOTING_REGEN_STILL
	return FOOTING_REGEN_MOVING
