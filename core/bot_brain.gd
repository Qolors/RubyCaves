class_name BotBrain
extends RefCounted
## Simple computer opponent. It plays fair: it only knows where you are if you are in its
## straight-ahead sight line (or in its tile), and then hunts your last known position.

const T := PlayerAction.Type

var _id: int
var _rng := RandomNumberGenerator.new()
var _last_seen: MapCell = null
var _last_seen_turn := 0
var _flee_bias: float
## Reads Footing and initiative: swings at an Exhausted foe, presses its initiative, guards to
## line the foe up against a wall. Off = the pure-habit bot (for sims).
var _footing_aware: bool
## Decaying counts of the opponent's conflict picks; all flee directions share RETREAT_BACK.
var _foe_habits := {}


## flee_bias: extra chance to flee in conflicts (used to sim a flee-spamming player).
func _init(id: int, seed := -1, flee_bias := 0.0, footing_aware := true) -> void:
	_id = id
	_flee_bias = flee_bias
	_footing_aware = footing_aware
	if seed >= 0:
		_rng.seed = seed
	else:
		_rng.randomize()


func decide(state: DuelState) -> PlayerAction:
	var me := state.fighters[_id]
	var foe := state.other(_id)
	var options := state.get_available_actions(_id)
	if options.is_empty():
		return PlayerAction.wait()

	if state.in_conflict:
		# Remember where the fight was; if the foe vanishes, hunt from here.
		_last_seen = me.cell
		_last_seen_turn = state.turn
		return _decide_conflict(state, me, foe, options)

	var ambush := _pick(options, T.AMBUSH)
	if ambush != null and _rng.randf() < 0.9:
		return ambush

	if DuelMap.sight_line(me.cell, me.facing).has(foe.cell):
		_last_seen = foe.cell
		_last_seen_turn = state.turn
		var foe_facing_me := foe.facing == Dirs.opposite(me.facing)
		if not foe_facing_me:
			return _or_wait(_pick(options, T.MOVE_FORWARD))  # sneak up behind them
		var roll := _rng.randf()
		if roll < 0.45:
			return _or_wait(_pick(options, T.MOVE_FORWARD))  # charge
		if roll < 0.65:
			return PlayerAction.wait()  # hold and bait
		for t in [T.MOVE_LEFT, T.MOVE_RIGHT, T.STEP_BACK]:  # break line of sight
			var a := _pick(options, t)
			if a != null:
				return a
		return PlayerAction.wait()

	if _last_seen != null and state.turn - _last_seen_turn <= 8:
		if _last_seen == me.cell:
			_last_seen = null
		else:
			var step := DuelMap.first_step_toward(me.cell, _last_seen)
			if step >= 0:
				var chase := _step_toward(options, me.facing, step)
				if chase != null:
					return chase

	return _wander(options)


## Learns the opponent's habits in conflicts.
func observe(result: TurnResult) -> void:
	var theirs := result.actions[1 - _id]
	var key := T.RETREAT_BACK if theirs.is_retreat() else theirs.type
	if key in [T.ATTACK, T.GUARD, T.SHOVE, T.RETREAT_BACK]:
		_foe_habits[key] = _foe_habits.get(key, 0.0) * 0.8 + 1.0


