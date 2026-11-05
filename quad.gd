extends Node2D
## Four-player square Pong: you against three CPUs, up to four people on one
## PC, or an online room of up to four with CPU paddles in empty seats.

const QuadSimulation = preload("res://quad_simulation.gd")
const QuadCourt = preload("res://quad_court.gd")
const INK_BUTTON_SCRIPT = preload("res://ink_button.gd")
const INK_PANEL_SCRIPT = preload("res://ink_panel.gd")
const INK_THEME = preload("res://ink_theme.tres")
const PADDLE_TEXTURE = preload("res://art/paddle-ink.png")
const BALL_TEXTURE = preload("res://art/ball-ink.png")
const PAPER_TEXTURE = preload("res://art/paper-court.png")
const MENU_SCENE := "res://main.tscn"
const INK := Color(0.12, 0.12, 0.11, 1.0)
const COURT_ORIGIN := Vector2(306.0, 54.0)
const PADDLE_REGION := Rect2(555, 266, 144, 721)
const BALL_REGION := Rect2(535, 525, 184, 184)

# Local play gives every wall its own pair of keys: [toward start, toward end].
const SEAT_KEYS := [[KEY_W, KEY_S], [KEY_UP, KEY_DOWN], [KEY_T, KEY_Y], [KEY_B, KEY_N]]
const SEAT_KEY_HINTS := ["W  S", "UP  DOWN", "T  Y", "B  N"]

const ONLINE_MAX_SNAPSHOT_AGE := 0.25
const ONLINE_MAX_LEAD_RTT := 0.3
const ONLINE_REMOTE_EXTRAPOLATION := 0.15
const ONLINE_ERROR_DECAY := 12.0
# Corrections glide instead of teleporting; only truly huge ones snap.
const ONLINE_SNAP_DISTANCE := 360.0
const ONLINE_MAX_CORRECTION_SPEED := 1300.0
const ONLINE_PREDICT_STEP := 1.0 / 120.0
const ONLINE_HISTORY_SECONDS := 1.0
const ONLINE_LOCAL_IDLE_RESYNC := 0.5
const ONLINE_LOCAL_RESYNC_RATE := 10.0

enum Phase { LOCAL_JOIN, ONLINE_MENU, ONLINE_JOIN, ONLINE_ROOM, PLAYING, PAUSED, OVER }

var mode := "cpu"
var phase := Phase.PLAYING
## Local matches run here; online it mirrors the latest server snapshot.
var sim := QuadSimulation.new()
var _predictor := QuadSimulation.new()
var _court: Node2D
var _paddles: Array[Sprite2D] = []
var _ball: Sprite2D
var _seat_big: Array[Label] = []
var _seat_small: Array[Label] = []
var _seat_controls: Array = [null, null, null, null]
var _seat_names: Array[String] = ["", "", "", ""]
var _join_order := 0

var _overlay_root: Control
var _dimmer: ColorRect
var _title: Label
var _status: Label
var _code: Label
var _hint: Label
var _code_frame: Panel
var _code_input: LineEdit
var _option_bgs: Array[Panel] = []
var _option_labels: Array[Label] = []
var _options: Array[String] = []
var _cursor := 0

var _online_seat := -1
var _online_host := -1
var _online_humans: Array = [false, false, false, false]
var _pending_action := ""
var _pending_code := ""
var _have_snapshot := false
var _snapshot_time := 0.0
var _local_pos := QuadSimulation.SIZE * 0.5
var _local_vel := 0.0
var _local_idle := 0.0
var _history_t := PackedFloat64Array()
var _history_p := PackedFloat32Array()
var _history_v := PackedFloat32Array()
var _ball_error := Vector2.ZERO
var _paddle_error: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _over_shown := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = false
	mode = GameState.quad_mode if GameState.quad_mode in ["cpu", "local", "online"] else "cpu"
	_build_court()
	_build_seat_labels()
	_build_overlay()
	NetworkManager.connection_changed.connect(_on_connection_changed)
	NetworkManager.online_error.connect(_on_online_error)
	NetworkManager.quad_room_joined.connect(_on_quad_room_joined)
	NetworkManager.quad_lobby_changed.connect(_on_quad_lobby_changed)
	NetworkManager.quad_started.connect(_on_quad_started)
	NetworkManager.quad_snapshot_received.connect(_on_quad_snapshot)
	NetworkManager.room_changed.connect(_on_two_player_room)
	match mode:
		"local":
			_enter_local_join()
		"online":
			_enter_online_menu()
		_:
			_start_cpu_match()


func _exit_tree() -> void:
	if mode == "online" and NetworkManager.state != NetworkManager.STATE_DISCONNECTED:
		NetworkManager.disconnect_from_server()


# --- scene building -----------------------------------------------------------

