class_name Hud
extends Control
## Portrait mobile HUD from the sketch: world viewport on top (enemy HP overlay), grey action panel
## with combat/movement tabs at the bottom, and the player's HP bar along the very bottom.

signal action_chosen(action: PlayerAction)
signal rematch_requested
## The player tapped the world view while a fight turn plays out.
signal fast_forward

const T := PlayerAction.Type
const RED := Color(1.0, 0.2, 0.2)
const BLUE := Color(0.2, 0.7, 1.0)
const PANEL_GREY := Color(0.33, 0.33, 0.33)
## Smallest text size anywhere in the HUD (VT323 runs small; below this it's unreadable on phones).
const SMALL := 20
const WINDED_COLOR := Color(1.0, 0.7, 0.3)
const FOOTING_COLOR := Color(1.0, 0.82, 0.2)
const INITIATIVE_COLOR := Color(0.55, 1.0, 0.55)

var world_viewport: SubViewport
var sword: SwordView
var mini_map: MiniMap
var fx: CombatFx

var _enemy_hp_label: Label
var _enemy_hp_fill: ColorRect
var _player_hp_label: Label
var _player_hp_fill: ColorRect
var _timer_label: Label
var _messages: Label
var _report: PanelContainer
var _report_matchup: Label
var _report_verdict: Label
var _report_lines: Label
## The report stays up through a fight; after one it fades out on its own.
var _report_sticky := false
var _report_time := 0.0
var _banner: Label
var _status: Label
var _flash: ColorRect
var _slots: Array[HBoxContainer] = []
var _combat_tab: OctagonTab
var _move_tab: OctagonTab
var _game_over: Control
var _game_over_title: Label
var _game_over_body: Label
var _enemy_winded: Label
var _player_winded: Label
var _enemy_footing: FootingPips
var _player_footing: FootingPips
var _enemy_initiative: Label
var _player_initiative: Label

var _tab := PlayerAction.Group.MOVEMENT
var _actions: Array[PlayerAction] = []
var _in_conflict := false
var _staggered := false
var _my_winded := 0
var _my_footing := DuelRules.MAX_FOOTING
var _foe_footing := DuelRules.MAX_FOOTING
var _my_free := false
var _my_initiative := false
var _foe_initiative := false
var _locked := false
var _log: Array = []  # [text, time]
var _clock := 0.0
## Screen shake for the 2D layer (sword and cut-ins), 0..1; the 3D camera shakes on its own.
var _trauma := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = _build_theme()

	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 0)
	add_child(root)

	root.add_child(_build_world_area())
	var sep := ColorRect.new()
	sep.color = Color.BLACK
	sep.custom_minimum_size = Vector2(0, 4)
	root.add_child(sep)
	root.add_child(_build_action_panel())
	root.add_child(_build_player_hp())

	_build_game_over()
	_select_tab(PlayerAction.Group.MOVEMENT)


# ---------- construction ----------

