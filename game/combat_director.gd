class_name CombatDirector
extends Node
## Stages a fighting turn like an anime exchange instead of playing everything at once:
##   1. VS card: both picks slam in while the enemy holds the pose of its move (wind-up, guard up...)
##   2. verdict stamp: who won the exchange, and the rule that decided it
##   3. the exchange itself: strike, block or hit animations with action-camera impacts
##   4. the detailed report
## Turns that walk into a fight (ambush, face-off) play the walk first. Plain walking skips all this.
## Tapping the world view fast-forwards the rest of the sequence.

const T := PlayerAction.Type
const K := TurnEvent.Kind
const LOCAL := 0
const BOT := 1
## Playback speed after a tap.
const FAST := 3.0
const YOU_HURT := Color(1.0, 0.15, 0.1)
const SPARK := Color(0.45, 0.75, 1.0)
const STEEL := Color(1.0, 0.95, 0.7)
## Where on screen our own hits land (0..1 of the view): low centre, where the enemy's blade meets us.
const MY_POINT := Vector2(0.5, 0.62)

## Camera and enemy reached their rail poses (see _glide).
signal arrived

var _world: WorldView
var _hud: Hud
var _speed := 1.0
var _running := false


func _init(world: WorldView, hud: Hud) -> void:
	_world = world
	_hud = hud


func _ready() -> void:
	_hud.fast_forward.connect(func():
		if _running and _speed < FAST:
			_speed = FAST
			Engine.time_scale = FAST)


## Plays one resolved fighting turn, then calls done. before/after: WorldView.poses_for around the turn.
func play(s: DuelState, r: TurnResult, report: CombatReport, before_turn: Dictionary,
		before: Dictionary, after: Dictionary, done: Callable) -> void:
	_running = true
	_hud.hide_report()
	_hud.set_cinematic(true)
	var mine := r.actions[LOCAL].type
	var theirs := r.actions[BOT].type
	var enemy_fled := r.has(K.RETREATED, BOT) and not r.has(K.CAUGHT, LOCAL)
	var walk_in: bool = not before_turn["in_conflict"]

	# Walking into the fight: finish the step first, then freeze the moment for the cut-in.
	if walk_in:
		if r.has(K.MOVED, LOCAL) or r.has(K.AMBUSHED, LOCAL):
			_hud.sword.bob()
		_glide(s, before, after, after["enemy"], r.has(K.BUMPED, LOCAL), r.has(K.BUMPED, BOT))
		await arrived
		before = after

	# 1. VS card.
	_hud.fx.letterbox(true)
	_world.cam_to("cam_zoom", -9.0, 1.1, Tween.TRANS_SINE)
	_pre_pose(theirs)
	if report.my_verb != "":
		_hud.fx.versus(report.my_verb, report.foe_verb)
		await _wait(0.6)
		_hud.fx.hide_versus()
		await _wait(0.08)

	# 2. Verdict stamp.
	_hud.fx.stamp(report.stamp, report.color, report.outcome, report.verdict)
	_hud.fx.speed_lines(0.45, report.color)
	_hud.shake(0.35)
	_world.shake(0.3)
	await _wait(0.8)
	_hud.fx.hide_stamp()
	await _wait(0.1)

	# 3. The exchange.
	_world.cam_to("cam_zoom", 0.0, 0.25)
	var glide_done := [walk_in]
	if not walk_in:
		arrived.connect(func(): glide_done[0] = true, CONNECT_ONE_SHOT)
		_glide(s, before, after, before["enemy"] if enemy_fled else after["enemy"], false, theirs in [T.ATTACK, T.SHOVE])
	_wind_up(r, mine, theirs, walk_in, enemy_fled)
	await _wait(0.15)
	await _impact(s, r, before_turn, mine, theirs)
	while not glide_done[0]:
		await get_tree().process_frame
	if enemy_fled:
		_world.snap_enemy(after["enemy"])
	if s.is_over:
		await _finale(s)
	else:
		await _wait(0.35)
		if theirs == T.GUARD and not r.has(K.GUARD_BROKEN) and not r.has(K.GUARD_SHATTERED):
			_world.play_enemy("guard_down", 12.0)

	# 4. Report.
	_hud.fx.letterbox(false)
	_hud.set_cinematic(false)
	_world.cam_settle()
	if not s.is_over:
		_hud.show_report(report, s.in_conflict)
	_running = false
	_speed = 1.0
	Engine.time_scale = 1.0
	done.call()


