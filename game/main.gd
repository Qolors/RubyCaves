extends Node
## Turn loop for the local vs-computer demo:
## Planning (both pick one action, 10s clock) -> Resolving (simultaneous playback) -> Planning ...

enum Phase { PLANNING, RESOLVING, GAME_OVER }

const T := PlayerAction.Type
const K := TurnEvent.Kind
const LOCAL := 0
const BOT := 1
const RUBIES_FOR_WIN := 30
const RUBIES_FOR_LOSS := 15
const PROFILE_PATH := "user://profile.cfg"

var _map: DuelMap
var _state: DuelState
var _bot: BotBrain
var _hud: Hud
var _world: WorldView
var _dev: DevCapture

var _phase := Phase.PLANNING
var _time_left := 0.0
var _bot_action: PlayerAction
var _enemy_was_visible := false
## Spawn layout for the next match (see DuelState._init); advances every match so spawns rotate.
var _spawn_round := randi() % 8


func _ready() -> void:
	_map = DuelMap.from_json(FileAccess.get_file_as_string("res://data/figure8.json"))

	var layer := CanvasLayer.new()
	add_child(layer)
	_hud = Hud.new()
	layer.add_child(_hud)
	_world = WorldView.new()
	_hud.world_viewport.add_child(_world)
	_world.build_map(_map)

	_hud.action_chosen.connect(_on_local_chose)
	_hud.rematch_requested.connect(_start_match)
	_dev = DevCapture.new()
	_start_match()
	_dev.attach(self, _on_local_chose, func(): return _state, func(): return _phase == Phase.PLANNING)


func _start_match() -> void:
	var forced := _dev.spawn_override()
	_state = DuelState.new(_map, forced if forced >= 0 else _spawn_round)
	_spawn_round += 1
	_bot = BotBrain.new(BOT)
	_dev.apply_bot_override(_state)
	_hud.mini_map.state = _state
	_hud.hide_game_over()
	_hud.set_hp(DuelRules.MAX_HP, DuelRules.MAX_HP)
	_world.revive()
	var poses := WorldView.poses_for(_state, LOCAL)
	_world.snap_to(poses["cam"], poses["enemy"], _state.fighters[BOT].facing)
	_world.set_sight(WorldView.visible_cells(_state, LOCAL))
	_world.set_enemy_visible(_enemy_in_sight())
	_enemy_was_visible = false
	_hud.log_message("Find the enemy. Strike from behind!")
	_begin_planning()


func _begin_planning() -> void:
	_phase = Phase.PLANNING
	_time_left = DuelRules.TURN_SECONDS
	var scripted := _dev.next_bot_action()
	if scripted != null:
		_bot_action = scripted
	elif _dev.bot_idle:
		_bot_action = PlayerAction.wait()
	else:
		_bot_action = _bot.decide(_state)

	var visible := _enemy_in_sight()
	_world.set_enemy_visible(visible)
	if visible:
		_world.reappear()
	if visible and not _state.in_conflict and not _enemy_was_visible:
		_hud.log_message("Enemy spotted!")
	_enemy_was_visible = visible

	var staggered := _state.fighters[LOCAL].staggered
	_world.enemy_engaged = _state.in_conflict
	_hud.set_winded(_state.winded_turns_left(LOCAL), _state.winded_turns_left(BOT))
	_hud.set_footing(_state.fighters[LOCAL].footing, _state.fighters[BOT].footing, _state.fighters[LOCAL].free_action)
	_hud.set_initiative(_state.initiative == LOCAL, _state.initiative == BOT)
	_hud.show_actions(_state.get_available_actions(LOCAL, true), _state.in_conflict, _state.can_ambush(LOCAL), staggered)
	_hud.set_timer(_time_left)

	# A staggered player has no choice to make; don't sit on the clock.
	if staggered:
		get_tree().create_timer(1.0).timeout.connect(func(): _on_local_chose(PlayerAction.wait()))


func _enemy_in_sight() -> bool:
	var me := _state.fighters[LOCAL]
	var foe := _state.fighters[BOT]
	return _state.in_conflict or me.cell == foe.cell or DuelMap.sight_line(me.cell, me.facing).has(foe.cell)


func _process(delta: float) -> void:
	if _phase != Phase.PLANNING:
		return
	_time_left -= delta
	_hud.set_timer(_time_left)
	if _time_left <= 0.0:
		_hud.log_message("Too slow - you hesitate.")
		_on_local_chose(PlayerAction.wait())


func _on_local_chose(action: PlayerAction) -> void:
	if _phase != Phase.PLANNING:
		return
	_phase = Phase.RESOLVING
	_hud.lock(action)
	# The bot locked in at the start of the tick; a short beat before both actions play out.
	get_tree().create_timer(0.2).timeout.connect(func(): _resolve(action))