func _build_world_area() -> Control:
	var area := Control.new()
	area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	area.clip_contents = true
	area.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed or e is InputEventScreenTouch and e.pressed:
			fast_forward.emit())

	var container := SubViewportContainer.new()
	container.stretch = true
	container.stretch_shrink = 2
	container.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	area.add_child(container)
	world_viewport = SubViewport.new()
	world_viewport.msaa_3d = Viewport.MSAA_DISABLED
	world_viewport.handle_input_locally = false
	container.add_child(world_viewport)

	sword = SwordView.new()
	area.add_child(sword)

	_flash = ColorRect.new()
	_flash.color = Color(1, 0, 0, 0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	area.add_child(_flash)

	fx = CombatFx.new()
	area.add_child(fx)

	# Enemy HP (top-left), turn timer (top-right).
	var top := VBoxContainer.new()
	top.position = Vector2(12, 8)
	top.custom_minimum_size = Vector2(160, 0)
	top.add_theme_constant_override("separation", 2)
	area.add_child(top)
	var name_row := HBoxContainer.new()
	name_row.add_child(_label("ENEMY"))
	_enemy_winded = _winded_tag()
	name_row.add_child(_enemy_winded)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(spacer)
	_enemy_hp_label = _label("10/10")
	name_row.add_child(_enemy_hp_label)
	top.add_child(name_row)
	var bar := _bar(160, 10)
	_enemy_hp_fill = bar[1]
	top.add_child(bar[0])
	var footing_row := HBoxContainer.new()
	footing_row.add_theme_constant_override("separation", 6)
	footing_row.add_child(_label("FOOTING", SMALL, FOOTING_COLOR))
	_enemy_footing = FootingPips.new()
	_enemy_footing.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	footing_row.add_child(_enemy_footing)
	_enemy_initiative = _initiative_tag()
	footing_row.add_child(_enemy_initiative)
	top.add_child(footing_row)

	_messages = _label("", SMALL, Color(1.0, 0.85, 0.4))
	_messages.position = Vector2(12, 84)
	_messages.size = Vector2(300, 70)
	area.add_child(_messages)

	_build_report(area)

	_timer_label = _label("", 30)
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_timer_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_timer_label.position = Vector2(-70, 2)
	_timer_label.size = Vector2(60, 32)
	area.add_child(_timer_label)

	var map_toggle := Button.new()
	map_toggle.text = "MAP"
	map_toggle.toggle_mode = true
	map_toggle.focus_mode = Control.FOCUS_NONE
	map_toggle.add_theme_font_size_override("font_size", SMALL)
	map_toggle.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	map_toggle.position = Vector2(-54, 38)
	map_toggle.size = Vector2(44, 26)
	area.add_child(map_toggle)
	mini_map = MiniMap.new()
	mini_map.visible = false
	mini_map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mini_map.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	mini_map.position = Vector2(-90, 70)
	area.add_child(mini_map)
	map_toggle.toggled.connect(func(on: bool): mini_map.visible = on)

	_banner = _label("", 30)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.visible = false
	_banner.add_theme_color_override("font_outline_color", Color.BLACK)
	_banner.add_theme_constant_override("outline_size", 4)
	_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_banner.position = Vector2(-120, 150)
	_banner.size = Vector2(240, 34)
	area.add_child(_banner)
	return area


## Bottom of the world view: what both sides did last turn, who won and why, what changed.
func _build_report(area: Control) -> void:
	_report = PanelContainer.new()
	_report.visible = false
	_report.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.6)
	style.border_color = Color(1, 1, 1, 0.25)
	style.border_width_top = 2
	style.set_content_margin_all(6)
	_report.add_theme_stylebox_override("panel", style)
	_report.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_report.grow_vertical = Control.GROW_DIRECTION_BEGIN
	area.add_child(_report)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	_report.add_child(box)
	_report_matchup = _label("", SMALL, Color(0.75, 0.75, 0.75))
	_report_verdict = _label("", 24)
	_report_lines = _label("", SMALL)
	for l in [_report_matchup, _report_verdict, _report_lines]:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(l)


func _build_action_panel() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, 190)
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_GREY
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", style)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	panel.add_child(row)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 4)
	row.add_child(left)
	_status = _label("", SMALL, Color(0.9, 0.9, 0.9))
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(0, 40)
	left.add_child(_status)

	var grid := GridContainer.new()
	grid.columns = 3
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	left.add_child(grid)
	for i in 9:
		var slot := HBoxContainer.new()
		slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slot.custom_minimum_size = Vector2(0, 38)
		slot.add_theme_constant_override("separation", 2)
		grid.add_child(slot)
		_slots.append(slot)

	var tabs := VBoxContainer.new()
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	tabs.add_theme_constant_override("separation", 8)
	row.add_child(tabs)
	_combat_tab = OctagonTab.new()
	_combat_tab.icon_glyph = OctagonTab.Glyph.SWORD
	_combat_tab.base_color = RED
	_move_tab = OctagonTab.new()
	_move_tab.icon_glyph = OctagonTab.Glyph.FEET
	_move_tab.base_color = BLUE
	_combat_tab.pressed.connect(func(): _select_tab(PlayerAction.Group.COMBAT))
	_move_tab.pressed.connect(func(): _select_tab(PlayerAction.Group.MOVEMENT))
	tabs.add_child(_combat_tab)
	tabs.add_child(_move_tab)
	return panel


