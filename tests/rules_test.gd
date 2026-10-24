extends SceneTree
## Rules regression test + bot-vs-bot balance sims (port of the C# rule harness).
## Run:  Godot_console.exe --headless --path . --script res://tests/rules_test.gd
## Add `-- --quick` to skip the long simulations.

const T := PlayerAction.Type
const V := PlayerAction.Veer
const K := TurnEvent.Kind

var json := ""
var fails := 0


func _init() -> void:
	json = FileAccess.get_file_as_string("res://data/figure8.json")
	run_rules()
	if not "--quick" in OS.get_cmdline_user_args():
		run_soak()
		run_ab()
		run_focus_ab()
	print("ALL PASSED" if fails == 0 else "%d FAILED" % fails)
	quit(1 if fails > 0 else 0)


func check(ok: bool, what: String) -> void:
	if ok:
		print("ok: " + what)
	else:
		fails += 1
		print("FAIL: " + what)


func make(c0: String, f0: int, c1: String, f1: int) -> DuelState:
	var s := DuelState.new(DuelMap.from_json(json))
	s.fighters[0].cell = s.map.get_cell(c0)
	s.fighters[0].facing = f0
	s.fighters[1].cell = s.map.get_cell(c1)
	s.fighters[1].facing = f1
	return s


func A(t: int, v: int = V.NONE) -> PlayerAction:
	return PlayerAction.new(t, v)


func W() -> PlayerAction:
	return PlayerAction.wait()


func has_action(list: Array[PlayerAction], a: PlayerAction) -> bool:
	return list.any(func(o: PlayerAction): return o.equals(a))


func retreats(list: Array[PlayerAction]) -> Array:
	return list.filter(func(o: PlayerAction): return o.is_retreat())


func first_of(list: Array[PlayerAction], t: int) -> PlayerAction:
	for o in list:
		if o.type == t:
			return o
	return null


## p0 in Top_SW facing South (wall) after ambushing p1, who faces North; p1 HP reset to 10.
func conf() -> DuelState:
	var c := make("Top_W", Dirs.SOUTH, "Top_SW", Dirs.EAST)
	c.resolve(A(T.AMBUSH), W())
	c.fighters[1].hp = 10
	return c


