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
## Reads Focus: shoves a foe who can't afford to attack. Off = the old pure-habit bot (for sims).
var _focus_aware: bool
## Decaying counts of the opponent's conflict picks; all flee directions share RETREAT_BACK.
var _foe_habits := {}


## flee_bias: extra chance to flee in conflicts (used to sim a flee-spamming player).
func _init(id: int, seed := -1, flee_bias := 0.0, focus_aware := true) -> void:
	_id = id
	_flee_bias = flee_bias
	_focus_aware = focus_aware
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
	if key in [T.ATTACK, T.GUARD, T.SHOVE, T.PURSUE, T.RETREAT_BACK]:
		_foe_habits[key] = _foe_habits.get(key, 0.0) * 0.8 + 1.0


func _decide_conflict(state: DuelState, me: Fighter, foe: Fighter, options: Array[PlayerAction]) -> PlayerAction:
	if options.size() == 1:
		return options[0]  # staggered, or out of Focus with only Guard left

	# The foe is off balance and must wait: free hit (a shove if we can't afford a swing).
	if foe.staggered:
		return _first(options, [T.ATTACK, T.SHOVE])

	# Focus read: a foe who can't afford to attack can only guard, shove, pursue or run.
	# Shove beats guard and pursue and cancels a shove, so it's the safe punish. At 0 Focus
	# their only option is Guard, so it's a sure thing.
	if _focus_aware and not state.can_afford(foe.id, T.ATTACK):
		var shove := _pick(options, T.SHOVE)
		if shove != null and (foe.focus == 0 or _rng.randf() < 0.75):
			return shove

	var retreats := options.filter(func(o: PlayerAction): return o.is_retreat())
	var losing := me.hp <= DuelRules.ATTACK_DAMAGE and foe.hp > DuelRules.ATTACK_DAMAGE
	var retreat_chance := (0.45 if losing else (0.15 if me.hp < foe.hp else 0.05)) + _flee_bias
	if not retreats.is_empty() and _rng.randf() < retreat_chance:
		return retreats[_rng.randi_range(0, retreats.size() - 1)]

	var can_pursue := _pick(options, T.PURSUE) != null
	# Counter the opponent's most common pick some of the time, otherwise mix it up.
	if not _foe_habits.is_empty() and _rng.randf() < 0.55:
		var favourite: int = _foe_habits.keys()[0]
		for k in _foe_habits:
			if _foe_habits[k] > _foe_habits[favourite]:
				favourite = k
		var counter := T.ATTACK
		match favourite:
			T.ATTACK: counter = T.GUARD
			T.GUARD: counter = T.SHOVE
			T.PURSUE: counter = T.GUARD
			T.RETREAT_BACK: counter = T.PURSUE if can_pursue else T.ATTACK
		return _first(options, [counter])
	var roll := _rng.randf()
	if can_pursue and roll < 0.12:
		return _first(options, [T.PURSUE])
	if roll < 0.5:
		return _first(options, [T.ATTACK])
	return _first(options, [T.GUARD if roll < 0.77 else T.SHOVE])


## First affordable option of the given types, else Guard (always free in a conflict).
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


## Picks an action of the given type, choosing a random veer when there are two variants.
func _pick(options: Array[PlayerAction], type: int) -> PlayerAction:
	var matches := options.filter(func(o: PlayerAction): return o.type == type)
	if matches.is_empty():
		return null
	return matches[_rng.randi_range(0, matches.size() - 1)]


static func _or_wait(a: PlayerAction) -> PlayerAction:
	return a if a != null else PlayerAction.wait()