func _build_player_hp() -> Control:
	var bar := Control.new()
	bar.custom_minimum_size = Vector2(0, 26)
	var bg := ColorRect.new()
	bg.color = Color(0.25, 0.05, 0.05)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bar.add_child(bg)
	_player_hp_fill = ColorRect.new()
	_player_hp_fill.color = RED
	_player_hp_fill.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	bar.add_child(_player_hp_fill)
	_player_hp_label = _label("10/10", 26, Color.BLACK)
	_player_hp_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
	_player_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_player_hp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_player_hp_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bar.add_child(_player_hp_label)
	_player_winded = _winded_tag()
	_player_winded.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	_player_winded.offset_left = 6
	_player_winded.offset_right = 90
	_player_winded.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bar.add_child(_player_winded)
	_player_footing = FootingPips.new()
	_player_footing.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	_player_footing.position = Vector2(-44, -4)
	bar.add_child(_player_footing)
	_player_initiative = _initiative_tag()
	_player_initiative.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	_player_initiative.offset_left = -100
	_player_initiative.offset_right = -50
	_player_initiative.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bar.add_child(_player_initiative)
	return bar


func _build_game_over() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.75)
	dim.visible = false
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	_game_over = dim

	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.add_theme_constant_override("separation", 14)
	dim.add_child(box)

	_game_over_title = _label("", 48)
	_game_over_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_game_over_title)
	_game_over_body = _label("", 20)
	_game_over_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_game_over_body)

	var again := Button.new()
	again.text = "REMATCH"
	again.custom_minimum_size = Vector2(160, 44)
	again.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	again.add_theme_font_size_override("font_size", 22)
	again.pressed.connect(func(): rematch_requested.emit())
	box.add_child(again)


static func _label(text: String, font_size := 0, color := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	if font_size > 0:
		l.add_theme_font_size_override("font_size", font_size)
	if color != Color.WHITE:
		l.add_theme_color_override("font_color", color)
	return l


static func _bar(width: float, height: float) -> Array:
	var bar := Control.new()
	bar.custom_minimum_size = Vector2(width, height)
	var bg := ColorRect.new()
	bg.color = Color(0.25, 0.05, 0.05, 0.85)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bar.add_child(bg)
	var fill := ColorRect.new()
	fill.color = RED
	fill.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	bar.add_child(fill)
	return [bar, fill]


static func _winded_tag() -> Label:
	var tag := _label("", SMALL, WINDED_COLOR)
	tag.visible = false
	return tag


static func _initiative_tag() -> Label:
	var tag := _label("INIT", SMALL, INITIATIVE_COLOR)
	tag.visible = false
	return tag


static func _build_theme() -> Theme:
	# Browsers can't see system fonts, so the pixel font ships with the game (VT323, OFL licence).
	var font: FontFile = load("res://assets/fonts/VT323-Regular.ttf")
	font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	font.hinting = TextServer.HINTING_NONE
	font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	var t := Theme.new()
	t.default_font = font
	t.default_font_size = 24

	var box := func(bg: Color, border: Color) -> StyleBoxFlat:
		var sb := StyleBoxFlat.new()
		sb.bg_color = bg
		sb.border_color = border
		sb.set_border_width_all(2)
		sb.set_content_margin_all(2)
		return sb
	t.set_stylebox("normal", "Button", box.call(Color(0.16, 0.16, 0.18), Color(0.7, 0.7, 0.7)))
	t.set_stylebox("hover", "Button", box.call(Color(0.24, 0.24, 0.28), Color.WHITE))
	t.set_stylebox("pressed", "Button", box.call(Color(0.9, 0.75, 0.2), Color.WHITE))
	t.set_stylebox("disabled", "Button", box.call(Color(0.2, 0.2, 0.2), Color(0.3, 0.3, 0.3)))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", Color.BLACK)
	t.set_color("font_disabled_color", "Button", Color(0.45, 0.45, 0.45))
	t.set_color("font_color", "Label", Color.WHITE)
	t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.8))
	t.set_constant("shadow_offset_x", "Label", 1)
	t.set_constant("shadow_offset_y", "Label", 1)
	return t