func _resolve(local: PlayerAction) -> void:
	var before := WorldView.poses_for(_state, LOCAL)
	var seen_before := _enemy_in_sight()
	var was_in_conflict := _state.in_conflict
	var before_turn := CombatReport.snapshot(_state)
	var result := _state.resolve(local, _bot_action)
	var after := WorldView.poses_for(_state, LOCAL)
	_world.set_sight(WorldView.visible_cells(_state, LOCAL), WorldView.STEP_DURATION)
	_world.set_enemy_visible(seen_before or _enemy_in_sight())
	_world.enemy_engaged = was_in_conflict or _state.in_conflict
	_bot.observe(result)

	var mine := result.actions[LOCAL].type
	var theirs := result.actions[BOT].type
	var i_moved := result.has(K.MOVED, LOCAL) or result.has(K.RETREATED, LOCAL) or result.has(K.AMBUSHED, LOCAL)
	if i_moved:
		_hud.sword.bob()
	if mine in [T.ATTACK, T.SHOVE]:
		_hud.sword.swing(false)
	if mine == T.AMBUSH:
		_hud.sword.swing(true)
	if mine == T.GUARD:
		_hud.sword.guard()

	var enemy_strikes := theirs in [T.ATTACK, T.SHOVE, T.AMBUSH]
	if theirs == T.GUARD:
		_world.show_enemy_guard()
	var enemy_lunges := enemy_strikes or result.has(K.BUMPED, BOT)

	# Fleeing never shows its direction: the fleer dissolves into shadow where it stood and is only
	# seen again next turn if it ended up in your sight line (e.g. a straight step back).
	# A caught flee isn't an escape: you chased them down, so you see exactly where they are.
	var enemy_fled := result.has(K.RETREATED, BOT) and not result.has(K.CAUGHT, LOCAL)
	var enemy_end: Vector3 = before["enemy"] if enemy_fled else after["enemy"]
	if enemy_fled:
		_world.vanish()
	if result.has(K.RETREATED, LOCAL) and not result.has(K.CAUGHT, BOT):
		_hud.flash_screen(Color(0.08, 0.0, 0.12), 0.6)

	get_tree().create_timer(0.18).timeout.connect(func():
		for e in result.events:
			match e.kind:
				K.ATTACKED, K.AMBUSHED, K.GUARD_BROKEN, K.SHOVED, K.CAUGHT, K.GUARD_SHATTERED, K.PUNISHED:
					if e.target == BOT:
						_world.flash_enemy()
					else:
						_hud.flash_screen(Color(1, 0, 0), 0.6 if e.kind == K.AMBUSHED else 0.4)
				K.CLASHED:
					_hud.flash_screen(Color(1.0, 0.9, 0.6), 0.45)
				K.BLOCKED:
					_hud.flash_screen(Color(0.4, 0.7, 1.0), 0.35)
		_hud.set_hp(_state.fighters[LOCAL].hp, _state.fighters[BOT].hp))

	_world.animate(before["cam"], after["cam"], before["enemy"], enemy_end, _state.fighters[BOT].facing,
		result.has(K.BUMPED, LOCAL), enemy_lunges, func():
			if enemy_fled:
				_world.snap_enemy(after["enemy"])
			_after_resolve(result, before_turn))


func _after_resolve(result: TurnResult, before_turn: Dictionary) -> void:
	var report := CombatReport.build(result, before_turn, _state, LOCAL)
	if report != null:
		_hud.show_report(report, _state.in_conflict)

	if not _state.is_over:
		_begin_planning()
		return

	_phase = Phase.GAME_OVER
	if _state.fighters[BOT].is_dead():
		_world.kill_enemy()
	var title := "DRAW"
	var color := Color.WHITE
	var delta := 0
	if _state.winner == LOCAL:
		title = "VICTORY"
		color = Color(1.0, 0.85, 0.2)
		delta = RUBIES_FOR_WIN
	elif _state.winner == BOT:
		title = "DEFEAT"
		color = Color(1.0, 0.25, 0.25)
		delta = -RUBIES_FOR_LOSS
	var total := maxi(0, _load_rubies() + delta)
	_save_rubies(total)
	_hud.show_game_over(title, color, "%s%d RUBIES\nTotal: %d rubies\n\nTurns: %d" % ["+" if delta > 0 else "", delta, total, result.turn])


static func _load_rubies() -> int:
	var cfg := ConfigFile.new()
	return int(cfg.get_value("profile", "rubies", 0)) if cfg.load(PROFILE_PATH) == OK else 0


static func _save_rubies(rubies: int) -> void:
	var cfg := ConfigFile.new()
	cfg.load(PROFILE_PATH)
	cfg.set_value("profile", "rubies", rubies)
	cfg.save(PROFILE_PATH)
