class_name DuelState
extends RefCounted
## Authoritative, engine-agnostic duel simulation. Both players submit one action per tick;
## resolve() plays them out simultaneously. Pure logic, so it can also run on a headless server.

const T := PlayerAction.Type
const K := TurnEvent.Kind


## Where an action would take a fighter.
class Plan:
	var dest: MapCell
	var facing: int
	var move_dir: int
	var moves := false


var map: DuelMap
var fighters: Array[Fighter] = []
var in_conflict := false
var turn := 1
var is_over := false
## Winning fighter id, or -1 for a draw (only meaningful when is_over).
var winner := -1
## Fighter id holding the initiative (wins Attack vs Attack), or -1. Won by an ambush or by
## winning an exchange; lost on a stalemate or when the conflict ends.
var initiative := -1
## Rolls for Exhausted guards shattering. Seed it for reproducible sims.
var rng := RandomNumberGenerator.new()
## Turn on which ambushes are disabled (the turn right after a conflict breaks up).
var _no_ambush_turn := -1


func _init(p_map: DuelMap) -> void:
	map = p_map
	for i in 2:
		fighters.append(Fighter.new(i, map.spawns[i]["cell"], map.spawns[i]["facing"]))


func other(id: int) -> Fighter:
	return fighters[1 - id]


## Turns of winded left for a fighter as of the upcoming turn (0 = can flee).
func winded_turns_left(id: int) -> int:
	return maxi(0, fighters[id].winded_until - turn + 1)


## Whether this fighter could flee right now if in a conflict.
func _can_flee(f: Fighter) -> bool:
	return not f.staggered and winded_turns_left(f.id) == 0


## True during the one-turn breakaway window after a conflict ends.
func in_breakaway() -> bool:
	return turn == _no_ambush_turn


## True when the attacker stands one tile away looking at the target's back or side.
func can_ambush(attacker_id: int) -> bool:
	if in_conflict or is_over or turn == _no_ambush_turn:
		return false
	var a := fighters[attacker_id]
	var b := other(attacker_id)
	return a.cell.neighbor(a.facing) == b.cell and b.facing != Dirs.opposite(a.facing)


## Footing this action would cost the fighter right now (0 when their next action is free).
func cost_for(id: int, type: int) -> int:
	var cost := DuelRules.footing_cost(type)
	return 0 if cost > 0 and fighters[id].free_action else cost


func can_afford(id: int, type: int) -> bool:
	return not DuelRules.needs_footing(type) or cost_for(id, type) <= fighters[id].footing


## Legal actions for a fighter. include_unaffordable also lists conflict actions they lack the
## Footing for, so the HUD can show them greyed out; resolve() only ever accepts affordable ones.
func get_available_actions(id: int, include_unaffordable := false) -> Array[PlayerAction]:
	var list := _all_actions(id)
	if include_unaffordable or not in_conflict:
		return list
	var affordable: Array[PlayerAction] = []
	for a in list:
		if can_afford(id, a.type):
			affordable.append(a)
	return affordable


func _all_actions(id: int) -> Array[PlayerAction]:
	var list: Array[PlayerAction] = []
	if is_over:
		return list

	var f := fighters[id]
	var c := f.cell
	var fw := f.facing
	var l := Dirs.left(fw)
	var r := Dirs.right(fw)
	var bk := Dirs.opposite(fw)

	if f.staggered:
		list.append(PlayerAction.wait())
		return list

	if in_conflict:
		list.append(PlayerAction.new(T.ATTACK))
		list.append(PlayerAction.new(T.GUARD))
		# Guarding can also turn the pair around the tile, but only when sharing it.
		if other(id).cell == c:
			list.append(PlayerAction.new(T.GUARD, PlayerAction.Veer.LEFT))
			list.append(PlayerAction.new(T.GUARD, PlayerAction.Veer.RIGHT))
		list.append(PlayerAction.new(T.SHOVE))
		if not _can_flee(f):
			return list  # winded: stand and fight
		if c.is_open(bk):
			list.append(PlayerAction.new(T.RETREAT_BACK))
		if c.is_open(l):
			_add_turning_move(list, T.RETREAT_LEFT, c, l)
		if c.is_open(r):
			_add_turning_move(list, T.RETREAT_RIGHT, c, r)
		var origin := _dash_origin(f)
		if origin.is_open(fw):
			_add_turning_move(list, T.RETREAT_THROUGH, origin, fw)
		return list

	list.append(PlayerAction.wait())
	if c.is_open(fw):
		_add_turning_move(list, T.MOVE_FORWARD, c, fw)
	if c.is_open(l):
		_add_turning_move(list, T.MOVE_LEFT, c, l)
	if c.is_open(r):
		_add_turning_move(list, T.MOVE_RIGHT, c, r)
	if c.is_open(bk):
		list.append(PlayerAction.new(T.STEP_BACK))
	if c.is_open(l):
		list.append(PlayerAction.new(T.TURN_LEFT))
	if c.is_open(r):
		list.append(PlayerAction.new(T.TURN_RIGHT))
	if c.is_open(bk):
		list.append(PlayerAction.new(T.TURN_AROUND))
	if can_ambush(id):
		list.append(PlayerAction.new(T.AMBUSH))
	return list


