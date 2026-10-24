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


func can_afford(id: int, type: int) -> bool:
	return DuelRules.focus_cost(type) <= fighters[id].focus


## Legal actions for a fighter. include_unaffordable also lists conflict actions they lack the
## Focus for, so the HUD can show them greyed out; resolve() only ever accepts affordable ones.
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
		list.append(PlayerAction.new(T.SHOVE))
		# Pursuing only makes sense if the other one is able to run (and has the Focus to).
		if DuelRules.pursue_enabled and _can_flee(other(id)) and can_afford(1 - id, T.RETREAT_BACK):
			list.append(PlayerAction.new(T.PURSUE))
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
		for i in 2:
			fighters[i].focus = clampi(fighters[i].focus - DuelRules.focus_cost(acts[i].type), 0, DuelRules.MAX_FOCUS)
		_resolve_conflict(acts, result)
	else:
		_resolve_movement(acts, result)
		for f in fighters:
			f.focus = mini(f.focus + DuelRules.FOCUS_REGEN, DuelRules.MAX_FOCUS)

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


## Conflict triangle: Attack beats Shove, Guard beats Attack, Shove beats Guard.
## Attack vs Attack clashes harmlessly. Fleeing dodges all of those, but Pursue catches a flee
## (and loses to everything else). Every flee attempt leaves the fleer winded.
func _resolve_conflict(acts: Array[PlayerAction], result: TurnResult) -> void:
	if acts[0].type == T.ATTACK and acts[1].type == T.ATTACK:
		result.add(K.CLASHED, -1)
	elif acts[0].type == T.SHOVE and acts[1].type == T.SHOVE:
		result.add(K.SHOVES_CANCELLED, -1)
	else:
		for i in 2:
			_resolve_strike(i, acts[i].type, acts[1 - i], result)

	var plans := [_plan_for(fighters[0], acts[0]), _plan_for(fighters[1], acts[1])]
	for i in 2:
		if not acts[i].is_retreat():
			continue
		fighters[i].cell = plans[i].dest
		fighters[i].facing = plans[i].facing
		fighters[i].winded_until = turn + DuelRules.winded_turns
		result.add(K.RETREATED, i)

		if acts[1 - i].type != T.PURSUE:
			continue
		# Read the flee: follow them wherever they went, hit them, and keep them in the fight.
		# The fleer is caught from behind and spins round; both end up on one line.
		var chaser := other(i)
		chaser.cell = fighters[i].cell
		fighters[i].facing = Dirs.opposite(plans[i].move_dir)
		chaser.facing = plans[i].move_dir
		fighters[i].hp -= DuelRules.PURSUE_DAMAGE
		result.add(K.CAUGHT, chaser.id, i, DuelRules.PURSUE_DAMAGE)

	if not acts[0].is_retreat() and not acts[1].is_retreat():
		return

	if fighters[0].cell != fighters[1].cell:
		in_conflict = false
		result.add(K.CONFLICT_ENDED, -1)
		# Squaring up in a corner can leave someone facing a wall. Turn them to an open side by a
		# fixed rule (right, left, back) that ignores where the fleer went, so it leaks nothing.
		for f in fighters:
			if not f.cell.is_open(f.facing):
				f.facing = DuelMap.first_open(f.cell, f.facing)
		# Breakaway: that auto-turn (or plain bad luck) must not hand out a free ambush the
		# instant someone escapes, so ambushes are off for the next turn.
		_no_ambush_turn = turn + 1
	elif acts[0].is_retreat() and acts[1].is_retreat():
		# Both fled into the same tile: they run straight into each other again.
		_face_each_other_after_meeting(plans)
		result.add(K.CONFLICT_STARTED, -1)


## Applies fighter i's offensive action against the other's choice
## (mirrored cases are handled by the other call).
func _resolve_strike(i: int, mine: int, theirs: PlayerAction, result: TurnResult) -> void:
	var target := other(i)
	match mine:
		T.ATTACK:
			if theirs.is_retreat():
				result.add(K.ATTACK_DODGED, i, target.id)
			elif theirs.type == T.GUARD:
				fighters[i].staggered = true
				result.add(K.BLOCKED, target.id, i)
				result.add(K.STAGGERED, i)
			else:
				target.hp -= DuelRules.ATTACK_DAMAGE
				result.add(K.ATTACKED, i, target.id, DuelRules.ATTACK_DAMAGE)
		T.PURSUE:
			# Lunging after someone who didn't run. vs Attack the attack lands (other call);
			# vs Shove the shove handles it; vs Guard the pursuer over-commits into the block.
			if theirs.type == T.GUARD:
				fighters[i].staggered = true
				result.add(K.OVEREXTENDED, i)
				result.add(K.STAGGERED, i)
		T.SHOVE:
			if theirs.type == T.GUARD:
				target.hp -= DuelRules.SHOVE_DAMAGE
				target.staggered = true
				result.add(K.GUARD_BROKEN, i, target.id, DuelRules.SHOVE_DAMAGE)
				result.add(K.STAGGERED, target.id)
			elif theirs.type == T.PURSUE:
				# Shoving someone who is charging in knocks them clean off balance.
				target.hp -= DuelRules.SHOVE_DAMAGE
				target.staggered = true
				result.add(K.SHOVED, i, target.id, DuelRules.SHOVE_DAMAGE)
				result.add(K.OVEREXTENDED, target.id)
				result.add(K.STAGGERED, target.id)
			elif theirs.type == T.WAIT:
				# Pushing someone who is already off balance hurts, but can't chain another stagger.
				target.hp -= DuelRules.SHOVE_DAMAGE
				result.add(K.SHOVED, i, target.id, DuelRules.SHOVE_DAMAGE)
			# vs Attack: the shove is stuffed (the attack's damage is applied by the other call).
			# vs Retreat: the shove meets air.


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
	winner = -1 if (d0 and d1) else (1 if d0 else 0)
