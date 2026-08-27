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

enum Step { MODE, DIFF, SIDE, ONLINE }
enum OnlineView { OPTIONS, JOIN, WAITING, ERROR }

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
var _touch_starts: Dictionary = {}
var _touch_dragged: Dictionary = {}
var online_overlay: Control
var online_card: Control
var online_title: Label
var online_status: Label
var online_code: Label
var online_input_frame: Panel
var online_input: LineEdit
var online_hint: Label
var online_option_bgs: Array[Panel] = []
var online_option_labels: Array[Label] = []
var _online_view := OnlineView.OPTIONS
var _online_cursor := 0
var _pending_online_action := ""
var _pending_online_code := ""
var _online_request_sent := false
var _online_countdown_active := false
var _online_countdown_id := 0
const TAP_SLACK := 28.0


func _ready() -> void:
	visible = false
	layer = 20
	Constants.configure_touch_root(root)
	root.modulate = Color(1, 1, 1, 0)
	GameState.serving_changed.connect(_on_serving_changed)
	GameState.game_over.connect(_on_game_over)
	GameState.mode_changed.connect(_on_mode_changed)
	GameState.rematch_started.connect(_on_rematch_started)
	Players.player_assigned.connect(_on_player_assigned)
	Players.player_released.connect(_on_player_released)
	option1_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	option2_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	option1_bg.mouse_filter = Control.MOUSE_FILTER_STOP
	option2_bg.mouse_filter = Control.MOUSE_FILTER_STOP
	option1_bg.gui_input.connect(_on_option_gui.bind(0))
	option2_bg.gui_input.connect(_on_option_gui.bind(1))
	_make_option3()
	_make_online_overlay()
	NetworkManager.connection_changed.connect(_on_online_connection_changed)
	NetworkManager.room_changed.connect(_on_online_room_changed)
	NetworkManager.opponent_changed.connect(_on_online_opponent_changed)
	NetworkManager.match_ready.connect(_on_online_match_ready)
	NetworkManager.online_error.connect(_on_online_error)
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
	option3_bg.set_script(preload("res://ink_button.gd"))
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
	back_label.text = "< BACK"
	back_label.add_theme_font_size_override("font_size", 18)
	back_label.add_theme_color_override("font_color", Color(0.12, 0.12, 0.11, 1))
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
		if _online_countdown_active:
			return
		_handle_serve_input(delta)
		if _serve_ready:
			hint_label.modulate.a = 1.0
		return
	_handle_menu_input()


func _handle_menu_input() -> void:
	if _step != Step.MODE and (Input.is_action_just_pressed("ui_cancel") or Players.is_pause_just_pressed()):
		_go_back()
		return
	if _step == Step.ONLINE:
		_handle_online_input()
		return
	if _step == Step.MODE:
		if Input.is_action_just_pressed("mode_1"):
			_confirm_mode(Constants.MODE_AI)
			return
		if Input.is_action_just_pressed("mode_2"):
			_confirm_mode(Constants.MODE_2P)
			return
		if Input.is_action_just_pressed("mode_3"):
			_open_online_lobby()
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
		SFX.play("nav")
		_update_menu_highlight()
	var adj := _adjust_dir()
	if adj != 0 and _step != Step.MODE:
		var count := _option_count()
		var next := (cursor + adj + count) % count
		if next != cursor:
			cursor = next
			SFX.play("nav")
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
	if _step == Step.MODE or _step == Step.DIFF:
		return 3
	if _step == Step.ONLINE:
		return _online_option_count()
	return 2


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
		Step.ONLINE:
			_confirm_online()
		_:
			if cursor == 2:
				_open_online_lobby()
			else:
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
		if _is_valid_serve_pointer(event.position):
			GameState.note_input("touch")
			_launch_player_serve()