## Adds the move, split into two veer variants when it would land facing a wall at a T.
static func _add_turning_move(list: Array[PlayerAction], type: int, from: MapCell, move_dir: int) -> void:
	if needs_veer(from, move_dir):
		list.append(PlayerAction.new(type, PlayerAction.Veer.LEFT))
		list.append(PlayerAction.new(type, PlayerAction.Veer.RIGHT))
	else:
		list.append(PlayerAction.new(type))


static func needs_veer(from: MapCell, move_dir: int) -> bool:
	var to := from.neighbor(move_dir)
	return to != null and not to.is_open(move_dir) \
		and to.is_open(Dirs.left(move_dir)) and to.is_open(Dirs.right(move_dir))


## Facing after stepping into a cell. Rounds corners automatically so the player never ends up
## staring at a wall; at a T-junction the veer picks the side.
static func landing_facing(to: MapCell, move_dir: int, veer: int) -> int:
	if to.is_open(move_dir):
		return move_dir
	var lo := to.is_open(Dirs.left(move_dir))
	var ro := to.is_open(Dirs.right(move_dir))
	if lo and ro:
		return Dirs.right(move_dir) if veer == PlayerAction.Veer.RIGHT else Dirs.left(move_dir)
	if lo:
		return Dirs.left(move_dir)
	if ro:
		return Dirs.right(move_dir)
	return Dirs.opposite(move_dir)


## Where a dash past the enemy starts: our own tile when we share it, or the enemy's tile when we
## bumped in a hallway (we slip past them into the cell beyond).
func _dash_origin(f: Fighter) -> MapCell:
	var foe := other(f.id)
	if foe.cell == f.cell:
		return f.cell
	if foe.cell == f.cell.neighbor(f.facing):
		return foe.cell
	return f.cell


func _plan_for(f: Fighter, a: PlayerAction) -> Plan:
	var plan := Plan.new()
	plan.dest = f.cell
	plan.facing = f.facing
	plan.move_dir = f.facing
	var move := -1
	var keep_facing := false
	match a.type:
		T.MOVE_FORWARD:
			move = f.facing
		T.MOVE_LEFT, T.RETREAT_LEFT:
			move = Dirs.left(f.facing)
		T.MOVE_RIGHT, T.RETREAT_RIGHT:
			move = Dirs.right(f.facing)
		T.STEP_BACK, T.RETREAT_BACK:
			move = Dirs.opposite(f.facing)
			keep_facing = true
		T.TURN_LEFT:
			plan.facing = Dirs.left(f.facing)
		T.TURN_RIGHT:
			plan.facing = Dirs.right(f.facing)
		T.TURN_AROUND:
			plan.facing = Dirs.opposite(f.facing)
		T.RETREAT_THROUGH:
			var past := _dash_origin(f).neighbor(f.facing)
			if past != null:
				plan.moves = true
				plan.dest = past
				plan.facing = landing_facing(past, f.facing, a.veer)
			return plan

	if move >= 0 and f.cell.neighbor(move) != null:
		var to := f.cell.neighbor(move)
		plan.moves = true
		plan.move_dir = move
		plan.dest = to
		plan.facing = f.facing if keep_facing else landing_facing(to, move, a.veer)
	return plan