# ---------- runtime API ----------

## Turns of "can't flee" left for each side; both are public knowledge.
func set_winded(mine: int, enemy: int) -> void:
	_my_winded = mine
	_player_winded.visible = mine > 0
	_player_winded.text = " WINDED %d" % mine
	_enemy_winded.visible = enemy > 0
	_enemy_winded.text = " WINDED %d" % enemy


## Footing pips for both sides; both are public knowledge. my_free: our next conflict action
## costs nothing (a guard held). Call before show_actions.
func set_footing(mine: int, enemy: int, my_free: bool) -> void:
	_my_footing = mine
	_foe_footing = enemy
	_my_free = my_free
	_player_footing.value = mine
	_enemy_footing.value = enemy


## Who holds the initiative (wins Attack vs Attack). Public knowledge. Call before show_actions.
func set_initiative(mine: bool, enemy: bool) -> void:
	_my_initiative = mine
	_foe_initiative = enemy
	_player_initiative.visible = mine
	_enemy_initiative.visible = enemy


func set_hp(mine: int, enemy: int) -> void:
	_player_hp_label.text = "%d/%d" % [maxi(0, mine), DuelRules.MAX_HP]
	_enemy_hp_label.text = "%d/%d" % [maxi(0, enemy), DuelRules.MAX_HP]
	_player_hp_fill.anchor_right = clampf(mine / float(DuelRules.MAX_HP), 0, 1)
	_enemy_hp_fill.anchor_right = clampf(enemy / float(DuelRules.MAX_HP), 0, 1)
	_player_hp_fill.offset_right = 0
	_enemy_hp_fill.offset_right = 0


func set_timer(seconds: float) -> void:
	var s := ceili(maxf(0.0, seconds))
	_timer_label.text = "%ds" % s
	_timer_label.add_theme_color_override("font_color", RED if s <= 3 else Color.WHITE)


func log_message(text: String) -> void:
	_log.append([text, _clock])


## Shows a turn's combat report. sticky: keep it up (still fighting) instead of fading it out.
func show_report(report: CombatReport, sticky: bool) -> void:
	_report_matchup.text = report.matchup
	_report_verdict.text = report.verdict
	_report_verdict.add_theme_color_override("font_color", report.color)
	_report_lines.text = "\n".join(report.lines)
	_report_lines.visible = not report.lines.is_empty()
	_report.modulate.a = 1.0
	_report.visible = true
	_report_sticky = sticky
	_report_time = _clock


func hide_report() -> void:
	_report.visible = false


## While a fight turn plays out, the banner and message log step aside for the cut-ins.
func set_cinematic(on: bool) -> void:
	for c in [_banner, _messages]:
		create_tween().tween_property(c, "modulate:a", 0.0 if on else 1.0, 0.15)


## Jolts the 2D layer (sword, cut-ins); stacks with shake already running.
func shake(amount: float) -> void:
	_trauma = minf(1.0, _trauma + amount)


func flash_screen(color: Color, alpha: float) -> void:
	_flash.color = Color(color, alpha)
	create_tween().tween_property(_flash, "color:a", 0.0, 0.5)


## Starts a new planning phase with the actions currently legal for the local player.
func show_actions(actions: Array[PlayerAction], in_conflict: bool, can_ambush: bool, staggered: bool) -> void:
	_actions = actions
	_in_conflict = in_conflict
	_staggered = staggered
	_locked = false
	_move_tab.disabled = in_conflict
	_combat_tab.alert = can_ambush

	if in_conflict:
		_select_tab(PlayerAction.Group.COMBAT)
	elif _tab == PlayerAction.Group.COMBAT and not can_ambush:
		_select_tab(PlayerAction.Group.MOVEMENT)
	else:
		_select_tab(_tab)

	if staggered:
		_set_banner("STAGGERED!", Color(1.0, 0.6, 0.2))
	elif in_conflict:
		_set_banner("!! CONFLICT !!", RED)
	elif can_ambush:
		_set_banner("AMBUSH READY", Color(1.0, 0.85, 0.2))
	else:
		_set_banner("", Color.WHITE)


