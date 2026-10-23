class_name DevCapture
extends RefCounted
## Dev-only automation, driven by user command-line args (after "--"):
##   --play=MoveForward,TurnLeft,...   plays these local actions, one per planning phase
##   --shot=C:/path/shot.png           saves a screenshot once the script finishes, then quits
##   --shotmid=0.3                     ...or captures that many seconds into the last action instead
##   --bot=Top_SW:East[:idle]          places the bot (optionally never acting)
##   --botplay=Wait,RetreatThrough     scripts the bot's actions (then it thinks for itself)
## Action tokens may carry a veer: MoveForward:Left.

var bot_idle := false
var _bot_step := 0


static func _arg(key: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % key):
			return a.split("=", true, 1)[1]
	return ""


static func _parse(token: String) -> PlayerAction:
	var parts := token.split(":")
	var veer := PlayerAction.Veer.NONE
	if parts.size() > 1:
		veer = PlayerAction.Veer.get(parts[1].to_upper(), PlayerAction.Veer.NONE)
	return PlayerAction.new(PlayerAction.type_from_name(parts[0]), veer)


func next_bot_action() -> PlayerAction:
	var script := _arg("botplay").split(",", false)
	if _bot_step >= script.size():
		return null
	_bot_step += 1
	return _parse(script[_bot_step - 1])


func apply_bot_override(state: DuelState) -> void:
	var spec := _arg("bot")
	if spec == "":
		return
	var parts := spec.split(":")
	state.fighters[1].cell = state.map.get_cell(parts[0])
	state.fighters[1].facing = Dirs.parse(parts[1])
	bot_idle = parts.size() > 2 and parts[2] == "idle"


func attach(host: Node, submit: Callable, get_state: Callable, is_planning: Callable) -> void:
	var shot := _arg("shot")
	var play := _arg("play").split(",", false)
	if shot == "" and play.is_empty():
		return

	var save_and_quit := func():
		host.get_viewport().get_texture().get_image().save_png(shot)
		print("[dev] saved ", shot)
		host.get_tree().quit()

	var step := [0]
	var idle := [0.0]
	var timer := Timer.new()
	timer.wait_time = 0.1
	timer.autostart = true
	host.add_child(timer)
	timer.timeout.connect(func():
		if not is_planning.call():
			# Script finished and the match ended (no more planning phases): shoot the game-over screen.
			idle[0] = idle[0] - 0.1 if step[0] >= play.size() else 0.0
			if shot != "" and idle[0] <= -1.5:
				timer.stop()
				save_and_quit.call()
			return
		idle[0] += 0.1
		if idle[0] < 0.4:
			return
		if step[0] < play.size():
			var action := _parse(play[step[0]])
			step[0] += 1
			var s: DuelState = get_state.call()
			print("[dev] turn %d: %s at %s facing %s; bot %s %s" % [s.turn, action.label(), s.fighters[0].cell,
				Dirs.name_of(s.fighters[0].facing), s.fighters[1].cell, Dirs.name_of(s.fighters[1].facing)])
			idle[0] = 0.0
			submit.call(action)
			if step[0] == play.size() and shot != "" and _arg("shotmid") != "":
				timer.stop()
				host.get_tree().create_timer(0.2 + _arg("shotmid").to_float()).timeout.connect(save_and_quit)
			return
		timer.stop()
		if shot != "":
			save_and_quit.call())