func _go_back() -> void:
	SFX.play("nav")
	if _step == Step.ONLINE:
		_close_online_lobby()
		return
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
	if GameState.mode == Constants.MODE_ONLINE and not GameState.is_local_player_serving():
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
	if not _serve_ready or not GameState.serving or GameState.is_cpu_serving() or _online_countdown_active:
		return
	if GameState.mode == Constants.MODE_ONLINE and not GameState.is_local_player_serving():
		return
	SFX.play("confirm", 1.15)
	if GameState.mode == Constants.MODE_ONLINE:
		NetworkManager.request_serve(_online_serve_aim())
		return
	GameState.set_serving(false)


func _input(event: InputEvent) -> void:
	if GameState.paused or GameState.is_game_over or not GameState.serving or not GameState.mode_selected:
		_clear_pointer_state()
		return
	if GameState.is_cpu_serving() or not _serve_ready or (GameState.mode == Constants.MODE_ONLINE and not GameState.is_local_player_serving()):
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		GameState.note_input("mouse")
		if event.pressed:
			if _is_valid_serve_pointer(event.position):
				_pointer_down = true
				_pointer_dragged = false
				_pointer_start = event.position
		else:
			if _pointer_down and not _pointer_dragged:
				_launch_player_serve()
			_pointer_down = false
			_pointer_dragged = false
		return
	elif event is InputEventScreenTouch:
		GameState.note_input("touch")
		if event.pressed:
			if _is_valid_serve_pointer(event.position):
				_touch_starts[event.index] = event.position
				_touch_dragged[event.index] = false
		else:
			if _touch_starts.has(event.index) and not bool(_touch_dragged.get(event.index, false)):
				_launch_player_serve()
			_touch_starts.erase(event.index)
			_touch_dragged.erase(event.index)
		return
	elif event is InputEventMouseMotion and _pointer_down:
		if event.position.distance_to(_pointer_start) > TAP_SLACK:
			_pointer_dragged = true
		return
	elif event is InputEventScreenDrag and _touch_starts.has(event.index):
		if event.position.distance_to(_touch_starts[event.index]) > TAP_SLACK:
			_touch_dragged[event.index] = true
		return


func _is_valid_serve_pointer(pos: Vector2) -> bool:
	if pos.y < Constants.HUD_HEIGHT or GameState.is_cpu_serving():
		return false
	if GameState.mode == Constants.MODE_ONLINE and not GameState.is_local_player_serving():
		return false
	var server_is_left := GameState.server_is_left()
	if GameState.mode == Constants.MODE_AI and server_is_left != GameState.player_is_left:
		return false
	if GameState.mode == Constants.MODE_2P:
		return (pos.x < get_viewport().get_visible_rect().size.x * 0.5) == server_is_left
	return true


func _clear_pointer_state() -> void:
	_pointer_down = false
	_pointer_dragged = false
	_touch_starts.clear()
	_touch_dragged.clear()


func _on_serving_changed(serving: bool) -> void:
	_ai_serve_timer = 0.0
	_serve_ready = false
	_clear_pointer_state()
	if serving:
		visible = true
		_refresh()
		_fade_in()
		if GameState.mode_selected:
			var serve_delay := 0.45 if GameState.mode == Constants.MODE_ONLINE else 0.22
			await get_tree().create_timer(serve_delay, true).timeout
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
	online_overlay.visible = false
	serve_title.visible = false
	serve_back.visible = false


func _on_mode_changed(_mode: int) -> void:
	_refresh()