func resolve(a0: PlayerAction, a1: PlayerAction) -> TurnResult:
	var acts: Array[PlayerAction] = [_sanitize(0, a0), _sanitize(1, a1)]
	var result := TurnResult.new()
	result.turn = turn
	result.actions = acts
	if is_over:
		return result
	# A stagger only costs the one action it forced to Wait above.
	for f in fighters:
		f.staggered = false

	var ambusher := 0 if acts[0].type == T.AMBUSH else (1 if acts[1].type == T.AMBUSH else -1)
	if ambusher >= 0:
		_resolve_ambush(ambusher, result)
	elif in_conflict:
		_resolve_conflict(acts, result)
	else:
		_resolve_movement(acts, result)
		for i in 2:
			_add_footing(fighters[i], DuelRules.regen_for(acts[i].type))

	_check_deaths(result)
	turn += 1
	return result


func _sanitize(id: int, a: PlayerAction) -> PlayerAction:
	for option in get_available_actions(id):
		if option.equals(a):
			return a
	return PlayerAction.wait()


func _resolve_ambush(id: int, result: TurnResult) -> void:
	var a := fighters[id]
	var b := other(id)
	# The ambusher lunges into the victim's tile; the victim's input is cancelled and they spin to face.
	a.cell = b.cell
	b.facing = Dirs.opposite(a.facing)
	b.hp -= DuelRules.AMBUSH_DAMAGE
	result.add(K.AMBUSHED, id, b.id, DuelRules.AMBUSH_DAMAGE)
	_start_conflict(result)
	_set_initiative(id, result)


## Conflict triangle: Attack beats Shove, Guard beats Attack, Shove beats Guard.
## Attack vs Attack goes to whoever holds the initiative, else it clashes harmlessly.
## Fleeing dodges Guard and Shove, but an Attack chases the fleer down.
## Every flee attempt leaves the fleer winded.
func _resolve_conflict(acts: Array[PlayerAction], result: TurnResult) -> void:
	# Exhaustion is judged on the Footing you went into the exchange with.
	var exhausted := [fighters[0].is_exhausted(), fighters[1].is_exhausted()]
	for i in 2:
		_add_footing(fighters[i], -cost_for(i, acts[i].type))
		fighters[i].free_action = false

	var t0 := acts[0].type
	var t1 := acts[1].type
	# Who came out ahead this exchange: a fighter id, STALEMATE, or -1 (no change).
	var round_winner := -1
	if t0 == T.ATTACK and t1 == T.ATTACK and initiative < 0:
		result.add(K.CLASHED, -1)
		round_winner = STALEMATE
	elif t0 == T.ATTACK and t1 == T.ATTACK:
		round_winner = initiative
		_hit(round_winner, _attack_damage(exhausted[round_winner]), result)
	elif t0 == t1 and t0 in [T.SHOVE, T.GUARD]:
		if t0 == T.SHOVE:
			result.add(K.SHOVES_CANCELLED, -1)
		round_winner = STALEMATE
	else:
		for i in 2:
			var w := _resolve_strike(i, acts[i], acts[1 - i], exhausted, result)
			if w >= 0:
				round_winner = w

	var caught := _resolve_flees(acts, exhausted, result)
	if caught >= 0:
		round_winner = caught
	if not in_conflict:
		return
	if round_winner == STALEMATE:
		_set_initiative(-1, result)
	elif round_winner >= 0:
		_set_initiative(round_winner, result)
	# A guard that held (wasn't shattered or shoved) sets up a free follow-up, and turns the
	# pair around the tile if a reposition was picked.
	if round_winner == STALEMATE:
		return
	for i in 2:
		if acts[i].type != T.GUARD or fighters[i].staggered or acts[1 - i].type == T.SHOVE:
			continue
		fighters[i].free_action = true
		if acts[i].veer != PlayerAction.Veer.NONE and fighters[0].cell == fighters[1].cell:
			_reposition(i, acts[i].veer, result)