func _build_court() -> void:
	var paper := TextureRect.new()
	paper.texture = PAPER_TEXTURE
	paper.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	paper.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	paper.size = Vector2(1152.0, 648.0)
	paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	paper.z_index = -10
	add_child(paper)
	_court = QuadCourt.new()
	_court.position = COURT_ORIGIN
	add_child(_court)
	for seat in QuadSimulation.SEATS:
		var paddle := Sprite2D.new()
		paddle.texture = PADDLE_TEXTURE
		paddle.region_enabled = true
		paddle.region_rect = PADDLE_REGION
		paddle.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		paddle.scale = Vector2(QuadSimulation.PADDLE_THICKNESS / PADDLE_REGION.size.x, QuadSimulation.PADDLE_LENGTH / PADDLE_REGION.size.y)
		if QuadSimulation.normal_axis(seat) == 1:
			paddle.rotation = PI * 0.5
		paddle.z_index = 1
		add_child(paddle)
		_paddles.append(paddle)
		_place_paddle(seat, QuadSimulation.SIZE * 0.5, true)
	_ball = Sprite2D.new()
	_ball.texture = BALL_TEXTURE
	_ball.region_enabled = true
	_ball.region_rect = BALL_REGION
	_ball.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_ball.scale = Vector2.ONE * (QuadSimulation.BALL_RADIUS * 2.0 / BALL_REGION.size.x)
	_ball.z_index = 2
	_ball.visible = false
	add_child(_ball)


func _build_seat_labels() -> void:
	# Lives sit outside each wall, like a scoreboard drawn around the court.
	var layer := CanvasLayer.new()
	layer.layer = 25
	add_child(layer)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = INK_THEME
	layer.add_child(root)
	var right_edge := COURT_ORIGIN.x + QuadSimulation.SIZE
	var bottom_edge := COURT_ORIGIN.y + QuadSimulation.SIZE
	var mid := COURT_ORIGIN + Vector2.ONE * QuadSimulation.SIZE * 0.5
	var big_rects := [
		Rect2(COURT_ORIGIN.x - 210.0, mid.y - 36.0, 180.0, 52.0),
		Rect2(right_edge + 30.0, mid.y - 36.0, 180.0, 52.0),
		Rect2(mid.x - 90.0, 0.0, 180.0, 50.0),
		Rect2(mid.x - 90.0, bottom_edge + 2.0, 180.0, 50.0),
	]
	var small_rects := [
		Rect2(COURT_ORIGIN.x - 210.0, mid.y + 18.0, 180.0, 24.0),
		Rect2(right_edge + 30.0, mid.y + 18.0, 180.0, 24.0),
		Rect2(mid.x + 50.0, 16.0, 200.0, 24.0),
		Rect2(mid.x + 50.0, bottom_edge + 16.0, 200.0, 24.0),
	]
	for seat in QuadSimulation.SEATS:
		var big := _make_label(40, HORIZONTAL_ALIGNMENT_CENTER)
		var big_rect: Rect2 = big_rects[seat]
		big.position = big_rect.position
		big.size = big_rect.size
		root.add_child(big)
		_seat_big.append(big)
		var small := _make_label(16, HORIZONTAL_ALIGNMENT_CENTER if QuadSimulation.normal_axis(seat) == 0 else HORIZONTAL_ALIGNMENT_LEFT)
		var small_rect: Rect2 = small_rects[seat]
		small.position = small_rect.position
		small.size = small_rect.size
		root.add_child(small)
		_seat_small.append(small)


func _build_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)
	_overlay_root = Control.new()
	_overlay_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay_root.theme = INK_THEME
	layer.add_child(_overlay_root)
	_dimmer = ColorRect.new()
	_dimmer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dimmer.color = Color(1.0, 1.0, 1.0, 0.94)
	_dimmer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay_root.add_child(_dimmer)
	_title = _make_label(40, HORIZONTAL_ALIGNMENT_CENTER)
	_overlay_root.add_child(_title)
	_status = _make_label(18, HORIZONTAL_ALIGNMENT_CENTER)
	# Wrapping labels size themselves from their width, so set it before any text.
	_status.size = Vector2(700.0, 52.0)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_overlay_root.add_child(_status)
	_code = _make_label(40, HORIZONTAL_ALIGNMENT_CENTER)
	_code.mouse_filter = Control.MOUSE_FILTER_STOP
	_code.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_code.tooltip_text = "COPY ROOM CODE"
	_code.gui_input.connect(_on_code_gui)
	_overlay_root.add_child(_code)
	_code_frame = Panel.new()
	_code_frame.set_script(INK_PANEL_SCRIPT)
	_code_frame.position = Vector2(396.0, 214.0)
	_code_frame.size = Vector2(360.0, 56.0)
	_overlay_root.add_child(_code_frame)
	_code_input = LineEdit.new()
	_code_input.position = Vector2(396.0, 216.0)
	_code_input.size = Vector2(360.0, 52.0)
	_code_input.max_length = 6
	_code_input.placeholder_text = "6-CHARACTER CODE"
	_code_input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_code_input.add_theme_font_size_override("font_size", 24)
	_code_input.add_theme_color_override("font_color", INK)
	_code_input.add_theme_color_override("font_placeholder_color", Color(0.35, 0.35, 0.34, 1.0))
	_code_input.add_theme_color_override("caret_color", INK)
	var clear := StyleBoxEmpty.new()
	_code_input.add_theme_stylebox_override("normal", clear)
	_code_input.add_theme_stylebox_override("focus", clear)
	_code_input.text_submitted.connect(func(_text: String) -> void: _submit_join())
	_overlay_root.add_child(_code_input)
	for i in 4:
		var bg := Panel.new()
		bg.set_script(INK_BUTTON_SCRIPT)
		bg.position = Vector2(336.0, 0.0)
		bg.size = Vector2(480.0, 58.0)
		bg.gui_input.connect(_on_option_gui.bind(i))
		_overlay_root.add_child(bg)
		_option_bgs.append(bg)
		var label := _make_label(21, HORIZONTAL_ALIGNMENT_CENTER)
		label.size = Vector2(480.0, 34.0)
		_overlay_root.add_child(label)
		_option_labels.append(label)
	_hint = _make_label(16, HORIZONTAL_ALIGNMENT_CENTER)
	_overlay_root.add_child(_hint)