func _on_rematch_started() -> void:
	visible = true
	_refresh()
	_fade_in()
	_serve_ready = false
	var serve_delay := 0.45 if GameState.mode == Constants.MODE_ONLINE else 0.22
	await get_tree().create_timer(serve_delay, true).timeout
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
	if _step == Step.ONLINE and (not GameState.mode_selected or _online_countdown_active):
		title_label.visible = false
		subtitle_label.visible = false
		panel.visible = false
		devices_label.visible = false
		serve_title.visible = false
		hint_label.visible = false
		_hide_options()
		online_overlay.visible = in_menu or _online_countdown_active
		_update_online_view()
		return
	if _step == Step.ONLINE:
		online_overlay.visible = false
	serve_title.visible = not in_menu
	serve_back.visible = false
	hint_label.modulate.a = 1.0
	if in_menu:
		cursor = mini(cursor, _option_count() - 1)
		var three_row_menu := _step == Step.DIFF or _step == Step.MODE
		hint_label.position = Vector2(80, 476 if _step == Step.DIFF else (526 if three_row_menu else 456))
		hint_label.size = Vector2(992, 36)
		devices_label.position.y = 520.0 if _step == Step.DIFF else (566.0 if three_row_menu else 500.0)
		hint_label.add_theme_color_override("font_color", Color(0.12, 0.12, 0.11, 1))
		match _step:
			Step.DIFF:
				subtitle_label.position.y = 218.0
				subtitle_label.text = "CPU DIFFICULTY"
				if GameState.is_touch_ui():
					hint_label.text = "TAP TO CHOOSE"
				elif GameState.is_controller_ui():
					hint_label.text = "STICK MOVE   A SELECT   B BACK"
				else:
					hint_label.text = "UP/DOWN MOVE   SPACE SELECT   ESC BACK"
				_update_devices_label()
			Step.SIDE:
				subtitle_label.position.y = 226.0
				subtitle_label.text = "YOUR SIDE" if GameState.mode == Constants.MODE_AI else "P1 SIDE"
				if GameState.is_touch_ui():
					hint_label.text = "TAP A SIDE"
				elif GameState.is_controller_ui():
					hint_label.text = "STICK CHOOSE   A SELECT   B BACK"
					if GameState.mode == Constants.MODE_AI:
						devices_label.text = "DRAG SIDE   CPU OTHER"
					else:
						devices_label.text = "LEFT P1   RIGHT P2"
				else:
					hint_label.text = "LEFT/RIGHT MOVE   SPACE SELECT   ESC BACK"
					if GameState.mode == Constants.MODE_AI:
						devices_label.text = "YOU W/S   CPU OTHER"
					else:
						devices_label.text = "P1 W/S   P2 ARROWS"
			_:
				subtitle_label.position.y = 226.0
				subtitle_label.text = "FIRST TO FIVE"
				if GameState.is_touch_ui():
					hint_label.text = "TAP TO CHOOSE"
				elif GameState.is_controller_ui():
					hint_label.text = "STICK MOVE   A SELECT"
				else:
					hint_label.text = "UP/DOWN MOVE   SPACE SELECT"
				_update_devices_label()
		_update_menu_highlight()
	else:
		_hide_options()
		serve_title.position = Vector2(76, 292)
		serve_title.size = Vector2(1000, 40)
		hint_label.position = Vector2(76, 336)
		hint_label.size = Vector2(1000, 32)
		hint_label.add_theme_color_override("font_color", Color(0.12, 0.12, 0.11, 1))
		if GameState.mode == Constants.MODE_ONLINE:
			if GameState.is_local_player_serving():
				serve_title.text = "YOUR SERVE"
				if GameState.is_touch_ui():
					hint_label.text = "DRAG TO AIM   TAP TO SERVE"
				elif GameState.is_controller_ui():
					hint_label.text = "LEFT STICK AIM   A SERVE   START MENU"
				else:
					hint_label.text = "W/S OR ARROWS AIM   SPACE SERVE   ESC MENU"
			else:
				serve_title.text = "OPPONENT SERVES"
				hint_label.text = "WAIT FOR THE SERVE   ESC MENU"
		elif GameState.is_cpu_serving():
			serve_title.text = "CPU SERVE"
			hint_label.text = "PAUSE AT BOTTOM" if GameState.is_touch_ui() else ("START PAUSE" if GameState.is_controller_ui() else "ESC PAUSE")
		elif GameState.is_p1_serving():
			serve_title.text = "YOUR SERVE" if GameState.mode == Constants.MODE_AI else "P1 SERVE"
			if GameState.is_touch_ui():
				hint_label.text = "DRAG TO AIM   TAP TO SERVE"
			elif GameState.is_controller_ui():
				hint_label.text = "LEFT STICK AIM   A SERVE   START PAUSE"
			else:
				hint_label.text = "W/S OR ARROWS AIM   SPACE SERVE   ESC PAUSE"
		else:
			serve_title.text = "P2 SERVE"
			if GameState.is_touch_ui():
				var half := "LEFT" if GameState.server_is_left() else "RIGHT"
				hint_label.text = "DRAG %s HALF TO AIM   TAP TO SERVE" % half
			elif GameState.is_controller_ui():
				hint_label.text = "LEFT STICK AIM   A SERVE   START PAUSE"
			else:
				hint_label.text = "UP/DOWN AIM   SPACE SERVE   ESC PAUSE"
		serve_title.add_theme_color_override("font_color", Color(0.12, 0.12, 0.11, 1))
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
	var idle := Color(0.12, 0.12, 0.11, 1)
	var selected := Color(0.12, 0.12, 0.11, 1)
	var in_menu := not GameState.mode_selected
	var names: PackedStringArray
	if _step == Step.DIFF:
		_place_option(option1_bg, option1_label, 268.0, 58.0)
		_place_option(option2_bg, option2_label, 338.0, 58.0)
		_place_option(option3_bg, option3_label, 408.0, 58.0)
		names = PackedStringArray(["EASY", "NORMAL", "HARD"])
	elif _step == Step.SIDE:
		_place_option(option1_bg, option1_label, 268.0, 68.0)
		_place_option(option2_bg, option2_label, 356.0, 68.0)
		names = PackedStringArray(["LEFT", "RIGHT"])
	else:
		_place_option(option1_bg, option1_label, 248.0, 62.0)
		_place_option(option2_bg, option2_label, 326.0, 62.0)
		_place_option(option3_bg, option3_label, 404.0, 62.0)
		names = PackedStringArray(["PLAYER VS CPU", "PLAYER VS PLAYER", "ONLINE"])
	var bars := [option1_bg, option2_bg, option3_bg]
	var labels := [option1_label, option2_label, option3_label]
	for i in range(3):
		var on := in_menu and i < names.size()
		bars[i].visible = on
		labels[i].visible = on
		if not on:
			continue
		var is_sel := cursor == i
		labels[i].text = names[i]
		labels[i].add_theme_color_override("font_color", selected if is_sel else idle)
		bars[i].set("selected", is_sel)
		bars[i].add_theme_stylebox_override("panel", _style_sel if is_sel else _style_idle)


