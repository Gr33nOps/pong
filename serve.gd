extends CanvasLayer
# Title screen and between-points serve prompt.

@onready var root = $Root
@onready var title_label = $Root/title
@onready var subtitle_label = $Root/subtitle
@onready var option1_label = $Root/option1
@onready var option2_label = $Root/option2
@onready var option1_bg = $Root/option1Bg
@onready var option2_bg = $Root/option2Bg
@onready var hint_label = $Root/hint
@onready var devices_label = $Root/devices
@onready var panel = $Root/Dimmer
@onready var serve_title = $Root/serveTitle
@onready var serve_back = $Root/serveBack
@onready var _style_sel: StyleBox = $Root/option1Bg.get_theme_stylebox("panel")
@onready var _style_idle: StyleBox = $Root/option2Bg.get_theme_stylebox("panel")

enum Step { MODE, DIFF, SIDE }

var cursor := 0
var _step := Step.MODE
var _fade_tween: Tween = null
var _ai_serve_timer := 0.0
var _serve_ready := false
var option3_bg: Panel
var option3_label: Label
var back_label: Label
var _pointer_down := false
var _pointer_start := Vector2.ZERO
var _pointer_dragged := false
const TAP_SLACK := 28.0


func _ready() -> void:
	visible = false
	layer = 20
	root.modulate = Color(1, 1, 1, 0)
	GameState.serving_changed.connect(_on_serving_changed)
	GameState.game_over.connect(_on_game_over)
	GameState.mode_changed.connect(_on_mode_changed)
	GameState.rematch_started.connect(_on_rematch_started)
	Players.player_assigned.connect(_on_player_assigned)
	Players.player_released.connect(_on_player_released)
	GameState.colorblind_changed.connect(func(_e: bool) -> void: _update_devices_label())
	option1_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	option2_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	option1_bg.mouse_filter = Control.MOUSE_FILTER_STOP
	option2_bg.mouse_filter = Control.MOUSE_FILTER_STOP
	option1_bg.gui_input.connect(_on_option_gui.bind(0))
	option2_bg.gui_input.connect(_on_option_gui.bind(1))
	_make_option3()
	_update_devices_label()
	GameState.back_pressed.connect(_on_back_pressed)
	serve_title.mouse_filter = Control.MOUSE_FILTER_STOP
	hint_label.mouse_filter = Control.MOUSE_FILTER_STOP
	serve_title.gui_input.connect(_on_serve_gui)
	hint_label.gui_input.connect(_on_serve_gui)
	_make_back_label()
	devices_label.mouse_filter = Control.MOUSE_FILTER_STOP
	devices_label.gui_input.connect(_on_devices_gui)


func _make_option3() -> void:
	option3_bg = Panel.new()
	option3_bg.mouse_filter = Control.MOUSE_FILTER_STOP
	option3_bg.add_theme_stylebox_override("panel", _style_idle)
	option3_label = Label.new()
	option3_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	option3_label.add_theme_font_size_override("font_size", 18)
	option3_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(option3_bg)
	root.add_child(option3_label)
	option3_bg.gui_input.connect(_on_option_gui.bind(2))
	option3_bg.visible = false
	option3_label.visible = false


func _make_back_label() -> void:
	back_label = Label.new()
	back_label.position = Vector2(36.0, 20.0)
	back_label.size = Vector2(160.0, 40.0)
	back_label.text = "<  BACK"
	back_label.add_theme_font_size_override("font_size", 14)
	back_label.add_theme_color_override("font_color", Color(0.82, 0.86, 0.9, 1))
	back_label.mouse_filter = Control.MOUSE_FILTER_STOP
	back_label.gui_input.connect(_on_back_gui)
	root.add_child(back_label)
	back_label.visible = false


func _on_option_gui(event: InputEvent, index: int) -> void:
	if GameState.mode_selected or GameState.paused:
		return
	if index >= _option_count():
		return
	if event is InputEventMouseMotion:
		if cursor != index:
			cursor = index
			_update_menu_highlight()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		cursor = index
		_update_menu_highlight()
		_confirm_menu()
	elif event is InputEventScreenTouch and event.pressed:
		cursor = index
		_update_menu_highlight()
		_confirm_menu()


func _process(delta: float) -> void:
	if GameState.paused or not GameState.serving or GameState.is_game_over:
		return
	if GameState.mode_selected:
		_handle_serve_input(delta)
		if _serve_ready:
			hint_label.modulate.a = 0.7 + sin(Time.get_ticks_msec() * 0.007) * 0.3
		return
	_handle_menu_input()


