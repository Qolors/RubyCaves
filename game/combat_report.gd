class_name CombatReport
extends RefCounted
## Turns one resolved combat turn into a plain-language report for the local player:
## what both sides picked, who won the exchange and the rule that decided it, then what changed.

const T := PlayerAction.Type
const K := TurnEvent.Kind
const GOOD := Color(0.45, 1.0, 0.45)
const BAD := Color(1.0, 0.35, 0.3)
const NEUTRAL := Color(0.9, 0.9, 0.9)
const MAX_LINES := 4

var matchup := ""
var verdict := ""
var color := NEUTRAL
var lines: Array[String] = []
## One-word headline for the cut-in ("BLOCKED!", "CLASH!").
var stamp := ""
## 1: we won the exchange, -1: we lost it, 0: even.
var outcome := 0
## Both picks, for the VS card ("" outside a fight, e.g. an ambush).
var my_verb := ""
var foe_verb := ""


## What the report needs from before the turn resolved.
static func snapshot(s: DuelState) -> Dictionary:
	return {
		"hp": [s.fighters[0].hp, s.fighters[1].hp],
		"footing": [s.fighters[0].footing, s.fighters[1].footing],
		"initiative": s.initiative,
		"in_conflict": s.in_conflict,
	}


## Null when the turn had no fighting in it (plain walking).
static func build(r: TurnResult, before: Dictionary, s: DuelState, me: int) -> CombatReport:
	var rep := CombatReport.new()
	var foe := 1 - me
	if r.has(K.AMBUSHED):
		var mine := r.has(K.AMBUSHED, me)
		rep.matchup = "AMBUSH!"
		rep.verdict = "You strike it from behind!" if mine else "Ambushed from behind!"
		rep.color = GOOD if mine else BAD
		rep.stamp = "AMBUSH!"
		rep.outcome = 1 if mine else -1
		rep.lines.append("Its move is cancelled; it spins to face you." if mine else "Your move is cancelled; you spin to face it.")
	elif not before["in_conflict"] and r.has(K.CONFLICT_STARTED):
		rep.matchup = "FACE OFF"
		rep.verdict = "You run into each other."
		rep.stamp = "FACE OFF!"
		rep.lines.append("A neutral fight: nobody holds the INITIATIVE.")
	elif before["in_conflict"]:
		rep.my_verb = _verb(r.actions[me])
		rep.foe_verb = _verb(r.actions[foe])
		rep.matchup = "You %s  vs  Enemy %s" % [rep.my_verb, rep.foe_verb]
		rep._judge(r, me)
	else:
		return null
	rep._consequences(r, before, s, me)
	if rep.lines.size() > MAX_LINES:
		rep.lines.resize(MAX_LINES)
	return rep


static func _verb(a: PlayerAction) -> String:
	if a.is_retreat():
		return "DASH" if a.type == T.RETREAT_THROUGH else "FLEE"
	match a.type:
		T.ATTACK: return "ATTACK"
		T.GUARD: return "GUARD" if a.veer == PlayerAction.Veer.NONE else "GUARD+TURN"
		T.SHOVE: return "SHOVE"
		T.WAIT: return "STUNNED"
	return a.label()