func _update_devices_label() -> void:
	if _step == Step.SIDE:
		return
	if GameState.is_touch_ui():
		var silent := SFX.muted or SFX.sfx_volume <= 0.001 or SFX.master_volume <= 0.001
		var sound := "MUTED" if silent else "SOUND ON"
		devices_label.text = sound
	else:
		devices_label.text = "P1 W/S   P2 UP/DOWN   M MUTE"


func _make_online_overlay() -> void:
	online_overlay = Control.new()
	online_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	online_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	online_overlay.visible = false
	root.add_child(online_overlay)
	online_card = Control.new()
	online_card.position = Vector2(316.0, 64.0)
	online_card.size = Vector2(520.0, 520.0)
	online_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	online_overlay.add_child(online_card)
	online_title = _make_online_label("ONLINE", Vector2(0.0, 42.0), Vector2(520.0, 42.0), 30)
	online_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	online_card.add_child(online_title)
	online_status = _make_online_label("CONNECTING...", Vector2(0.0, 94.0), Vector2(520.0, 52.0), 18)
	online_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	online_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	online_card.add_child(online_status)
	online_code = _make_online_label("", Vector2(0.0, 160.0), Vector2(520.0, 48.0), 36)
	online_code.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	online_code.mouse_filter = Control.MOUSE_FILTER_STOP
	online_code.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	online_code.tooltip_text = "COPY ROOM CODE"
	online_code.gui_input.connect(_on_online_code_gui)
	online_card.add_child(online_code)
	online_input_frame = Panel.new()
	online_input_frame.set_script(preload("res://ink_panel.gd"))
	online_input_frame.position = Vector2(80.0, 148.0)
	online_input_frame.size = Vector2(360.0, 56.0)
	online_input_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	online_card.add_child(online_input_frame)
	online_input = LineEdit.new()
	online_input.position = Vector2(80.0, 150.0)
	online_input.size = Vector2(360.0, 52.0)
	online_input.max_length = 6
	online_input.placeholder_text = "6-CHARACTER CODE"
	online_input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	online_input.add_theme_font_size_override("font_size", 24)
	online_input.add_theme_color_override("font_color", Color(0.12, 0.12, 0.11, 1))
	online_input.add_theme_color_override("font_placeholder_color", Color(0.35, 0.35, 0.34, 1))
	online_input.add_theme_color_override("caret_color", Color(0.12, 0.12, 0.11, 1))
	var input_style := StyleBoxFlat.new()
	input_style.bg_color = Color(1.0, 1.0, 1.0, 0.0)
	input_style.border_width_left = 0
	input_style.border_width_top = 0
	input_style.border_width_right = 0
	input_style.border_width_bottom = 0
	input_style.content_margin_left = 0.0
	input_style.content_margin_right = 0.0
	input_style.content_margin_top = 0.0
	input_style.content_margin_bottom = 0.0
	input_style.corner_radius_top_left = 0
	input_style.corner_radius_top_right = 0
	input_style.corner_radius_bottom_right = 0
	input_style.corner_radius_bottom_left = 0
	online_input.add_theme_stylebox_override("normal", input_style)
	online_input.add_theme_stylebox_override("focus", input_style)
	online_input.text_submitted.connect(_on_online_text_submitted)
	online_card.add_child(online_input)
	for i in range(3):
		var bg := Panel.new()
		bg.set_script(preload("res://ink_button.gd"))
		bg.position = Vector2(20.0, 204.0 + i * 70.0)
		bg.size = Vector2(480.0, 58.0)
		bg.mouse_filter = Control.MOUSE_FILTER_STOP
		bg.gui_input.connect(_on_online_option_gui.bind(i))
		online_card.add_child(bg)
		online_option_bgs.append(bg)
		var label := _make_online_label("", Vector2(20.0, 216.0 + i * 70.0), Vector2(480.0, 34.0), 21)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		online_card.add_child(label)
		online_option_labels.append(label)
	online_hint = _make_online_label("ESC/B BACK", Vector2(0.0, 432.0), Vector2(520.0, 30.0), 16)
	online_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	online_card.add_child(online_hint)