## Fleers move; an attacker chases theirs down. Ends the conflict if they come apart.
## Returns the id of a fighter who caught a flee, else -1.
func _resolve_flees(acts: Array[PlayerAction], exhausted: Array, result: TurnResult) -> int:
	var plans := [_plan_for(fighters[0], acts[0]), _plan_for(fighters[1], acts[1])]
	var caught := -1
	for i in 2:
		if not acts[i].is_retreat():
			continue
		fighters[i].cell = plans[i].dest
		fighters[i].facing = plans[i].facing
		fighters[i].winded_until = turn + DuelRules.winded_turns
		result.add(K.RETREATED, i)

		if acts[1 - i].type != T.ATTACK:
			continue
		# Read the flee: follow them wherever they went, hit them, and keep them in the fight.
		# The fleer is caught from behind and spins round; both end up on one line.
		var chaser := other(i)
		chaser.cell = fighters[i].cell
		fighters[i].facing = Dirs.opposite(plans[i].move_dir)
		chaser.facing = plans[i].move_dir
		var dmg := _attack_damage(exhausted[chaser.id])
		fighters[i].hp -= dmg
		result.add(K.CAUGHT, chaser.id, i, dmg)
		caught = chaser.id

	if not acts[0].is_retreat() and not acts[1].is_retreat():
		return caught
	if fighters[0].cell != fighters[1].cell:
		_end_conflict(result)
	elif acts[0].is_retreat() and acts[1].is_retreat():
		# Both fled into the same tile: they run straight into each other again.
		_face_each_other_after_meeting(plans)
		result.add(K.CONFLICT_STARTED, -1)
	return caught


## Applies fighter i's action against the other's choice (mirrored cases are handled by the
## other call). Returns the id of whoever won the exchange because of it, else -1.
func _resolve_strike(i: int, mine: PlayerAction, theirs: PlayerAction, exhausted: Array, result: TurnResult) -> int:
	var me := fighters[i]
	var target := other(i)
	match mine.type:
		T.ATTACK:
			if theirs.is_retreat():
				return -1  # _resolve_flees chases them down
			if theirs.type != T.GUARD:
				_hit(i, _attack_damage(exhausted[i]), result)
				return i
			if exhausted[i]:
				# Telegraphed: the guard sees it coming and makes the attacker pay for it.
				_hold_guard(target.id, i, result)
				me.hp -= DuelRules.CHIP_DAMAGE
				result.add(K.PUNISHED, target.id, i, DuelRules.CHIP_DAMAGE)
				return target.id
			if exhausted[target.id] and rng.randf() < DuelRules.SHATTER_CHANCE:
				target.hp -= DuelRules.WEAK_DAMAGE
				target.staggered = true
				result.add(K.GUARD_SHATTERED, i, target.id, DuelRules.WEAK_DAMAGE)
				result.add(K.STAGGERED, target.id)
				return i
			_hold_guard(target.id, i, result)
			return target.id
		T.SHOVE:
			if theirs.type == T.GUARD:
				target.hp -= DuelRules.SHOVE_DAMAGE
				result.add(K.GUARD_BROKEN, i, target.id, DuelRules.SHOVE_DAMAGE)
				_add_footing(me, 1)  # landing on a guard refunds the shove
				_push(i, true, result)
				return i
			if theirs.type == T.WAIT:
				# Pushing someone already off balance hurts, but can't chain another stun.
				target.hp -= DuelRules.SHOVE_DAMAGE
				result.add(K.SHOVED, i, target.id, DuelRules.SHOVE_DAMAGE)
				_push(i, false, result)
				return i
			# vs Attack: the shove is stuffed (the attack's damage is applied by the other call).
			# vs Retreat: the shove meets air.
	return -1


const STALEMATE := -2


static func _attack_damage(telegraphed: bool) -> int:
	return DuelRules.WEAK_DAMAGE if telegraphed else DuelRules.ATTACK_DAMAGE


func _hit(attacker: int, dmg: int, result: TurnResult) -> void:
	other(attacker).hp -= dmg
	result.add(K.ATTACKED, attacker, 1 - attacker, dmg)


## Guard g stopped attacker a's swing: g gets BLOCK_GAIN in all (its +1 was paid up front)
## and a loses BLOCK_STRIP.
func _hold_guard(g: int, a: int, result: TurnResult) -> void:
	_add_footing(fighters[g], DuelRules.BLOCK_GAIN + DuelRules.footing_cost(T.GUARD))
	var stripped := mini(DuelRules.BLOCK_STRIP, fighters[a].footing)
	fighters[a].footing -= stripped
	result.add(K.BLOCKED, g, a, stripped)