## The enemy shows its pick while the VS card is up: anticipation before the hit.
func _pre_pose(theirs: int) -> void:
	match theirs:
		T.ATTACK, T.AMBUSH: _world.play_enemy("windup", 12.0, true)
		T.GUARD, T.SHOVE: _world.play_enemy("guard_up", 12.0, true)
		T.WAIT: _world.play_enemy("stunned", 1.0, true)
		_: _world.enemy_idle()


## The moves start: swings, lunges, guards, vanishing flees.
func _wind_up(r: TurnResult, mine: int, theirs: int, walk_in: bool, enemy_fled: bool) -> void:
	match mine:
		T.ATTACK, T.SHOVE:
			_hud.sword.swing(false)
			_world.cam_to("cam_push", 0.3, 0.12)
		T.AMBUSH:
			_hud.sword.swing(true)
			_world.cam_to("cam_push", 0.45, 0.12)
		T.GUARD:
			_hud.sword.guard()
	if theirs in [T.ATTACK, T.AMBUSH]:
		_world.play_enemy("strike", 14.0)
	if walk_in and theirs in [T.AMBUSH, T.SHOVE, T.ATTACK]:
		_world.knock_enemy(-0.5, 0.3)  # it's already in our face after the walk: lunge from there
	if enemy_fled:
		_world.vanish()
		_hud.fx.speed_lines(0.3, Color(0.5, 0.3, 0.7))
	if r.has(K.RETREATED, LOCAL) and not r.has(K.CAUGHT, BOT):
		_hud.flash_screen(Color(0.08, 0.0, 0.12), 0.6)
		_hud.fx.speed_lines(0.4, Color(0.5, 0.3, 0.7))
	if r.has(K.REPOSITIONED):
		var left := r.actions[LOCAL if r.has(K.REPOSITIONED, LOCAL) else BOT].veer == PlayerAction.Veer.LEFT
		_world.cam_kick("cam_roll", 0.14 if left else -0.14, 0.5)