func _handle_menu_input() -> void:
	if _step != Step.MODE and (Input.is_action_just_pressed("ui_cancel") or Players.is_pause_just_pressed()):
		_go_back()
		return
	if _step == Step.MODE:
		if Input.is_action_just_pressed("mode_1"):
			_confirm_mode(Constants.MODE_AI)
			return
		if Input.is_action_just_pressed("mode_2"):
			_confirm_mode(Constants.MODE_2P)
			return
	if Input.is_action_just_pressed("colorblind"):
		GameState.toggle_colorblind()
		SFX.play("ui", 1.2)
		return
	var nav := 0
	if Input.is_action_just_pressed("up") or Input.is_action_just_pressed("ui_up"):
		nav = -1
	elif Input.is_action_just_pressed("down") or Input.is_action_just_pressed("ui_down"):
		nav = 1
	elif Players.is_nav_up_just_pressed():
		nav = -1
	elif Players.is_nav_down_just_pressed():
		nav = 1
	if nav != 0:
		var count := _option_count()
		cursor = (cursor + nav + count) % count
		SFX.play("ui")
		_update_menu_highlight()
	var adj := _adjust_dir()
	if adj != 0 and _step != Step.MODE:
		var count := _option_count()
		var next := (cursor + adj + count) % count
		if next != cursor:
			cursor = next
			SFX.play("ui")
			_update_menu_highlight()
	if Input.is_action_just_pressed("stop") or Input.is_action_just_pressed("ui_accept") or Players.is_confirm_just_pressed():
		_confirm_menu()


func _adjust_dir() -> int:
	if Input.is_action_just_pressed("ui_left"):
		return -1
	if Input.is_action_just_pressed("ui_right"):
		return 1
	return 0


func _option_count() -> int:
	return 3 if _step == Step.DIFF else 2


func _diff_cursor() -> int:
	if GameState.ai_difficulty <= 0.8:
		return 0
	if GameState.ai_difficulty >= 0.97:
		return 2
	return 1


func _confirm_menu() -> void:
	match _step:
		Step.SIDE:
			_confirm_side()
		Step.DIFF:
			_confirm_diff()
		_:
			_confirm_mode(Constants.MODE_AI if cursor == 0 else Constants.MODE_2P)


func _confirm_mode(mode: int) -> void:
	SFX.play("confirm")
	GameState.select_mode(mode)
	if mode == Constants.MODE_AI:
		_step = Step.DIFF
		cursor = _diff_cursor()
	else:
		_goto_side()
		return
	_refresh()


func _confirm_diff() -> void:
	var steps := [Constants.DIFFICULTY_EASY, Constants.DIFFICULTY_NORMAL, Constants.DIFFICULTY_HARD]
	GameState.set_ai_difficulty(steps[clampi(cursor, 0, 2)])
	SFX.play("confirm")
	_goto_side()


func _goto_side() -> void:
	_step = Step.SIDE
	cursor = 0 if GameState.player_is_left else 1
	_refresh()


func _confirm_side() -> void:
	SFX.play("confirm")
	_step = Step.MODE
	GameState.select_side(cursor == 0)


func _on_back_gui(event: InputEvent) -> void:
	if GameState.mode_selected or GameState.paused:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_go_back()
	elif event is InputEventScreenTouch and event.pressed:
		_go_back()


func _on_devices_gui(event: InputEvent) -> void:
	if GameState.mode_selected or GameState.paused or _step == Step.SIDE:
		return
	var tapped := false
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		tapped = true
	elif event is InputEventScreenTouch and event.pressed:
		tapped = true
	if not tapped:
		return
	var local_x := 0.0
	if event is InputEventMouseButton or event is InputEventScreenTouch:
		local_x = event.position.x
	if local_x < devices_label.size.x * 0.5:
		GameState.toggle_colorblind()
		SFX.play("ui", 1.2)
	else:
		SFX.toggle_mute()
	_update_devices_label()


func _on_back_pressed() -> void:
	if GameState.mode_selected or GameState.paused or GameState.is_game_over:
		return
	if _step != Step.MODE:
		_go_back()
	elif OS.has_feature("mobile"):
		get_tree().quit()


func _on_serve_gui(event: InputEvent) -> void:
	if not GameState.mode_selected or GameState.paused or GameState.is_game_over:
		return
	if not GameState.serving or GameState.is_cpu_serving() or not _serve_ready:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_launch_player_serve()
	elif event is InputEventScreenTouch and event.pressed:
		_launch_player_serve()


func _go_back() -> void:
	SFX.play("ui")
	if _step == Step.SIDE and GameState.mode == Constants.MODE_AI:
		_step = Step.DIFF
		cursor = _diff_cursor()
	else:
		_step = Step.MODE
		cursor = 0 if GameState.mode == Constants.MODE_AI else 1
	_refresh()