func _make_online_label(text_value: String, label_position: Vector2, label_size: Vector2, font_size: int) -> Label:
	var label := Label.new()
	label.text = text_value
	label.position = label_position
	label.size = label_size
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color(0.12, 0.12, 0.11, 1))
	return label


func _open_online_lobby() -> void:
	SFX.play("confirm")
	_step = Step.ONLINE
	_online_view = OnlineView.OPTIONS
	_online_cursor = 0
	_pending_online_action = ""
	_pending_online_code = ""
	_online_request_sent = false
	GameState.select_mode(Constants.MODE_ONLINE)
	NetworkManager.connect_to_server()
	_refresh()


func _close_online_lobby() -> void:
	_cancel_online_countdown()
	if NetworkManager.state != NetworkManager.STATE_DISCONNECTED:
		NetworkManager.disconnect_from_server()
	_step = Step.MODE
	cursor = 2
	_online_view = OnlineView.OPTIONS
	_online_cursor = 0
	_pending_online_action = ""
	_pending_online_code = ""
	_online_request_sent = false
	online_overlay.visible = false
	_refresh()


func _online_option_count() -> int:
	match _online_view:
		OnlineView.OPTIONS:
			return 3
		OnlineView.JOIN:
			return 2
		OnlineView.WAITING:
			return 1 if NetworkManager.room_code.is_empty() else 2
		OnlineView.ERROR:
			return 2
	return 0