## The moment blades meet: hitstop, flashes, shake, sparks, damage numbers, reaction animations.
func _impact(s: DuelState, r: TurnResult, before_turn: Dictionary, mine: int, theirs: int) -> void:
	var my_dmg: int = before_turn["hp"][LOCAL] - s.fighters[LOCAL].hp
	var foe_dmg: int = before_turn["hp"][BOT] - s.fighters[BOT].hp
	var foe_point := _world.enemy_screen_point()
	var heavy := r.has(K.GUARD_SHATTERED) or r.has(K.AMBUSHED) or r.has(K.PINNED)
	var stop := 0.0
	_world.cam_to("cam_push", 0.0, 0.3)

	if r.has(K.CLASHED) or r.has(K.SHOVES_CANCELLED):
		var mid := (foe_point + MY_POINT) / 2
		_hud.fx.burst(mid, STEEL, 18)
		_hud.flash_screen(STEEL, 0.45)
		_shake(0.5)
		_world.cam_kick("cam_push", -0.25, 0.4)
		_world.knock_enemy(0.3)
		stop = 0.1
	elif r.has(K.BLOCKED, BOT) or r.has(K.PUNISHED, BOT):
		# Our swing rings off its guard and we recoil.
		_world.play_enemy("block_hit", 12.0)
		_hud.fx.burst(foe_point, SPARK, 16)
		_hud.flash_screen(SPARK, 0.3)
		_shake(0.35)
		_world.cam_kick("cam_push", -0.3, 0.45)
		_world.cam_kick("cam_roll", 0.06, 0.4)
		stop = 0.07
	elif r.has(K.BLOCKED, LOCAL) or r.has(K.PUNISHED, LOCAL):
		# Its swing rings off our guard and it recoils.
		_hud.fx.burst(MY_POINT, SPARK, 16)
		_hud.flash_screen(SPARK, 0.35)
		_shake(0.35)
		_world.knock_enemy(0.35)
		_world.cam_kick("cam_zoom", -6.0, 0.4)
		stop = 0.07
	elif r.has(K.GUARD_BROKEN, LOCAL) or r.has(K.SHOVED, LOCAL):
		_world.play_enemy("hit", 14.0)
		_world.knock_enemy(0.6, 0.5)
		_shake(0.55)
		_world.cam_kick("cam_zoom", -8.0, 0.4)
	elif r.has(K.GUARD_BROKEN, BOT) or r.has(K.SHOVED, BOT):
		_hud.flash_screen(Color(1.0, 0.7, 0.3), 0.35)
		_shake(0.6)
		_world.cam_kick("cam_push", -0.45, 0.6)
		_world.cam_kick("cam_roll", -0.15, 0.6)

	if foe_dmg > 0:
		_world.play_enemy("hit", 14.0)
		_world.flash_enemy()
		_world.knock_enemy(0.45 if heavy else 0.3)
		_hud.fx.slash(foe_point)
		_hud.fx.burst(foe_point, Color(1.0, 0.3, 0.2), 14)
		_hud.fx.pop_number("-%d" % foe_dmg, foe_point + Vector2(0.18, -0.08), Color(1.0, 0.9, 0.3))
		_hud.flash_screen(Color.WHITE, 0.3)
		_shake(0.7 if heavy else 0.5)
		_world.cam_kick("cam_zoom", -14.0 if heavy else -10.0, 0.5)
		stop = maxf(stop, 0.14 if heavy else 0.09)
	if my_dmg > 0:
		_hud.flash_screen(YOU_HURT, 0.6 if heavy else 0.45)
		_hud.fx.slash(MY_POINT, YOU_HURT)
		_hud.fx.pop_number("-%d" % my_dmg, MY_POINT + Vector2(-0.2, 0.0), YOU_HURT)
		_shake(0.8 if heavy else 0.6)
		_world.cam_kick("cam_push", -0.3, 0.5)
		_world.cam_kick("cam_roll", 0.18 if randf() < 0.5 else -0.18, 0.6)
		stop = maxf(stop, 0.12 if heavy else 0.08)
	if r.has(K.STAGGERED) or r.has(K.PINNED):
		_hud.fx.speed_lines(0.3, Color(1.0, 0.7, 0.3))

	_hud.set_hp(s.fighters[LOCAL].hp, s.fighters[BOT].hp)
	if stop > 0.0:
		await _hitstop(stop)


## The last blow: slow motion, then the loser goes down.
func _finale(s: DuelState) -> void:
	Engine.time_scale = 0.3
	if s.fighters[BOT].is_dead():
		_world.kill_enemy()
		_world.cam_to("cam_zoom", -16.0, 0.5)
		_hud.fx.speed_lines(0.6, Color(1.0, 0.85, 0.2))
	if s.fighters[LOCAL].is_dead():
		# We fall: the view tips over and drops to the floor.
		_world.cam_to("cam_roll", 1.2, 0.7, Tween.TRANS_BOUNCE)
		_world.cam_to("cam_drop", -0.8, 0.7, Tween.TRANS_BOUNCE)
		_hud.flash_screen(YOU_HURT, 0.7)
	await get_tree().create_timer(0.9, true, false, true).timeout
	Engine.time_scale = _speed


func _shake(amount: float) -> void:
	_hud.shake(amount)
	_world.shake(amount)


## Freezes the action for a beat (real time) so the hit lands.
func _hitstop(seconds: float) -> void:
	Engine.time_scale = 0.05
	await get_tree().create_timer(seconds, true, false, true).timeout
	Engine.time_scale = _speed


## Waits on game time, so a fast-forward shortens it.
func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


## Glides camera and enemy along the rails; emits arrived when they get there.
func _glide(s: DuelState, before: Dictionary, after: Dictionary, enemy_end: Vector3, bump: bool, lunge: bool) -> void:
	_world.animate(before["cam"], after["cam"], before["enemy"], enemy_end, s.fighters[BOT].facing, bump, lunge,
		func(): arrived.emit())