func run_rules() -> void:
	var m := DuelMap.from_json(json)
	check(m.cells.size() == 14 and m.get_cell("Bottom_N") == m.get_cell("Top_SW"), "14 cells, merged alias")
	check(m.spawns[0]["cell"].id == "Top_NW" and m.spawns[0]["facing"] == Dirs.SOUTH, "spawn p1")
	for c in m.cells:
		check(c.open_count() >= 2, "%s has >=2 openings (%d)" % [c.id, c.open_count()])

	var s := make("Top_N", Dirs.EAST, "Bottom_SE", Dirs.NORTH)
	s.resolve(A(T.MOVE_FORWARD), W())
	check(s.fighters[0].cell.id == "Top_NE" and s.fighters[0].facing == Dirs.SOUTH, "corner auto-turn Top_N->Top_NE faces South")

	s = make("Top_W", Dirs.SOUTH, "Bottom_SE", Dirs.NORTH)
	var acts := s.get_available_actions(0)
	check(has_action(acts, A(T.MOVE_FORWARD, V.LEFT)) and has_action(acts, A(T.MOVE_FORWARD, V.RIGHT)), "T-junction offers veer L/R")
	check(not acts.any(func(a): return a.type in [T.TURN_LEFT, T.TURN_RIGHT, T.MOVE_LEFT]), "corridor has no side options")
	s.resolve(A(T.MOVE_FORWARD, V.RIGHT), W())
	check(s.fighters[0].cell.id == "Top_SW" and s.fighters[0].facing == Dirs.WEST, "veer right from south faces West")

	s = make("Top_W", Dirs.SOUTH, "Top_SW", Dirs.EAST)
	check(s.can_ambush(0), "ambush on side")
	var r := s.resolve(A(T.AMBUSH), A(T.MOVE_FORWARD))
	check(s.fighters[1].hp == 6 and s.in_conflict and s.fighters[1].cell.id == "Top_SW" and s.fighters[0].cell.id == "Top_SW", "ambush: -4, input cancelled, conflict same tile")
	check(s.fighters[1].facing == Dirs.NORTH, "victim turns to face ambusher")
	s.resolve(A(T.ATTACK), A(T.ATTACK))
	check(s.fighters[0].hp == 10 and s.fighters[1].hp == 6 and s.in_conflict, "attack vs attack clashes, no damage")
	s.resolve(A(T.ATTACK), retreats(s.get_available_actions(1))[0])
	check(s.fighters[1].hp == 6 and not s.in_conflict, "retreat dodges and ends conflict")

	s = conf()
	s.resolve(A(T.ATTACK), A(T.SHOVE))
	check(s.fighters[1].hp == 8 and s.fighters[0].hp == 10, "attack beats shove")
	s = conf()
	r = s.resolve(A(T.ATTACK), A(T.GUARD))
	check(s.fighters[1].hp == 10 and s.fighters[0].staggered and r.has(K.BLOCKED, 1), "guard blocks attack, attacker staggered")
	var only := s.get_available_actions(0)
	check(only.size() == 1 and only[0].equals(W()), "staggered fighter can only wait")
	s.resolve(A(T.ATTACK), A(T.ATTACK))
	check(s.fighters[0].hp == 8 and not s.fighters[0].staggered, "punish staggered player; stagger clears")
	s = conf()
	s.resolve(A(T.SHOVE), A(T.GUARD))
	check(s.fighters[1].hp == 9 and s.fighters[1].staggered, "shove breaks guard: -1 + stagger")
	s.resolve(A(T.SHOVE), A(T.ATTACK))
	check(s.fighters[1].hp == 8 and not s.fighters[1].staggered, "shove on waiting target: -1, no stagger chain")
	s = conf()
	r = s.resolve(A(T.SHOVE), A(T.SHOVE))
	check(r.has(K.SHOVES_CANCELLED) and s.fighters[1].hp == 10, "shove vs shove cancels")
	s = conf()
	s.resolve(A(T.GUARD), A(T.GUARD))
	check(s.fighters[0].hp == 10 and s.fighters[1].hp == 10 and s.in_conflict, "guard vs guard nothing")

	s = make("Top_W", Dirs.SOUTH, "Top_SW", Dirs.NORTH)
	check(not s.can_ambush(0) and not s.can_ambush(1), "no ambush when facing each other")
	r = s.resolve(A(T.MOVE_FORWARD, V.LEFT), A(T.MOVE_FORWARD))
	check(s.in_conflict and r.has(K.BUMPED) and s.fighters[0].cell.id == "Top_W", "hallway swap -> bump conflict, positions held")
	r = s.resolve(A(T.ATTACK), A(T.ATTACK))
	check(s.in_conflict and s.fighters[0].hp == 10 and r.has(K.CLASHED), "bump conflict persists through a clash")

	s = make("Top_NW", Dirs.EAST, "Top_NE", Dirs.WEST)
	s.resolve(A(T.MOVE_FORWARD), A(T.MOVE_FORWARD))
	check(s.in_conflict and s.fighters[0].cell.id == "Top_N" and s.fighters[0].facing == Dirs.EAST and s.fighters[1].facing == Dirs.WEST, "meet in middle tile facing each other")

	s = make("Top_NW", Dirs.EAST, "Top_N", Dirs.EAST)
	s.resolve(A(T.AMBUSH), W())
	check(s.in_conflict and s.fighters[1].hp == 6, "ambush from directly behind")

	# --- one-line facing + dash past ---
	for start_turn in [1, 2]:
		s = make("Top_N", Dirs.EAST, "Top_E", Dirs.NORTH)
		if start_turn == 2:
			s.resolve(W(), W())
		s.resolve(A(T.MOVE_FORWARD), A(T.MOVE_FORWARD))
		check(s.in_conflict and s.fighters[0].cell.id == "Top_NE" and s.fighters[0].facing == Dirs.opposite(s.fighters[1].facing), "corner meet faces exactly opposite (turn parity %d)" % start_turn)
		for fleer in [0, 1]:
			for flee in retreats(s.get_available_actions(fleer)):
				var t := make("Top_N", Dirs.EAST, "Top_E", Dirs.NORTH)
				if start_turn == 2:
					t.resolve(W(), W())
				t.resolve(A(T.MOVE_FORWARD), A(T.MOVE_FORWARD))
				if fleer == 0:
					t.resolve(flee, W())
				else:
					t.resolve(W(), flee)
				check(not t.can_ambush(1 - fleer), "  flee %s by p%d gives no free ambush" % [flee.label(), fleer])

	s = conf()
	var p1_dash := s.get_available_actions(1).filter(func(a): return a.type == T.RETREAT_THROUGH)
	check(p1_dash.size() == 1, "dash past offered when the way beyond is open")
	s.resolve(A(T.ATTACK), p1_dash[0])
	check(not s.in_conflict and s.fighters[1].cell.id == "Top_W" and s.fighters[1].hp == 10, "dash past dodges and goes through")
	check(not s.can_ambush(0) and not s.can_ambush(1), "after dash past nobody has an ambush")

	s = make("Top_W", Dirs.SOUTH, "Top_SW", Dirs.NORTH)
	s.resolve(A(T.MOVE_FORWARD, V.LEFT), A(T.MOVE_FORWARD))
	var dash0 := s.get_available_actions(1).filter(func(a): return a.type == T.RETREAT_THROUGH)
	check(dash0.size() == 1, "dash past available from hallway bump")
	s.resolve(W(), dash0[0])
	check(s.fighters[1].cell.id == "Top_NW" and not s.in_conflict, "bump dash slips past to the cell beyond the enemy")

	for flee_type in [T.RETREAT_LEFT, T.RETREAT_THROUGH, T.RETREAT_RIGHT]:
		var t := conf()
		var flee := first_of(t.get_available_actions(1), flee_type)
		if flee == null:
			continue
		t.resolve(A(T.ATTACK), flee)
		check(not t.in_conflict and t.fighters.all(func(f): return f.cell.is_open(f.facing)), "after %s: nobody faces a wall" % flee.label())
		check(not t.can_ambush(0) and not t.can_ambush(1) and t.in_breakaway(), "after %s: breakaway turn, no ambush" % flee.label())

	# --- Pursue & Winded ---
	for flee_type in [T.RETREAT_LEFT, T.RETREAT_RIGHT, T.RETREAT_THROUGH]:
		var t := conf()
		var flee := first_of(t.get_available_actions(1), flee_type)
		if flee == null:
			continue
		var rr := t.resolve(A(T.PURSUE), flee)
		check(t.in_conflict and t.fighters[0].cell == t.fighters[1].cell and t.fighters[1].hp == 8 and rr.has(K.CAUGHT, 0), "pursue catches %s: -2, conflict continues in new cell" % flee.label())
		check(t.fighters[0].facing == Dirs.opposite(t.fighters[1].facing), "  caught pair faces opposite")
		check(retreats(t.get_available_actions(1)).is_empty(), "  caught fleer is winded: no flee options")
		check(first_of(t.get_available_actions(0), T.PURSUE) == null, "  no pursue offered vs a winded foe")
	s = conf()
	r = s.resolve(A(T.PURSUE), A(T.GUARD))
	check(s.fighters[0].staggered and r.has(K.OVEREXTENDED, 0) and s.fighters[1].hp == 10, "guard beats pursue: pursuer staggered")
	s = conf()
	s.resolve(A(T.PURSUE), A(T.ATTACK))
	check(s.fighters[0].hp == 8, "attack beats pursue: -2")
	s = conf()
	s.resolve(A(T.PURSUE), A(T.SHOVE))
	check(s.fighters[0].hp == 9 and s.fighters[0].staggered, "shove beats pursue: -1 + stagger")
	s = conf()
	s.resolve(A(T.ATTACK), retreats(s.get_available_actions(1))[0])
	check(not s.in_conflict and s.winded_turns_left(1) == 3, "escaping leaves the fleer winded for 3 turns")
	s.resolve(W(), W())
	s.resolve(W(), W())
	s.resolve(W(), W())
	check(s.winded_turns_left(1) == 0, "winded wears off after 3 turns")

	# --- Focus ---
	s = conf()
	check(s.fighters[0].focus == 3 and s.fighters[1].focus == 3, "ambush turn costs no focus")
	s.resolve(A(T.ATTACK), A(T.GUARD))
	check(s.fighters[0].focus == 1 and s.fighters[1].focus == 3, "attack spends 2 focus, guard caps at 3")
	s = conf()
	s.resolve(A(T.ATTACK), A(T.ATTACK))
	check(s.fighters[0].focus == 1 and s.fighters[1].focus == 1, "clash: both spend 2")
	check(first_of(s.get_available_actions(0), T.ATTACK) == null, "can't attack on 1 focus")
	check(first_of(s.get_available_actions(0, true), T.ATTACK) != null, "  ...but the HUD list still shows it (greyed)")
	r = s.resolve(A(T.ATTACK), A(T.GUARD))
	check(not r.has(K.BLOCKED) and s.fighters[0].focus == 2 and s.fighters[1].focus == 2, "unaffordable attack becomes a wait (+1); guard +1")
	s = conf()
	s.resolve(A(T.SHOVE), A(T.SHOVE))
	check(s.fighters[0].focus == 2, "shove spends 1")
	s = conf()
	s.fighters[1].focus = 0
	var broke := s.get_available_actions(1)
	check(broke.size() == 1 and broke[0].type == T.GUARD, "0 focus: guard is the only option")
	check(first_of(s.get_available_actions(0), T.PURSUE) == null, "no pursue vs a foe too tired to flee")
	r = s.resolve(A(T.SHOVE), A(T.ATTACK))
	check(r.has(K.SHOVED, 0) and s.fighters[1].hp == 9 and s.fighters[1].focus == 1, "broke fighter's attack becomes a wait (+1) and gets shoved")
	s = conf()
	var flee1: PlayerAction = retreats(s.get_available_actions(1))[0]
	s.resolve(A(T.GUARD), flee1)
	check(not s.in_conflict and s.fighters[1].focus == 2, "fleeing spends 1")
	s.resolve(W(), W())
	check(s.fighters[1].focus == 3, "focus refills out of conflict")