func _make_label(font_size: int, alignment: HorizontalAlignment) -> Label:
	var label := Label.new()
	label.horizontal_alignment = alignment
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", INK)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


# --- overlay ------------------------------------------------------------------

func _show_overlay(title: String, status: String, options: Array, hint: String = "", dim: bool = true, option_y: float = 300.0) -> void:
	_overlay_root.visible = true
	_dimmer.visible = dim
	_title.text = title
	_title.position = Vector2(176.0, 96.0)
	_title.size = Vector2(800.0, 56.0)
	_status.position = Vector2(226.0, 156.0)
	_status.size = Vector2(700.0, 52.0)
	_status.text = status
	_hint.text = hint
	_hint.position = Vector2(76.0, 562.0)
	_hint.size = Vector2(1000.0, 28.0)
	_code.visible = false
	_code_frame.visible = false
	_code_input.visible = false
	_options.clear()
	for i in _option_bgs.size():
		var on := i < options.size()
		_option_bgs[i].visible = on
		_option_labels[i].visible = on
		if not on:
			continue
		_options.append(str(options[i][0]))
		_option_labels[i].text = str(options[i][1])
		_option_bgs[i].position.y = option_y + i * 70.0
		_option_labels[i].position = Vector2(336.0, option_y + i * 70.0 + 12.0)
	_cursor = clampi(_cursor, 0, maxi(_options.size() - 1, 0))
	_refresh_cursor()


func _hide_overlay() -> void:
	_overlay_root.visible = false
	_code_input.release_focus()


func _refresh_cursor() -> void:
	for i in _option_bgs.size():
		_option_bgs[i].set("selected", i == _cursor and i < _options.size())


func _move_cursor(direction: int) -> void:
	if _options.is_empty():
		return
	_cursor = (_cursor + direction + _options.size()) % _options.size()
	SFX.play("nav")
	_refresh_cursor()


func _on_option_gui(event: InputEvent, index: int) -> void:
	if index >= _options.size():
		return
	if event is InputEventMouseMotion and _cursor != index:
		_cursor = index
		_refresh_cursor()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_cursor = index
		_refresh_cursor()
		_activate(_options[index])


func _activate(id: String) -> void:
	SFX.play("confirm")
	match id:
		"resume":
			_resume()
		"menu":
			_go_to_menu()
		"rematch":
			_rematch()
		"create":
			_request_online("create")
		"join":
			_enter_online_join()
		"join_go":
			_submit_join()
		"online":
			_enter_online_menu()
		"start":
			NetworkManager.request_start()
			_status.text = "STARTING..."
		"copy":
			_copy_code()
		"leave":
			NetworkManager.leave_room()
			_enter_online_menu()


func _go_back() -> void:
	match phase:
		Phase.PLAYING:
			_pause()
		Phase.PAUSED:
			_resume()
		Phase.ONLINE_JOIN:
			_enter_online_menu()
		Phase.ONLINE_ROOM:
			NetworkManager.leave_room()
			_enter_online_menu()
		_:
			_go_to_menu()


# --- input --------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		_handle_key(event.physical_keycode)
	elif event is InputEventJoypadButton and event.pressed:
		_handle_pad_button(event.device, event.button_index)


func _handle_key(keycode: int) -> void:
	if keycode == KEY_ESCAPE:
		_go_back()
		return
	if phase == Phase.LOCAL_JOIN:
		if keycode == KEY_SPACE or keycode == KEY_ENTER or keycode == KEY_KP_ENTER:
			_start_local_match()
			return
		for seat in QuadSimulation.SEATS:
			if keycode in SEAT_KEYS[seat]:
				_claim_seat(seat, {"keys": SEAT_KEYS[seat]})
		return
	if phase == Phase.PLAYING:
		return
	if keycode == KEY_UP or keycode == KEY_W:
		_move_cursor(-1)
	elif keycode == KEY_DOWN or keycode == KEY_S:
		_move_cursor(1)
	elif (keycode == KEY_SPACE or keycode == KEY_ENTER or keycode == KEY_KP_ENTER) and not _options.is_empty():
		_activate(_options[_cursor])