## Sets the verdict: who came out ahead and which rule decided it.
func _judge(r: TurnResult, me: int) -> void:
	var a := r.actions[me].type
	var b := r.actions[1 - me].type
	var e: TurnEvent
	if _find(r, K.GUARD_SHATTERED) != null:
		e = _find(r, K.GUARD_SHATTERED)
		_win(e.actor == me, "SHATTER!", "Exhausted guard SHATTERS!", "At 0 footing a guard can break under a full swing.")
	elif _find(r, K.PUNISHED) != null:
		e = _find(r, K.PUNISHED)
		_win(e.actor == me, "PUNISHED!", "Telegraphed swing PUNISHED", "At 0 footing an attack is slow: the guard hits back.")
	elif _find(r, K.BLOCKED) != null:
		_win(_find(r, K.BLOCKED).actor == me, "BLOCKED!", "GUARD beats ATTACK", "")
	elif _find(r, K.CAUGHT) != null:
		_win(_find(r, K.CAUGHT).actor == me, "CAUGHT!", "ATTACK catches the flee", "Running from a swing gets you cut down.")
	elif _find(r, K.PINNED) != null:
		e = _find(r, K.PINNED)
		_win(e.actor == me, "PINNED!", "SHOVE beats GUARD: slammed into the wall" if r.has(K.GUARD_BROKEN) else "Slammed into the wall", "")
	elif _find(r, K.SHOVED_AWAY) != null:
		e = _find(r, K.SHOVED_AWAY)
		_win(e.actor == me, "SHOVED OUT!", "SHOVE beats GUARD: shoved out of the room" if r.has(K.GUARD_BROKEN) else "Shoved out of the room", "")
	elif r.has(K.CLASHED):
		_neutral("CLASH!", "Blades bounce off", "Nobody held the INITIATIVE to win the trade.")
	elif a == T.ATTACK and b == T.ATTACK:
		_win(_find(r, K.ATTACKED).actor == me, "FIRST STRIKE!", "INITIATIVE wins the trade of blows", "")
	elif _find(r, K.ATTACKED) != null:
		e = _find(r, K.ATTACKED)
		var other := r.actions[e.target].type
		_win(e.actor == me, "COUNTER!" if other == T.SHOVE else "FREE HIT!", "ATTACK beats SHOVE" if other == T.SHOVE else "Free hit on a stunned fighter", "")
	elif _find(r, K.SHOVED) != null:
		_win(_find(r, K.SHOVED).actor == me, "SHOVED!", "Shove on a stunned fighter", "")
	elif r.has(K.SHOVES_CANCELLED):
		_neutral("STALEMATE", "SHOVES cancel out", "")
	elif a == T.GUARD and b == T.GUARD:
		_neutral("STALEMATE", "Both GUARD", "")
	elif r.has(K.RETREATED, 1 - me) and r.has(K.RETREATED, me):
		_neutral("SCATTER!", "You both run for it", "")
	elif r.has(K.RETREATED, 1 - me):
		_win(false, "ESCAPED!", "It ESCAPES: a flee slips past a %s" % _verb(r.actions[me]), "Only an ATTACK catches a flee.")
	elif r.has(K.RETREATED, me):
		_win(true, "ESCAPED!", "You ESCAPE: a flee slips past a %s" % _verb(r.actions[1 - me]), "Only an ATTACK catches a flee.")
	else:
		_neutral("...", "No contact", "")


func _win(mine: bool, word: String, text: String, why: String) -> void:
	stamp = word
	outcome = 1 if mine else -1
	verdict = text
	color = GOOD if mine else BAD
	if why != "":
		lines.append(why)


func _neutral(word: String, text: String, why: String) -> void:
	stamp = word
	verdict = text
	color = NEUTRAL
	if why != "":
		lines.append(why)


func _consequences(r: TurnResult, before: Dictionary, s: DuelState, me: int) -> void:
	var foe := 1 - me
	var hurt: Array[String] = []
	for id in [me, foe]:
		var dmg: int = before["hp"][id] - s.fighters[id].hp
		if dmg > 0:
			hurt.append(("You take %d" if id == me else "Enemy takes %d") % dmg)
	if not hurt.is_empty():
		lines.append(", ".join(hurt) + " damage.")

	var footing: Array[String] = []
	for id in [me, foe]:
		var was: int = before["footing"][id]
		if was != s.fighters[id].footing:
			footing.append("%s %d->%d" % ["you" if id == me else "enemy", was, s.fighters[id].footing])
	if not footing.is_empty():
		lines.append("Footing: " + ", ".join(footing))

	for e in r.events:
		if e.kind == K.STAGGERED:
			lines.append("You are STUNNED next turn." if e.actor == me else "Enemy is STUNNED next turn.")
	if r.has(K.RETREATED, me) and not r.has(K.CAUGHT):
		lines.append("You're WINDED: no fleeing for %d turns." % DuelRules.winded_turns)

	if not s.in_conflict:
		if r.has(K.CONFLICT_ENDED) and not s.is_over:
			lines.append("The fight breaks off.")
		return

	if s.initiative != before["initiative"] or r.has(K.AMBUSHED):
		if s.initiative == me:
			lines.append("You take the INITIATIVE: you win an attack trade.")
		elif s.initiative == foe:
			lines.append("Enemy takes the INITIATIVE: it wins an attack trade.")
		else:
			lines.append("INITIATIVE lost: attack trades clash again.")
	if s.fighters[me].free_action:
		lines.append("Guard held: your next move is FREE.")
	if s.fighters[foe].free_action:
		lines.append("Its guard held: its next move is FREE.")
	if r.has(K.REPOSITIONED):
		lines.append("You turn the fight around." if r.has(K.REPOSITIONED, me) else "It turns the fight around.")

	var my := s.fighters[me]
	if my.cell == s.fighters[foe].cell:
		if not my.cell.is_open(my.facing):
			lines.append("Its back is to a WALL: SHOVE pins it.")
		if not my.cell.is_open(s.fighters[foe].facing):
			lines.append("Your back is to a WALL: beware SHOVE.")
	if s.fighters[foe].is_exhausted():
		lines.append("Enemy EXHAUSTED: weak swing, brittle guard.")
	if my.is_exhausted():
		lines.append("You're EXHAUSTED: GUARD to recover.")


static func _find(r: TurnResult, kind: int) -> TurnEvent:
	for e in r.events:
		if e.kind == kind:
			return e
	return null