## Shover i drives the other one backwards along i's facing: out of the tile if there is
## room behind them (the conflict breaks), else into the wall (stunned, when can_stun).
func _push(i: int, can_stun: bool, result: TurnResult) -> void:
	var target := other(i)
	var behind := target.cell.neighbor(fighters[i].facing)
	if behind != null:
		target.cell = behind
		result.add(K.SHOVED_AWAY, i, target.id)
		_end_conflict(result)
	elif can_stun:
		target.staggered = true
		result.add(K.PINNED, i, target.id)
		result.add(K.STAGGERED, target.id)


## Turns guard g 90 degrees toward veer and squares the foe up opposite, on the same tile.
## The foe's back ends up toward the guard's new facing: line them up against a wall.
func _reposition(g: int, veer: int, result: TurnResult) -> void:
	var f := fighters[g]
	f.facing = Dirs.left(f.facing) if veer == PlayerAction.Veer.LEFT else Dirs.right(f.facing)
	other(g).facing = Dirs.opposite(f.facing)
	result.add(K.REPOSITIONED, g, f.facing)


static func _add_footing(f: Fighter, amount: int) -> void:
	f.footing = clampi(f.footing + amount, 0, DuelRules.MAX_FOOTING)


func _set_initiative(id: int, result: TurnResult) -> void:
	if initiative == id:
		return
	initiative = id
	result.add(K.INITIATIVE, id)


func _resolve_movement(acts: Array[PlayerAction], result: TurnResult) -> void:
	var f := fighters
	var p := [_plan_for(f[0], acts[0]), _plan_for(f[1], acts[1])]

	# Crossing paths in a hallway: both bump and stop, facing each other.
	if p[0].moves and p[1].moves and p[0].dest == f[1].cell and p[1].dest == f[0].cell:
		f[0].facing = p[0].move_dir
		f[1].facing = p[1].move_dir
		result.add(K.BUMPED, 0, 1)
		result.add(K.BUMPED, 1, 0)
		_start_conflict(result)
		return

	for i in 2:
		var kind: int
		if p[i].moves:
			kind = K.MOVED
		elif acts[i].type == T.WAIT:
			kind = K.WAITED
		else:
			kind = K.TURNED
		f[i].cell = p[i].dest
		f[i].facing = p[i].facing
		result.add(kind, i)

	if f[0].cell != f[1].cell:
		return

	if p[0].moves and p[1].moves:
		_face_each_other_after_meeting(p)
	else:
		# One walked in on the other: the entrant keeps its heading, the stationary one turns to face.
		var mover := 0 if p[0].moves else 1
		f[mover].facing = p[mover].move_dir
		f[1 - mover].facing = Dirs.opposite(p[mover].move_dir)
	_start_conflict(result)


## Both entered the same tile: square them up on ONE line so they face exactly opposite ways.
## (Facing perpendicular would let a sideways flee land in the other's view with its back
## turned - a free ambush.) The lead turns toward where the other came from and the other faces
## the lead. Head-on meetings come out the same either way; for corner meetings the lead
## alternates by turn so neither player id is favoured.
func _face_each_other_after_meeting(p: Array) -> void:
	var lead := turn % 2
	var lead_facing := Dirs.opposite(p[1 - lead].move_dir)
	fighters[lead].facing = lead_facing
	fighters[1 - lead].facing = Dirs.opposite(lead_facing)


func _start_conflict(result: TurnResult) -> void:
	in_conflict = true
	result.add(K.CONFLICT_STARTED, -1)


func _end_conflict(result: TurnResult) -> void:
	in_conflict = false
	initiative = -1
	for f in fighters:
		f.free_action = false
	result.add(K.CONFLICT_ENDED, -1)
	# Squaring up in a corner can leave someone facing a wall. Turn them to an open side by a
	# fixed rule (right, left, back) that ignores where the fleer went, so it leaks nothing.
	for f in fighters:
		if not f.cell.is_open(f.facing):
			f.facing = DuelMap.first_open(f.cell, f.facing)
	# Breakaway: that auto-turn (or plain bad luck) must not hand out a free ambush the
	# instant someone escapes, so ambushes are off for the next turn.
	_no_ambush_turn = turn + 1


func _check_deaths(result: TurnResult) -> void:
	var d0 := fighters[0].is_dead()
	var d1 := fighters[1].is_dead()
	if not d0 and not d1:
		return
	if d0:
		result.add(K.DIED, 0)
	if d1:
		result.add(K.DIED, 1)
	is_over = true
	in_conflict = false
	initiative = -1
	winner = -1 if (d0 and d1) else (1 if d0 else 0)