func _handle_online_input() -> void:
	var count := _online_option_count()
	if count <= 0:
		return
	var nav := 0
	if Input.is_action_just_pressed("up") or Input.is_action_just_pressed("ui_up") or Players.is_nav_up_just_pressed():
		nav = -1
	elif Input.is_action_just_pressed("down") or Input.is_action_just_pressed("ui_down") or Players.is_nav_down_just_pressed():
		nav = 1
	if nav != 0:
		_online_cursor = (_online_cursor + nav + count) % count
		SFX.play("nav")
		_update_online_view()
	if Input.is_action_just_pressed("ui_cancel") or Players.is_pause_just_pressed():
		_go_back()
	elif Input.is_action_just_pressed("stop") or Input.is_action_just_pressed("ui_accept") or Players.is_confirm_just_pressed():
		_confirm_online()


func _confirm_online() -> void:
	match _online_view:
		OnlineView.OPTIONS:
			match _online_cursor:
				0:
					if not _pending_online_action.is_empty():
						return
					SFX.play("confirm")
					_pending_online_action = "create"
					_pending_online_code = ""
					_online_request_sent = false
					_online_view = OnlineView.WAITING
					online_code.text = ""
					_update_online_view()
					_send_pending_online_action()
				1:
					SFX.play("confirm")
					_online_view = OnlineView.JOIN
					_online_cursor = 0
					online_input.text = ""
					online_input.grab_focus()
					_update_online_view()
				_:
					_close_online_lobby()
		OnlineView.JOIN:
			if _online_cursor == 0:
				_submit_online_join()
			else:
				_open_online_options()
		OnlineView.WAITING:
			if NetworkManager.room_code.is_empty():
				SFX.play("nav")
				_pending_online_action = ""
				NetworkManager.disconnect_from_server()
				NetworkManager.connect_to_server()
				_open_online_options()
			elif _online_cursor == 1:
				SFX.play("nav")
				NetworkManager.leave_room()
				_open_online_options()
			else:
				_copy_online_code()
		OnlineView.ERROR:
			if _online_cursor == 0:
				SFX.play("confirm")
				_online_view = OnlineView.OPTIONS
				_online_cursor = 0
				NetworkManager.connect_to_server()
				_update_online_view()
			else:
				_close_online_lobby()


func _submit_online_join() -> void:
	if not _pending_online_action.is_empty():
		return
	var code := online_input.text.strip_edges().to_upper()
	if code.length() != 6:
		_show_online_error("ENTER THE SIX-CHARACTER ROOM CODE")
		return
	SFX.play("confirm")
	_pending_online_action = "join"
	_pending_online_code = code
	_online_request_sent = false
	_online_view = OnlineView.WAITING
	online_code.text = ""
	online_input.release_focus()
	_update_online_view()
	_send_pending_online_action()


func _on_online_text_submitted(_text: String) -> void:
	_online_cursor = 0
	_submit_online_join()


func _on_online_option_gui(event: InputEvent, index: int) -> void:
	if _step != Step.ONLINE or index >= _online_option_count():
		return
	var activated := false
	if event is InputEventMouseMotion:
		if _online_cursor != index:
			_online_cursor = index
			_update_online_view()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_online_cursor = index
		activated = true
	elif event is InputEventScreenTouch and event.pressed:
		_online_cursor = index
		activated = true
	if activated:
		_update_online_view()
		_confirm_online()


func _on_online_code_gui(event: InputEvent) -> void:
	if _step != Step.ONLINE or _online_view != OnlineView.WAITING or NetworkManager.room_code.is_empty():
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_copy_online_code()
	elif event is InputEventScreenTouch and event.pressed:
		_copy_online_code()