func run_soak() -> void:
	var games := 3000
	var draws := 0
	var max_turns := 0
	var total_turns := 0
	var ambushes := 0
	var unfinished := 0
	var free_ambush := 0
	var wall_stare := 0
	var map := DuelMap.from_json(json)
	for g in games:
		var st := DuelState.new(map)
		var b0 := BotBrain.new(0, g)
		var b1 := BotBrain.new(1, g + 99999)
		while not st.is_over and st.turn < 500:
			var was_conflict := st.in_conflict
			var res := st.resolve(b0.decide(st), b1.decide(st))
			b0.observe(res)
			b1.observe(res)
			if was_conflict and not st.in_conflict and not st.is_over and (st.can_ambush(0) or st.can_ambush(1)):
				free_ambush += 1
			if not st.in_conflict and not st.is_over and st.fighters.any(func(f): return not f.cell.is_open(f.facing)):
				wall_stare += 1
			if res.has(K.AMBUSHED):
				ambushes += 1
		if not st.is_over:
			unfinished += 1
		if st.is_over and st.winner < 0:
			draws += 1
		total_turns += st.turn
		max_turns = maxi(max_turns, st.turn)
	print("soak: %d games, avg turns %.1f, max %d, draws %d, unfinished %d, ambushes/game %.2f, free ambush after flee %d, wall stares %d" % [
		games, total_turns / float(games), max_turns, draws, unfinished, ambushes / float(games), free_ambush, wall_stare])
	check(draws == 0 and unfinished == 0 and free_ambush == 0 and wall_stare == 0, "soak invariants")