func _handle_serve_input(delta: float) -> void:
	if not _serve_ready:
		return
	var ai_serving: bool = GameState.is_cpu_serving()
	if ai_serving:
		_ai_serve_timer += delta
		if _ai_serve_timer >= 0.7:
			GameState.set_serving(false)
		return
	if Input.is_action_just_pressed("stop") or Input.is_action_just_pressed("ui_accept") or Players.is_confirm_just_pressed():
		_launch_player_serve()


func _launch_player_serve() -> void:
	if not _serve_ready or not GameState.serving or GameState.is_cpu_serving():
		return
	SFX.play("confirm", 1.15)
	GameState.set_serving(false)


func _input(event: InputEvent) -> void:
	if GameState.paused or GameState.is_game_over or not GameState.serving or not GameState.mode_selected:
		_pointer_down = false
		_pointer_dragged = false
		return
	if GameState.is_cpu_serving() or not _serve_ready:
		return
	var pos := Vector2.ZERO
	var is_press := false
	var is_release := false
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		pos = event.position
		is_press = event.pressed
		is_release = not event.pressed
	elif event is InputEventScreenTouch:
		pos = event.position
		is_press = event.pressed
		is_release = not event.pressed
	elif event is InputEventMouseMotion and _pointer_down:
		if event.position.distance_to(_pointer_start) > TAP_SLACK:
			_pointer_dragged = true
		return
	elif event is InputEventScreenDrag and _pointer_down:
		if event.position.distance_to(_pointer_start) > TAP_SLACK:
			_pointer_dragged = true
		return
	else:
		return
	if pos.y < Constants.HUD_HEIGHT:
		return
	if is_press:
		_pointer_down = true
		_pointer_dragged = false
		_pointer_start = pos
	elif is_release and _pointer_down:
		_pointer_down = false
		if not _pointer_dragged:
			_launch_player_serve()


func _on_serving_changed(serving: bool) -> void:
	_ai_serve_timer = 0.0
	_serve_ready = false
	_pointer_down = false
	if serving:
		visible = true
		_refresh()
		_fade_in()
		if GameState.mode_selected:
			await get_tree().create_timer(0.22, true).timeout
			if is_instance_valid(self) and GameState.serving:
				_serve_ready = true
	else:
		_fade_out()