func _copy_online_code() -> void:
	var code := NetworkManager.room_code.strip_edges()
	if code.is_empty():
		return
	DisplayServer.clipboard_set(code)
	SFX.play("confirm")
	online_status.text = "ROOM CODE COPIED"
	online_hint.text = "SHARE IT WITH YOUR OPPONENT"


func _open_online_options() -> void:
	_pending_online_action = ""
	_pending_online_code = ""
	_online_request_sent = false
	_online_view = OnlineView.OPTIONS
	_online_cursor = 0
	online_input.release_focus()
	_update_online_view()


func _show_online_error(message: String) -> void:
	SFX.play("nav")
	_pending_online_action = ""
	_pending_online_code = ""
	_online_request_sent = false
	_online_view = OnlineView.ERROR
	_online_cursor = 0
	online_status.text = message
	online_input.release_focus()
	_update_online_view()


func _on_online_connection_changed(state: int, message: String) -> void:
	if _step != Step.ONLINE:
		return
	online_status.text = message
	if state == NetworkManager.STATE_DISCONNECTED and GameState.mode_selected and GameState.mode == Constants.MODE_ONLINE:
		_pending_online_action = ""
		_return_to_online_lobby()
		_show_online_error(message)
	elif state == NetworkManager.STATE_DISCONNECTED and _online_view == OnlineView.WAITING:
		_pending_online_action = ""
		_show_online_error(message)
	elif state == NetworkManager.STATE_CONNECTED and not _pending_online_action.is_empty():
		_send_pending_online_action()
	else:
		_update_online_view()


func _on_online_room_changed(code: String, _side: String, status: String) -> void:
	if _step != Step.ONLINE:
		return
	_online_view = OnlineView.WAITING
	_pending_online_action = ""
	_pending_online_code = ""
	_online_request_sent = false
	_online_cursor = 0
	online_code.text = code
	online_status.text = status
	_update_online_view()


func _on_online_opponent_changed(connected: bool) -> void:
	if _step != Step.ONLINE:
		return
	if connected:
		online_status.text = "OPPONENT CONNECTED"
	else:
		if GameState.mode_selected and GameState.mode == Constants.MODE_ONLINE:
			_return_to_online_lobby()
		_online_view = OnlineView.WAITING
		online_status.text = "OPPONENT DISCONNECTED"
	_update_online_view()


func _on_online_match_ready() -> void:
	if _step != Step.ONLINE or _online_countdown_active:
		return
	_online_countdown_active = true
	_online_countdown_id += 1
	var countdown_id := _online_countdown_id
	GameState.begin_online_match(NetworkManager.player_side)
	_run_online_countdown(countdown_id)


func _run_online_countdown(countdown_id: int) -> void:
	_online_view = OnlineView.WAITING
	online_title.text = "MATCH READY"
	online_code.text = ""
	online_hint.text = "PLEASE WAIT"
	for count in [3, 2, 1]:
		online_status.text = str(count)
		_update_online_view()
		await get_tree().create_timer(0.8, true).timeout
		if not _online_countdown_active or countdown_id != _online_countdown_id:
			return
	online_status.text = "GO"
	_update_online_view()
	await get_tree().create_timer(0.45, true).timeout
	if not _online_countdown_active or countdown_id != _online_countdown_id:
		return
	_online_countdown_active = false
	_update_online_view()
	_refresh()