func _handle_pad_button(device: int, button: int) -> void:
	if button == JOY_BUTTON_BACK:
		_go_back()
		return
	if phase == Phase.LOCAL_JOIN:
		match button:
			JOY_BUTTON_A:
				_claim_pad_seat(device)
			JOY_BUTTON_B:
				_release_pad_seat(device)
			JOY_BUTTON_START:
				_start_local_match()
		return
	if button == JOY_BUTTON_START:
		if phase == Phase.PLAYING or phase == Phase.PAUSED:
			_go_back()
		elif not _options.is_empty():
			_activate(_options[_cursor])
		return
	if phase == Phase.PLAYING:
		return
	match button:
		JOY_BUTTON_DPAD_UP:
			_move_cursor(-1)
		JOY_BUTTON_DPAD_DOWN:
			_move_cursor(1)
		JOY_BUTTON_A:
			if not _options.is_empty():
				_activate(_options[_cursor])
		JOY_BUTTON_B:
			_go_back()


func _seat_axis(seat: int) -> float:
	var control = _seat_controls[seat]
	if control == null:
		return 0.0
	var vertical := QuadSimulation.normal_axis(seat) == 0
	var axis := 0.0
	if control.has("keys"):
		var keys: Array = control["keys"]
		axis += float(Input.is_physical_key_pressed(keys[1])) - float(Input.is_physical_key_pressed(keys[0]))
	if control.get("arrows", false):
		# One player per PC: WASD or arrows move the paddle the way its wall runs.
		if vertical:
			axis += float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN))
			axis -= float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP))
		else:
			axis += float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT))
			axis -= float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT))
	var device := int(control.get("device", -1))
	if device == -2:
		for pad in Input.get_connected_joypads():
			axis += _pad_axis(pad, vertical)
	elif device >= 0:
		axis += _pad_axis(device, vertical)
	return clampf(axis, -1.0, 1.0)


func _pad_axis(device: int, vertical: bool) -> float:
	var dpad := 0.0
	if vertical:
		dpad = float(Input.is_joy_button_pressed(device, JOY_BUTTON_DPAD_DOWN)) - float(Input.is_joy_button_pressed(device, JOY_BUTTON_DPAD_UP))
	else:
		dpad = float(Input.is_joy_button_pressed(device, JOY_BUTTON_DPAD_RIGHT)) - float(Input.is_joy_button_pressed(device, JOY_BUTTON_DPAD_LEFT))
	if dpad != 0.0:
		return dpad
	return Players.shape_stick(Input.get_joy_axis(device, JOY_AXIS_LEFT_Y if vertical else JOY_AXIS_LEFT_X))


# --- local play ---------------------------------------------------------------

func _cpu_skill() -> float:
	if GameState.ai_difficulty <= 0.8:
		return QuadSimulation.SKILL_EASY
	if GameState.ai_difficulty >= 0.97:
		return QuadSimulation.SKILL_HARD
	return QuadSimulation.SKILL_NORMAL


func _start_cpu_match() -> void:
	_seat_controls = [{"arrows": true, "device": -2}, null, null, null]
	_seat_names = ["YOU", "CPU", "CPU", "CPU"]
	_begin_local_match()


func _enter_local_join() -> void:
	phase = Phase.LOCAL_JOIN
	_seat_controls = [null, null, null, null]
	_seat_names = ["", "", "", ""]
	_join_order = 0
	sim.reset_match([true, true, true, true])
	_court.set_alive(sim.lives)
	_render_state(sim.ball_pos)
	_ball.visible = false
	_show_overlay("PRESS YOUR KEYS TO JOIN", "CONTROLLERS PRESS A", [], "SPACE START   ESC BACK", false)
	_title.position.y = 230.0
	_status.position.y = 284.0
	_hint.position.y = 500.0
	_refresh_seat_labels()


func _claim_seat(seat: int, control: Dictionary) -> void:
	if _seat_controls[seat] != null:
		return
	_join_order += 1
	_seat_controls[seat] = control
	_seat_names[seat] = "P%d" % _join_order
	SFX.play("confirm")
	_refresh_seat_labels()


func _claim_pad_seat(device: int) -> void:
	for seat in QuadSimulation.SEATS:
		var control = _seat_controls[seat]
		if control != null and int(control.get("device", -1)) == device:
			return
	for seat in QuadSimulation.SEATS:
		if _seat_controls[seat] == null:
			_claim_seat(seat, {"device": device})
			return


func _release_pad_seat(device: int) -> void:
	for seat in QuadSimulation.SEATS:
		var control = _seat_controls[seat]
		if control != null and int(control.get("device", -1)) == device:
			_seat_controls[seat] = null
			_seat_names[seat] = ""
			SFX.play("nav")
			_refresh_seat_labels()


func _start_local_match() -> void:
	if not _seat_controls.any(func(control) -> bool: return control != null):
		_status.text = "PRESS YOUR KEYS OR A TO JOIN FIRST"
		SFX.play("nav")
		return
	for seat in QuadSimulation.SEATS:
		if _seat_controls[seat] == null:
			_seat_names[seat] = "CPU"
	SFX.play("confirm")
	_begin_local_match()


