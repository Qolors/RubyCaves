class_name DuelRules

const MAX_HP := 10
const ATTACK_DAMAGE := 2
const AMBUSH_DAMAGE := 4
const SHOVE_DAMAGE := 1
const PURSUE_DAMAGE := 2
const TURN_SECONDS := 10.0

# Tuning knobs (settable so balance sims can A/B them).
## Turns after a flee during which that fighter can't flee again.
static var winded_turns := 3
static var pursue_enabled := true