func lock(chosen: PlayerAction) -> void:
	_locked = true
	_status.text = "LOCKED: %s" % chosen.label()
	for slot in _slots:
		for b in slot.get_children():
			if b is Button:
				b.disabled = true


func show_game_over(title: String, color: Color, body: String) -> void:
	_game_over_title.text = title
	_game_over_title.add_theme_color_override("font_color", color)
	_game_over_body.text = body
	_game_over.visible = true
	_set_banner("", Color.WHITE)


func hide_game_over() -> void:
	_game_over.visible = false


func _set_banner(text: String, color: Color) -> void:
	_banner.visible = text != ""
	_banner.text = text
	_banner.add_theme_color_override("font_color", color)


func _select_tab(tab: int) -> void:
	if _in_conflict:
		tab = PlayerAction.Group.COMBAT
	_tab = tab
	_combat_tab.selected = tab == PlayerAction.Group.COMBAT
	_move_tab.selected = tab == PlayerAction.Group.MOVEMENT
	_rebuild_slots()


func _rebuild_slots() -> void:
	for slot in _slots:
		for child in slot.get_children():
			slot.remove_child(child)
			child.queue_free()

	var visible_actions := _actions.filter(func(a: PlayerAction): return a.group() == _tab)
	for a in visible_actions:
		var b := Button.new()
		var siblings := _actions.filter(func(o: PlayerAction): return o.type == a.type).size()
		b.text = _short_label(a, siblings)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.focus_mode = Control.FOCUS_NONE
		var cost := DuelRules.footing_cost(a.type) if _in_conflict else 0
		if cost > 0 and _my_free:
			cost = 0
		b.disabled = _locked or (DuelRules.needs_footing(a.type) and cost > _my_footing)
		b.clip_text = true
		var tint := Color.WHITE
		match a.type:
			T.AMBUSH, T.ATTACK: tint = Color(1.0, 0.4, 0.4)
			T.GUARD: tint = Color(0.5, 0.8, 1.0)
			T.SHOVE: tint = Color(1.0, 0.75, 0.3)
		b.add_theme_color_override("font_color", tint)
		b.pressed.connect(func(): action_chosen.emit(a))
		if cost != 0:
			# Footing cost in the corner: -1 spends a pip, +1 gives one back.
			var tag := _label("%+d" % -cost, 18, FOOTING_COLOR)
			tag.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
			tag.position = Vector2(-18, -5)
			tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
			if b.disabled:
				tag.modulate.a = 0.4
			b.add_child(tag)
		_slots[_slot_of(a)].add_child(b)

	# Keep the 3x3 layout stable: empty slots get an invisible spacer.
	for slot in _slots:
		if slot.get_child_count() == 0:
			var spacer := Control.new()
			spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			slot.add_child(spacer)

	if _locked:
		return
	var combat := _tab == PlayerAction.Group.COMBAT
	if _staggered:
		_status.text = "Off balance! You lose this turn."
	elif combat and _in_conflict and _my_free:
		_status.text = "Your guard held: your next move is FREE. Set them up!"
	elif combat and _in_conflict and _foe_footing <= 0:
		_status.text = "Enemy is EXHAUSTED: its swing is weak and its guard may shatter."
	elif combat and _in_conflict and _my_footing <= 0:
		_status.text = "EXHAUSTED: your swing is telegraphed. GUARD to regain footing."
	elif combat and _in_conflict and _my_winded > 0:
		_status.text = "WINDED: you can't flee for %d more turn(s). Stand and fight!" % _my_winded
	elif combat and _in_conflict and _my_initiative:
		_status.text = "You hold the INITIATIVE: you win a trade of attacks."
	elif combat and _in_conflict and _foe_initiative:
		_status.text = "Enemy holds the INITIATIVE: it wins a trade of attacks."
	elif combat and _in_conflict:
		_status.text = "ATK>SHOVE>GUARD>ATK. Fleeing dodges a guard or shove, but not an ATTACK."
	elif combat and visible_actions.is_empty():
		_status.text = "No target. Get 1 tile behind or beside the enemy to AMBUSH."
	elif combat:
		_status.text = "Enemy's back is turned! AMBUSH cancels their move (-4)."
	elif _actions.any(func(a: PlayerAction): return a.type == T.AMBUSH):
		_status.text = "Enemy exposed! Tap the SWORD tab to AMBUSH."
	elif visible_actions.any(func(a: PlayerAction): return a.veer != PlayerAction.Veer.NONE):
		_status.text = "Junction: go straight, or step in and hook L/R down the side passage."
	else:
		_status.text = "Choose your move."