func _update_online_view() -> void:
	if online_overlay == null:
		return
	var count := _online_option_count()
	_online_cursor = clampi(_online_cursor, 0, maxi(count - 1, 0))
	online_input.visible = _online_view == OnlineView.JOIN
	online_input_frame.visible = _online_view == OnlineView.JOIN
	online_code.visible = _online_view == OnlineView.WAITING
	online_input.position.y = 150.0
	if _online_countdown_active:
		online_title.text = "MATCH READY"
		online_code.visible = false
		online_hint.text = "PLEASE WAIT"
		for i in range(online_option_bgs.size()):
			online_option_bgs[i].visible = false
			online_option_labels[i].visible = false
		return
	online_title.text = "ONLINE"
	online_hint.text = "ESC/B BACK"
	var names := PackedStringArray()
	var option_start_y := 204.0
	match _online_view:
		OnlineView.OPTIONS:
			names = PackedStringArray(["CREATE ROOM", "JOIN ROOM", "BACK"])
			online_code.text = ""
		OnlineView.JOIN:
			names = PackedStringArray(["JOIN ROOM", "BACK"])
			option_start_y = 218.0
			online_hint.text = "TYPE CODE   ENTER TO JOIN   ESC/B BACK"
		OnlineView.WAITING:
			option_start_y = 220.0
			online_title.text = "ONLINE ROOM"
			if NetworkManager.room_code.is_empty():
				names = PackedStringArray(["CANCEL"])
				if _pending_online_action == "join":
					online_hint.text = "CHECKING ROOM CODE"
				else:
					online_hint.text = "CREATING YOUR PRIVATE ROOM"
			else:
				names = PackedStringArray(["COPY CODE", "LEAVE ROOM"])
				online_hint.text = "SHARE THIS CODE WITH YOUR OPPONENT"
		OnlineView.ERROR:
			names = PackedStringArray(["RETRY", "BACK"])
			option_start_y = 218.0
			online_code.text = ""
	for i in range(online_option_bgs.size()):
		online_option_bgs[i].position.y = option_start_y + i * 70.0
		online_option_labels[i].position.y = option_start_y + 12.0 + i * 70.0
		var on := i < names.size()
		online_option_bgs[i].visible = on
		online_option_labels[i].visible = on
		if not on:
			continue
		online_option_labels[i].text = names[i]
		var selected := i == _online_cursor
		online_option_labels[i].add_theme_color_override("font_color", Color(0.12, 0.12, 0.11, 1))
		online_option_bgs[i].set("selected", selected)
	if _online_view == OnlineView.OPTIONS and NetworkManager.state == NetworkManager.STATE_CONNECTING:
		online_status.text = "CONNECTING...\nSERVER MAY TAKE A MOMENT"
	if _online_view == OnlineView.WAITING and online_code.text.is_empty():
		if not NetworkManager.connection_is_open():
			online_status.text = "CONNECTING TO ONLINE SERVER..."
		else:
			online_status.text = "JOINING ROOM..." if _pending_online_action == "join" else "CREATING ROOM..."


func _on_online_error(message: String) -> void:
	if _step != Step.ONLINE:
		return
	_show_online_error(message)


func _send_pending_online_action() -> void:
	if _pending_online_action.is_empty() or _online_request_sent or not NetworkManager.connection_is_open():
		return
	_online_request_sent = true
	if _pending_online_action == "create":
		NetworkManager.create_room()
	elif _pending_online_action == "join":
		NetworkManager.join_room(_pending_online_code)


func _online_serve_aim() -> float:
	var paddle = get_parent().get_node("paddleLeft") if GameState.player_is_left else get_parent().get_node("paddleRight")
	var mid := (get_viewport().get_visible_rect().size.y + Constants.HUD_HEIGHT) * 0.5
	var center_offset: float = (paddle.position.y - mid) / maxf(paddle.half_height(), 1.0)
	var paddle_input: float = paddle.last_vy / maxf(paddle.speed, 1.0) if paddle.has_pointer_target() else paddle.get_move_input()
	return clampf(paddle_input * 0.85 + center_offset * 0.4, -1.0, 1.0)


func _cancel_online_countdown() -> void:
	_online_countdown_active = false
	_online_countdown_id += 1


func _return_to_online_lobby() -> void:
	_cancel_online_countdown()
	GameState.cancel_online_match()
	_online_view = OnlineView.WAITING if not NetworkManager.room_code.is_empty() else OnlineView.ERROR
	_refresh()