func _begin_local_match() -> void:
	var cpu_seats := []
	for control in _seat_controls:
		cpu_seats.append(control == null)
	sim.cpu_skill = _cpu_skill()
	sim.reset_match(cpu_seats)
	_court.set_alive(sim.lives)
	phase = Phase.PLAYING
	_hide_overlay()
	_refresh_seat_labels()
	_render_state(sim.ball_pos)


func _physics_process(delta: float) -> void:
	if mode == "online":
		_online_physics(delta)
		return
	if phase != Phase.PLAYING:
		return
	for seat in QuadSimulation.SEATS:
		if not sim.cpu[seat]:
			sim.set_axis(seat, _seat_axis(seat))
	sim.tick(delta)
	_play_events(sim.events)
	sim.events.clear()
	_render_state(sim.ball_pos)


func _render_state(ball_position: Vector2) -> void:
	for seat in QuadSimulation.SEATS:
		_place_paddle(seat, sim.paddle_pos[seat], sim.is_alive(seat))
	_ball.position = COURT_ORIGIN + ball_position
	_ball.visible = phase != Phase.LOCAL_JOIN and sim.state != QuadSimulation.STATE_OVER
	_refresh_seat_labels()


func _place_paddle(seat: int, along: float, alive: bool) -> void:
	var inset := QuadSimulation.PADDLE_INSET
	var size := QuadSimulation.SIZE
	var local := Vector2(along, size - inset)
	if seat == QuadSimulation.LEFT:
		local = Vector2(inset, along)
	elif seat == QuadSimulation.RIGHT:
		local = Vector2(size - inset, along)
	elif seat == QuadSimulation.TOP:
		local = Vector2(along, inset)
	_paddles[seat].position = COURT_ORIGIN + local
	_paddles[seat].visible = alive


func _refresh_seat_labels() -> void:
	for seat in QuadSimulation.SEATS:
		var big := _seat_big[seat]
		var small := _seat_small[seat]
		match phase:
			Phase.LOCAL_JOIN:
				var joined: bool = _seat_controls[seat] != null
				big.text = _seat_names[seat] if joined else "CPU"
				small.text = ("CONTROLLER" if _seat_controls[seat].has("device") else SEAT_KEY_HINTS[seat]) if joined else SEAT_KEY_HINTS[seat]
				big.modulate.a = 1.0 if joined else 0.35
			Phase.ONLINE_ROOM:
				var human: bool = _online_humans[seat]
				big.text = "YOU" if seat == _online_seat else ("P%d" % (seat + 1) if human else "CPU")
				small.text = "HOST" if seat == _online_host else ("" if human else "OPEN SEAT")
				big.modulate.a = 1.0 if human else 0.35
			Phase.ONLINE_MENU, Phase.ONLINE_JOIN:
				big.text = ""
				small.text = ""
			_:
				big.text = str(sim.lives[seat]) if sim.is_alive(seat) else "OUT"
				small.text = _seat_names[seat]
				big.modulate.a = 1.0 if sim.is_alive(seat) else 0.4


func _play_events(events: Array) -> void:
	var speed_ratio := clampf((sim.ball_vel.length() - QuadSimulation.START_SPEED) / (QuadSimulation.MAX_SPEED - QuadSimulation.START_SPEED), 0.0, 1.0)
	for event in events:
		var world := COURT_ORIGIN + Vector2(float(event.get("x", 270.0)), float(event.get("y", 270.0)))
		match str(event.get("type", "")):
			"paddle":
				SFX.play("paddle", 0.95 + speed_ratio * 0.85)
				ParticleEffects.spawn_paddle_hit(world, INK)
			"wall":
				SFX.play("wall", 0.9 + speed_ratio * 0.35)
				ParticleEffects.spawn_wall_bounce(world)
			"goal":
				_on_life_lost(int(event.get("seat", 0)))
			"out":
				_court.set_alive(sim.lives)
			"win":
				_show_game_over(int(event.get("seat", -1)))