static func _slot_of(a: PlayerAction) -> int:
	if a.type == T.GUARD and a.veer != PlayerAction.Veer.NONE:
		return 6 if a.veer == PlayerAction.Veer.LEFT else 8  # reposition guards flank the dash
	match a.type:
		T.TURN_LEFT, T.GUARD: return 0
		T.MOVE_FORWARD, T.AMBUSH, T.ATTACK: return 1
		T.TURN_RIGHT, T.SHOVE: return 2
		T.MOVE_LEFT, T.RETREAT_LEFT: return 3
		T.STEP_BACK, T.RETREAT_BACK: return 4
		T.MOVE_RIGHT, T.RETREAT_RIGHT: return 5
		T.TURN_AROUND: return 6
		T.WAIT, T.RETREAT_THROUGH: return 7
	return 8


## Button text. Plain ASCII arrows so it renders with the bundled pixel font everywhere.
## siblings: how many variants of this move share the slot (straight / hook L / hook R).
static func _short_label(a: PlayerAction, siblings := 1) -> String:
	var label := ""
	match a.type:
		T.TURN_LEFT: label = "TURN L"
		T.TURN_RIGHT: label = "TURN R"
		T.MOVE_FORWARD: label = "^ FWD"
		T.MOVE_LEFT: label = "< LEFT"
		T.MOVE_RIGHT: label = "RIGHT >"
		T.STEP_BACK: label = "v BACK"
		T.TURN_AROUND: label = "TURN 180"
		T.WAIT: label = "WAIT"
		T.AMBUSH: label = "AMBUSH!"
		T.ATTACK: label = "ATTACK"
		T.GUARD: label = "GUARD"
		T.SHOVE: label = "SHOVE"
		T.RETREAT_LEFT: label = "< FLEE"
		T.RETREAT_BACK: label = "v BACK"
		T.RETREAT_RIGHT: label = "FLEE >"
		T.RETREAT_THROUGH: label = "^ DASH"
	if a.type == T.GUARD:
		match a.veer:
			PlayerAction.Veer.LEFT: return "< GUARD"
			PlayerAction.Veer.RIGHT: return "GUARD >"
		return label
	var arrow := ">"
	if a.type in [T.MOVE_FORWARD, T.RETREAT_THROUGH]:
		arrow = "^"
	elif a.type in [T.MOVE_LEFT, T.RETREAT_LEFT]:
		arrow = "<"
	elif a.type in [T.STEP_BACK, T.RETREAT_BACK]:
		arrow = "v"
	if a.veer == PlayerAction.Veer.NONE:
		return arrow if siblings > 1 else label
	# Variants share the slot: arrow of the move plus which way to turn on arrival.
	return "%s%s" % [arrow, "L" if a.veer == PlayerAction.Veer.LEFT else "R"]


func _process(delta: float) -> void:
	_clock += delta
	_trauma = maxf(0.0, _trauma - delta * 1.6)
	var jolt := Vector2(randf_range(-1, 1), randf_range(-1, 1)) * _trauma * _trauma * 14.0
	sword.jolt = jolt
	fx.position = jolt
	_log = _log.filter(func(l): return _clock - l[1] <= 5.0)
	while _log.size() > 4:
		_log.pop_front()
	_messages.text = "\n".join(_log.map(func(l): return l[0]))
	# A finished fight's report lingers for a few seconds, then fades.
	if _report.visible and not _report_sticky:
		var age := _clock - _report_time
		_report.modulate.a = clampf(7.0 - age, 0.0, 1.0)
		_report.visible = age < 7.0