func run_ab() -> void:
	var map := DuelMap.from_json(json)
	for cfg in [[false, 0], [true, 3]]:
		DuelRules.pursue_enabled = cfg[0]
		DuelRules.winded_turns = cfg[1]
		var spam_wins := 0
		var norm_wins := 0
		var dr := 0
		var turns := 0
		for g in 4000:
			var st := DuelState.new(map)
			var spam := g % 2
			var bots := [BotBrain.new(0, g, 0.7 if spam == 0 else 0.0), BotBrain.new(1, g + 7777, 0.7 if spam == 1 else 0.0)]
			while not st.is_over and st.turn < 400:
				var res := st.resolve(bots[0].decide(st), bots[1].decide(st))
				bots[0].observe(res)
				bots[1].observe(res)
			turns += st.turn
			if not st.is_over or st.winner < 0:
				dr += 1
			elif st.winner == spam:
				spam_wins += 1
			else:
				norm_wins += 1
		print("A/B pursue=%s winded=%d: flee-spammer wins %.1f%%, normal %.1f%%, draw/unfinished %.1f%%, avg turns %.1f" % [
			cfg[0], cfg[1], spam_wins / 40.0, norm_wins / 40.0, dr / 40.0, turns / 4000.0])
	DuelRules.pursue_enabled = true
	DuelRules.winded_turns = 3


## Same bot on both sides, but one reads Focus (punishes a foe who can't attack) and one doesn't.
## If Focus adds skill, reading it must win clearly more than half the time.
func run_focus_ab() -> void:
	var map := DuelMap.from_json(json)
	var games := 4000
	var aware_wins := 0
	var draws := 0
	var turns := 0
	for g in games:
		var st := DuelState.new(map)
		var aware := g % 2
		var bots := [BotBrain.new(0, g, 0.0, aware == 0), BotBrain.new(1, g + 4242, 0.0, aware == 1)]
		while not st.is_over and st.turn < 400:
			var res := st.resolve(bots[0].decide(st), bots[1].decide(st))
			bots[0].observe(res)
			bots[1].observe(res)
		turns += st.turn
		if not st.is_over or st.winner < 0:
			draws += 1
		elif st.winner == aware:
			aware_wins += 1
	var rate := aware_wins * 100.0 / games
	print("focus A/B: focus-reading bot wins %.1f%%, draw/unfinished %.1f%%, avg turns %.1f" % [rate, draws * 100.0 / games, turns / float(games)])
	check(rate > 55.0, "reading focus is a real edge")