func _decide_conflict(state: DuelState, me: Fighter, foe: Fighter, options: Array[PlayerAction]) -> PlayerAction:
	if options.size() == 1:
		return options[0]  # stunned: forced to wait

	# The foe is off balance and must wait: a free hit.
	if foe.staggered:
		return _first(options, [T.ATTACK])

	# The foe's back is to a wall: a shove there pins them (stun), so it's worth fishing for.
	var foe_pinnable := foe.cell == me.cell and not me.cell.is_open(me.facing)

	if _footing_aware:
		# Exhausted foe: its attacks are Telegraphed and its guard may shatter, and it can't
		# afford to shove or run unless its next action is free. Swing at it.
		if foe.is_exhausted() and not foe.free_action and _rng.randf() < 0.7:
			return _first(options, [T.ATTACK])
		# Holding the initiative wins any trade of blows.
		if state.initiative == _id and _rng.randf() < 0.45:
			return _first(options, [T.ATTACK])
		# Out of Footing ourselves: a guard recovers and punishes a swing.
		if me.is_exhausted() and _rng.randf() < 0.6:
			return _guard(options, me)
		if foe_pinnable and _rng.randf() < 0.4:
			return _first(options, [T.SHOVE])

	var retreats := options.filter(func(o: PlayerAction): return o.is_retreat())
	var losing := me.hp <= DuelRules.ATTACK_DAMAGE and foe.hp > DuelRules.ATTACK_DAMAGE
	var retreat_chance := (0.45 if losing else (0.15 if me.hp < foe.hp else 0.05)) + _flee_bias
	if not retreats.is_empty() and _rng.randf() < retreat_chance:
		return retreats[_rng.randi_range(0, retreats.size() - 1)]

	# Counter the opponent's most common pick some of the time, otherwise mix it up.
	if not _foe_habits.is_empty() and _rng.randf() < 0.55:
		var favourite: int = _foe_habits.keys()[0]
		for k in _foe_habits:
			if _foe_habits[k] > _foe_habits[favourite]:
				favourite = k
		match favourite:
			T.ATTACK: return _guard(options, me)
			T.GUARD: return _first(options, [T.SHOVE])
			_: return _first(options, [T.ATTACK])  # beats Shove and catches a flee
	var roll := _rng.randf()
	if roll < 0.45:
		return _first(options, [T.ATTACK])
	if roll < 0.75:
		return _guard(options, me)
	return _first(options, [T.SHOVE])


## A guard, turning the pair so the foe's back is to a wall when that's on offer.
func _guard(options: Array[PlayerAction], me: Fighter) -> PlayerAction:
	if _footing_aware:
		for o in options:
			if o.type != T.GUARD or o.veer == PlayerAction.Veer.NONE:
				continue
			var turned := Dirs.left(me.facing) if o.veer == PlayerAction.Veer.LEFT else Dirs.right(me.facing)
			if not me.cell.is_open(turned):
				return o
	for o in options:
		if o.type == T.GUARD and o.veer == PlayerAction.Veer.NONE:
			return o
	return _first(options, [T.GUARD])


## First affordable option of the given types, else Guard (always allowed in a conflict).
func _first(options: Array[PlayerAction], types: Array) -> PlayerAction:
	for t in types + [T.GUARD]:
		var a := _pick(options, t)
		if a != null:
			return a
	return options[0]


func _step_toward(options: Array[PlayerAction], facing: int, step: int) -> PlayerAction:
	if step == facing:
		return _pick(options, T.MOVE_FORWARD)
	if step == Dirs.left(facing):
		return _pick(options, T.MOVE_LEFT)
	if step == Dirs.right(facing):
		return _pick(options, T.MOVE_RIGHT)
	return _pick(options, T.TURN_AROUND) if _rng.randf() < 0.5 else _pick(options, T.STEP_BACK)


func _wander(options: Array[PlayerAction]) -> PlayerAction:
	var weighted := []
	var total := 0.0
	for o in options:
		var w := 0.0
		match o.type:
			T.MOVE_FORWARD: w = 6.0
			T.MOVE_LEFT, T.MOVE_RIGHT: w = 1.5
			T.TURN_LEFT, T.TURN_RIGHT: w = 0.6
			T.TURN_AROUND: w = 0.5
			T.WAIT: w = 0.5
			T.STEP_BACK: w = 0.3
		if w > 0.0:
			weighted.append([o, w])
			total += w
	if weighted.is_empty():
		return PlayerAction.wait()
	var roll := _rng.randf() * total
	for pair in weighted:
		roll -= pair[1]
		if roll <= 0.0:
			return pair[0]
	return weighted[-1][0]


## Picks an action of the given type. With several veers it mostly keeps straight, otherwise a
## random one (a T-junction side, or a hook into a side passage).
func _pick(options: Array[PlayerAction], type: int) -> PlayerAction:
	var matches := options.filter(func(o: PlayerAction): return o.type == type)
	if matches.is_empty():
		return null
	for m in matches:
		if m.veer == PlayerAction.Veer.NONE and matches.size() > 1 and _rng.randf() < 0.6:
			return m
	return matches[_rng.randi_range(0, matches.size() - 1)]


static func _or_wait(a: PlayerAction) -> PlayerAction:
	return a if a != null else PlayerAction.wait()