func _fade_in() -> void:
	if _fade_tween:
		_fade_tween.kill()
	_fade_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_fade_tween.tween_property(root, "modulate:a", 1.0, Constants.MENU_FADE_IN).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _fade_out() -> void:
	if _fade_tween:
		_fade_tween.kill()
	_fade_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_fade_tween.tween_property(root, "modulate:a", 0.0, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_fade_tween.finished.connect(_on_fade_out_done)


func _on_fade_out_done() -> void:
	visible = false
	serve_title.visible = false
	serve_back.visible = false


func _on_mode_changed(_mode: int) -> void:
	_refresh()


func _on_rematch_started() -> void:
	visible = true
	_refresh()
	_fade_in()
	_serve_ready = false
	await get_tree().create_timer(0.22, true).timeout
	if is_instance_valid(self) and GameState.serving:
		_serve_ready = true


func _on_game_over(_winner: String) -> void:
	visible = false
	serve_title.visible = false
	serve_back.visible = false
	if _fade_tween:
		_fade_tween.kill()
	root.modulate.a = 0.0


func _on_player_assigned(_player: int, _device: int) -> void:
	_update_devices_label()


func _on_player_released(_player: int) -> void:
	_update_devices_label()


func _refresh() -> void:
	var in_menu := not GameState.mode_selected
	title_label.visible = in_menu
	subtitle_label.visible = in_menu
	panel.visible = in_menu
	devices_label.visible = in_menu
	if back_label:
		back_label.visible = in_menu and _step != Step.MODE
	serve_title.visible = not in_menu
	serve_back.visible = false
	hint_label.modulate.a = 1.0
	if in_menu:
		cursor = mini(cursor, _option_count() - 1)
		hint_label.position = Vector2(80, 456)
		hint_label.size = Vector2(992, 36)
		hint_label.add_theme_color_override("font_color", Color(0.82, 0.86, 0.9, 1))
		match _step:
			Step.DIFF:
				subtitle_label.text = "CPU DIFFICULTY"
				if GameState.is_touch_ui():
					hint_label.text = "TAP A DIFFICULTY"
				else:
					hint_label.text = "W/S NAVIGATE   SPACE/ENTER SELECT   ESC BACK"
				_update_devices_label()
			Step.SIDE:
				subtitle_label.text = "YOUR SIDE" if GameState.mode == Constants.MODE_AI else "P1 SIDE"
				if GameState.is_touch_ui():
					hint_label.text = "TAP LEFT OR RIGHT"
					if GameState.mode == Constants.MODE_AI:
						devices_label.text = "DRAG YOUR SIDE TO MOVE      CPU PLAYS THE OTHER"
					else:
						devices_label.text = "LEFT HALF P1      RIGHT HALF P2"
				else:
					hint_label.text = "W/S OR LEFT/RIGHT   SPACE/ENTER SELECT   ESC BACK"
					if GameState.mode == Constants.MODE_AI:
						devices_label.text = "YOU: W/S OR ARROWS      CPU PLAYS THE OTHER SIDE"
					else:
						devices_label.text = "P1: W / S ON YOUR SIDE      P2: ARROWS ON THE OTHER"
			_:
				subtitle_label.text = "FIRST TO FIVE"
				if GameState.is_touch_ui():
					hint_label.text = "TAP A MODE"
				else:
					hint_label.text = "W/S NAVIGATE   SPACE/ENTER SELECT"
				_update_devices_label()
		_update_menu_highlight()
	else:
		_hide_options()
		serve_title.position = Vector2(76, 292)
		serve_title.size = Vector2(1000, 40)
		hint_label.position = Vector2(76, 336)
		hint_label.size = Vector2(1000, 32)
		hint_label.add_theme_color_override("font_color", Color(0.7, 0.74, 0.8, 1))
		if GameState.is_cpu_serving():
			serve_title.text = "CPU SERVE"
			hint_label.text = "PAUSE AT BOTTOM" if GameState.is_touch_ui() else "ESC PAUSE"
		elif GameState.is_p1_serving():
			serve_title.text = "YOUR SERVE" if GameState.mode == Constants.MODE_AI else "P1 SERVE"
			if GameState.is_touch_ui():
				hint_label.text = "DRAG TO AIM   TAP TO SERVE"
			else:
				hint_label.text = "W/S or ARROWS Aim  ·  SPACE/CLICK Serve  ·  ESC Pause"
		else:
			serve_title.text = "P2 SERVE"
			if GameState.is_touch_ui():
				hint_label.text = "DRAG RIGHT HALF TO AIM   TAP TO SERVE"
			else:
				hint_label.text = "UP/DOWN Aim  ·  SPACE/CLICK Serve  ·  ESC Pause"
		serve_title.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	hint_label.visible = true


func _hide_options() -> void:
	option1_bg.visible = false
	option2_bg.visible = false
	option1_label.visible = false
	option2_label.visible = false
	if option3_bg:
		option3_bg.visible = false
	if option3_label:
		option3_label.visible = false


func _place_option(bg: Control, label: Control, y: float, h: float) -> void:
	bg.position = Vector2(336.0, y)
	bg.size = Vector2(480.0, h)
	label.position = Vector2(336.0, y + (h - 34.0) * 0.5)
	label.size = Vector2(480.0, 34.0)


func _update_menu_highlight() -> void:
	var idle := Color(0.62, 0.66, 0.72, 1)
	var selected := Color(1, 1, 1, 1)
	var in_menu := not GameState.mode_selected
	var names: PackedStringArray
	if _step == Step.DIFF:
		_place_option(option1_bg, option1_label, 248.0, 58.0)
		_place_option(option2_bg, option2_label, 318.0, 58.0)
		_place_option(option3_bg, option3_label, 388.0, 58.0)
		names = PackedStringArray(["EASY", "NORMAL", "HARD"])
	elif _step == Step.SIDE:
		_place_option(option1_bg, option1_label, 268.0, 68.0)
		_place_option(option2_bg, option2_label, 356.0, 68.0)
		names = PackedStringArray(["LEFT", "RIGHT"])
	else:
		_place_option(option1_bg, option1_label, 268.0, 68.0)
		_place_option(option2_bg, option2_label, 356.0, 68.0)
		names = PackedStringArray(["VS CPU", "VS PLAYER"])
	var bars := [option1_bg, option2_bg, option3_bg]
	var labels := [option1_label, option2_label, option3_label]
	for i in range(3):
		var on := in_menu and i < names.size()
		bars[i].visible = on
		labels[i].visible = on
		if not on:
			continue
		var is_sel := cursor == i
		labels[i].text = (">  %s" % names[i]) if is_sel else names[i]
		labels[i].add_theme_color_override("font_color", selected if is_sel else idle)
		bars[i].add_theme_stylebox_override("panel", _style_sel if is_sel else _style_idle)


func _update_devices_label() -> void:
	if _step == Step.SIDE:
		return
	if GameState.is_touch_ui():
		var sound := "MUTED" if SFX.muted else "SOUND ON"
		var cb := "ON" if GameState.colorblind_mode else "OFF"
		devices_label.text = "COLORBLIND %s      %s" % [cb, sound]
	else:
		var cb := "ON" if GameState.colorblind_mode else "OFF"
		devices_label.text = "P1: W / S      P2: UP / DOWN      C COLORBLIND %s      M MUTE" % cb