func _on_life_lost(seat: int) -> void:
	SFX.play_score()
	var size := QuadSimulation.SIZE
	var wall := [Vector2(0.0, size * 0.5), Vector2(size, size * 0.5), Vector2(size * 0.5, 0.0), Vector2(size * 0.5, size)]
	ParticleEffects.spawn_score(COURT_ORIGIN + wall[seat], INK)
	_court.set_alive(sim.lives)
	var label := _seat_big[seat]
	label.pivot_offset = label.size * 0.5
	label.scale = Vector2.ONE * 1.25
	create_tween().tween_property(label, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _show_game_over(winner: int) -> void:
	phase = Phase.OVER
	SFX.play_win()
	var mine := _online_seat if mode == "online" else (QuadSimulation.LEFT if mode == "cpu" else -1)
	var title := "NO WINNER"
	if winner >= 0:
		title = "YOU WIN" if winner == mine else "%s WINS" % _winner_name(winner)
	_cursor = 0
	_show_overlay(title, "", [["rematch", "REMATCH"], ["menu", "MENU"]])
	_refresh_seat_labels()


func _winner_name(seat: int) -> String:
	var seat_name := _seat_names[seat]
	return seat_name if not seat_name.is_empty() else QuadSimulation.SEAT_NAMES[seat]


func _rematch() -> void:
	if mode == "online":
		NetworkManager.request_rematch()
		_status.text = "STARTING A NEW MATCH..."
		return
	_begin_local_match()


func _pause() -> void:
	phase = Phase.PAUSED
	_cursor = 0
	var leave := ["leave", "LEAVE MATCH"] if mode == "online" else ["menu", "MENU"]
	_show_overlay("PAUSED" if mode != "online" else "MENU", "THE MATCH KEEPS RUNNING ONLINE" if mode == "online" else "", [["resume", "RESUME"], leave])


func _resume() -> void:
	phase = Phase.PLAYING
	_hide_overlay()


func _go_to_menu() -> void:
	if mode == "online" and NetworkManager.state != NetworkManager.STATE_DISCONNECTED:
		NetworkManager.disconnect_from_server()
	get_tree().paused = false
	get_tree().change_scene_to_file(MENU_SCENE)


# --- online lobby -------------------------------------------------------------

func _enter_online_menu(message: String = "") -> void:
	phase = Phase.ONLINE_MENU
	_pending_action = ""
	_have_snapshot = false
	_cursor = 0
	if NetworkManager.state == NetworkManager.STATE_DISCONNECTED:
		NetworkManager.connect_to_server()
	var status := message if not message.is_empty() else NetworkManager.status_message
	_show_overlay("ONLINE", status, [["create", "CREATE ROOM"], ["join", "JOIN ROOM"], ["menu", "BACK"]], "UP TO 4 PLAYERS   EMPTY SIDES PLAY AS CPU")
	_refresh_seat_labels()


func _enter_online_join() -> void:
	phase = Phase.ONLINE_JOIN
	_cursor = 0
	_show_overlay("JOIN ROOM", "TYPE THE ROOM CODE", [["join_go", "JOIN"], ["online", "BACK"]], "", true, 300.0)
	_code_frame.visible = true
	_code_input.visible = true
	_code_input.text = ""
	_code_input.grab_focus()


func _submit_join() -> void:
	var code := _code_input.text.strip_edges().to_upper()
	if code.length() != 6:
		_status.text = "ENTER THE SIX-CHARACTER ROOM CODE"
		return
	_pending_code = code
	_code_input.release_focus()
	_request_online("join")


func _request_online(action: String) -> void:
	_pending_action = action
	_status.text = "JOINING ROOM..." if action == "join" else "CREATING ROOM..."
	if NetworkManager.state == NetworkManager.STATE_DISCONNECTED:
		NetworkManager.connect_to_server()
	_send_pending_action()


func _send_pending_action() -> void:
	if _pending_action.is_empty() or NetworkManager.state != NetworkManager.STATE_CONNECTED:
		return
	var action := _pending_action
	_pending_action = ""
	if action == "create":
		NetworkManager.create_room(NetworkManager.MODE_QUAD)
	else:
		NetworkManager.join_room(_pending_code, NetworkManager.MODE_QUAD)


func _show_room() -> void:
	phase = Phase.ONLINE_ROOM
	var host := _online_seat == _online_host
	var options := [["copy", "COPY CODE"], ["leave", "LEAVE ROOM"]]
	if host:
		options.push_front(["start", "START MATCH"])
	var players := 0
	for human in _online_humans:
		players += 1 if human else 0
	var status := "%d OF 4 PLAYERS IN" % players
	status += "   EMPTY SIDES PLAY AS CPU" if host else "   WAITING FOR THE HOST TO START"
	_show_overlay("ROOM", status, options, "SHARE THE CODE WITH UP TO THREE FRIENDS", true, 290.0)
	_code.visible = true
	_code.text = NetworkManager.room_code
	_code.position = Vector2(376.0, 210.0)
	_code.size = Vector2(400.0, 56.0)
	_refresh_seat_labels()


func _copy_code() -> void:
	var code := NetworkManager.room_code.strip_edges()
	if code.is_empty():
		return
	if OS.has_feature("web"):
		JavaScriptBridge.eval("navigator.clipboard.writeText('%s')" % code)
	else:
		DisplayServer.clipboard_set(code)
	_status.text = "ROOM CODE COPIED"


func _on_code_gui(event: InputEvent) -> void:
	if phase == Phase.ONLINE_ROOM and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_copy_code()


func _on_connection_changed(state: int, message: String) -> void:
	if mode != "online":
		return
	if state == NetworkManager.STATE_DISCONNECTED and phase != Phase.ONLINE_MENU:
		_enter_online_menu(message)
		return
	if phase == Phase.ONLINE_MENU or phase == Phase.ONLINE_JOIN:
		if state == NetworkManager.STATE_CONNECTED and not _pending_action.is_empty():
			_send_pending_action()
		elif _pending_action.is_empty() and not message.is_empty():
			_status.text = message


func _on_online_error(message: String) -> void:
	if mode != "online":
		return
	_pending_action = ""
	if phase in [Phase.ONLINE_MENU, Phase.ONLINE_JOIN, Phase.ONLINE_ROOM, Phase.OVER]:
		_status.text = message


## An older server ignores the four-player request and opens a 2-player room.
func _on_two_player_room(_code_value: String, _side: String, _status_text: String) -> void:
	if mode != "online":
		return
	NetworkManager.leave_room()
	_enter_online_menu("THIS SERVER DOESN'T SUPPORT 4 PLAYERS YET")


func _on_quad_room_joined(_code_value: String, seat: int) -> void:
	_online_seat = seat
	_online_host = seat
	_online_humans = [false, false, false, false]
	_online_humans[seat] = true
	_cursor = 0
	_show_room()


func _on_quad_lobby_changed(lobby: Dictionary) -> void:
	var humans = lobby.get("seats", [])
	if humans is Array and humans.size() == QuadSimulation.SEATS:
		_online_humans = humans.duplicate()
	_online_seat = int(lobby.get("you", _online_seat))
	_online_host = int(lobby.get("host", _online_host))
	if phase == Phase.ONLINE_ROOM:
		_show_room()


func _on_quad_started() -> void:
	if mode != "online":
		return
	for seat in QuadSimulation.SEATS:
		var human: bool = _online_humans[seat]
		_seat_names[seat] = "YOU" if seat == _online_seat else ("P%d" % (seat + 1) if human else "CPU")
		_seat_controls[seat] = {"arrows": true, "device": -2} if seat == _online_seat else null
	_have_snapshot = false
	_over_shown = false
	_ball_error = Vector2.ZERO
	_paddle_error = [0.0, 0.0, 0.0, 0.0]
	_history_t.clear()
	_history_p.clear()
	_history_v.clear()
	phase = Phase.PLAYING
	_hide_overlay()


# --- online play --------------------------------------------------------------

func _now() -> float:
	return Time.get_ticks_usec() / 1000000.0


func _lead_rtt() -> float:
	return clampf(NetworkManager.rtt_seconds, 0.0, ONLINE_MAX_LEAD_RTT)


## The view runs ahead of the latest snapshot by its age plus one round trip,
## which is when this player's paddle input lands on the server.
func _lead(now: float) -> float:
	return clampf(now - _snapshot_time, 0.0, ONLINE_MAX_SNAPSHOT_AGE) + _lead_rtt()


func _on_quad_snapshot(data: Dictionary) -> void:
	if mode != "online" or not phase in [Phase.PLAYING, Phase.PAUSED, Phase.OVER]:
		return
	var now := _now()
	var was_playing := sim.state == QuadSimulation.STATE_PLAY
	var old_ball := Vector2.ZERO
	var old_paddles: Array[float] = [0.0, 0.0, 0.0, 0.0]
	if _have_snapshot:
		if was_playing:
			old_ball = _predict_ball(now, 0.0)["pos"] + _ball_error
		for seat in QuadSimulation.SEATS:
			old_paddles[seat] = _remote_predicted(seat, now) + _paddle_error[seat]
	var previous_lives := sim.lives.duplicate()
	sim.apply_snapshot(data)
	_snapshot_time = now
	if not _have_snapshot:
		_have_snapshot = true
		if _online_seat >= 0:
			_local_pos = sim.paddle_pos[_online_seat]
	else:
		_ball_error = Vector2.ZERO
		if sim.state == QuadSimulation.STATE_PLAY:
			# A fresh serve starts from the centre spot the ball was waiting on,
			# then glides into the predicted path instead of skipping ahead.
			var shown := old_ball if was_playing else Vector2.ONE * QuadSimulation.SIZE * 0.5
			_ball_error = shown - _predict_ball(now, 0.0)["pos"]
			if _ball_error.length() > ONLINE_SNAP_DISTANCE:
				_ball_error = Vector2.ZERO
		for seat in QuadSimulation.SEATS:
			_paddle_error[seat] = old_paddles[seat] - _remote_predicted(seat, now)
			if absf(_paddle_error[seat]) > ONLINE_SNAP_DISTANCE:
				_paddle_error[seat] = 0.0
		for seat in QuadSimulation.SEATS:
			if sim.lives[seat] < int(previous_lives[seat]):
				_on_life_lost(seat)
	_court.set_alive(sim.lives)
	if sim.state == QuadSimulation.STATE_OVER:
		if not _over_shown:
			_over_shown = true
			_show_game_over(sim.winner)
	else:
		_over_shown = false


func _online_physics(delta: float) -> void:
	if not _have_snapshot or not phase in [Phase.PLAYING, Phase.PAUSED, Phase.OVER]:
		return
	var now := _now()
	if _online_seat >= 0 and sim.is_alive(_online_seat):
		_update_local_paddle(delta, now)
	var decay := exp(-ONLINE_ERROR_DECAY * delta)
	var max_step := ONLINE_MAX_CORRECTION_SPEED * delta
	var ball_step := _ball_error * (1.0 - decay)
	_ball_error -= ball_step.limit_length(max_step) if ball_step.length() > 0.0 else Vector2.ZERO
	for seat in QuadSimulation.SEATS:
		_paddle_error[seat] *= decay
		var along := _local_pos if seat == _online_seat else _remote_predicted(seat, now) + _paddle_error[seat]
		_place_paddle(seat, clampf(along, QuadSimulation.paddle_min(), QuadSimulation.paddle_max()), sim.is_alive(seat))
	if sim.state == QuadSimulation.STATE_PLAY:
		var predicted := _predict_ball(now, delta)
		_ball.position = COURT_ORIGIN + predicted["pos"] + _ball_error
		_ball.visible = true
		_play_events(predicted["events"])
	else:
		_ball.position = COURT_ORIGIN + Vector2.ONE * QuadSimulation.SIZE * 0.5
		_ball.visible = sim.state == QuadSimulation.STATE_COUNTDOWN
	_refresh_seat_labels()


func _update_local_paddle(delta: float, now: float) -> void:
	var axis := _seat_axis(_online_seat) if phase == Phase.PLAYING else 0.0
	var before := _local_pos
	_local_pos = clampf(_local_pos + axis * QuadSimulation.PADDLE_SPEED * delta, QuadSimulation.paddle_min(), QuadSimulation.paddle_max())
	if absf(_local_pos - before) > 0.001:
		_local_idle = 0.0
	else:
		_local_idle += delta
		# Only reconcile once the server has had time to see us standing still.
		if _local_idle > ONLINE_LOCAL_IDLE_RESYNC + _lead_rtt():
			var server_pos := sim.paddle_pos[_online_seat]
			if absf(server_pos - _local_pos) > 0.5:
				_local_pos = lerpf(_local_pos, server_pos, 1.0 - exp(-ONLINE_LOCAL_RESYNC_RATE * delta))
	_local_vel = (_local_pos - before) / delta if delta > 0.0 else 0.0
	_history_t.append(now)
	_history_p.append(_local_pos)
	_history_v.append(_local_vel)
	var stale := 0
	while stale < _history_t.size() and _history_t[stale] < now - ONLINE_HISTORY_SECONDS:
		stale += 1
	if stale > 0:
		_history_t = _history_t.slice(stale)
		_history_p = _history_p.slice(stale)
		_history_v = _history_v.slice(stale)
	NetworkManager.send_input(axis, _local_pos)


## Paddle position and velocity `offset` seconds after the latest snapshot.
func _sample(seat: int, offset: float) -> Vector2:
	if seat == _online_seat:
		return _local_at(_snapshot_time - _lead_rtt() + offset)
	var velocity := sim.paddle_vel[seat]
	var ahead := minf(offset, ONLINE_REMOTE_EXTRAPOLATION)
	var along := clampf(sim.paddle_pos[seat] + velocity * ahead, QuadSimulation.paddle_min(), QuadSimulation.paddle_max())
	return Vector2(along, velocity if offset <= ONLINE_REMOTE_EXTRAPOLATION else 0.0)


func _remote_predicted(seat: int, now: float) -> float:
	return _sample(seat, _lead(now)).x


func _local_at(time: float) -> Vector2:
	var count := _history_t.size()
	if count == 0 or time >= _history_t[count - 1]:
		return Vector2(_local_pos, _local_vel)
	for i in range(count - 2, -1, -1):
		if _history_t[i] <= time:
			var span := _history_t[i + 1] - _history_t[i]
			var weight := (time - _history_t[i]) / span if span > 0.0 else 1.0
			return Vector2(lerpf(_history_p[i], _history_p[i + 1], weight), _history_v[i + 1])
	return Vector2(_history_p[0], _history_v[0])


## Replays the latest server ball forward to this player's view time, bouncing
## off paddles where they were (our own from history, others extrapolated).
func _predict_ball(now: float, frame_delta: float) -> Dictionary:
	var lead := _lead(now)
	for seat in QuadSimulation.SEATS:
		_predictor.lives[seat] = sim.lives[seat]
		var start := _sample(seat, 0.0)
		_predictor.paddle_pos[seat] = start.x
		_predictor.paddle_prev[seat] = start.x
		_predictor.paddle_vel[seat] = start.y
	_predictor.ball_pos = sim.ball_pos
	_predictor.ball_vel = sim.ball_vel
	_predictor.hits = sim.hits
	var fresh: Array = []
	var elapsed := 0.0
	while elapsed < lead - 0.000001:
		var step := minf(ONLINE_PREDICT_STEP, lead - elapsed)
		elapsed += step
		for seat in QuadSimulation.SEATS:
			var sample := _sample(seat, elapsed)
			_predictor.paddle_prev[seat] = _predictor.paddle_pos[seat]
			_predictor.paddle_pos[seat] = sample.x
			_predictor.paddle_vel[seat] = sample.y
		_predictor.events.clear()
		var inside := _predictor.advance_ball(step, false)
		if frame_delta > 0.0 and elapsed > lead - frame_delta:
			fresh.append_array(_predictor.events)
		if not inside:
			break
	_predictor.events.clear()
	return {"pos": _predictor.ball_pos, "vel": _predictor.ball_vel, "events": fresh}
