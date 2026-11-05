extends Node2D
## Polygon Pong for 2-7 players: play against AI in the browser, or online
## with friends where AI fills the empty sides. Your own wall is always drawn
## at the bottom of the court.

const ArenaSimulation = preload("res://arena_simulation.gd")
const ArenaCourt = preload("res://arena_court.gd")
const INK_BUTTON_SCRIPT = preload("res://ink_button.gd")
const INK_PANEL_SCRIPT = preload("res://ink_panel.gd")
const INK_THEME = preload("res://ink_theme.tres")
const PADDLE_TEXTURE = preload("res://art/paddle-ink.png")
const BALL_TEXTURE = preload("res://art/ball-ink.png")
const PAPER_TEXTURE = preload("res://art/paper-court.png")
const INK := Color(0.12, 0.12, 0.11, 1.0)
const CENTER := Vector2(576.0, 318.0)
const PADDLE_REGION := Rect2(555, 266, 144, 721)
const BALL_REGION := Rect2(535, 525, 184, 184)
const MORPH_SECONDS := 0.8
const LINE_PADDLE_LENGTH := 70.0

const ONLINE_MAX_SNAPSHOT_AGE := 0.25
const ONLINE_MAX_LEAD_RTT := 0.3
const ONLINE_REMOTE_EXTRAPOLATION := 0.15
const ONLINE_ERROR_DECAY := 12.0
const ONLINE_SNAP_DISTANCE := 360.0
const ONLINE_MAX_CORRECTION_SPEED := 1300.0
const ONLINE_PREDICT_STEP := 1.0 / 120.0
const ONLINE_HISTORY_SECONDS := 1.0
const ONLINE_LOCAL_IDLE_RESYNC := 0.5
const ONLINE_LOCAL_RESYNC_RATE := 10.0

enum Phase { TITLE, SOLO_SETUP, ONLINE_MENU, ONLINE_JOIN, ONLINE_ROOM, PLAYING, PAUSED, OVER }

var phase := Phase.TITLE
var online := false
## Solo matches run here; online it mirrors the latest server snapshot.
var sim := ArenaSimulation.new()
var my_seat := 0
var solo_players := 4
var solo_skill := ArenaSimulation.SKILL_NORMAL
var _predictor := ArenaSimulation.new()
var _court: Node2D
var _paddles: Array[Sprite2D] = []
var _ball: Sprite2D
var _seat_big: Array[Label] = []
var _seat_small: Array[Label] = []
var _seat_names: Array[String] = []
var _play_hint: Label
var _view_rotation := 0.0
var _line_flip := 1.0
var _shown_walls := 0
var _morph_from := PackedVector2Array()
var _morph_removed := -1
var _morph_time := 1.0
var _line_reveal := 0.0
var _swing_flash := 0.0

var _overlay_root: Control
var _dimmer: ColorRect
var _title: Label
var _subtitle: Label
var _status: Label
var _code: Label
var _hint: Label
var _code_frame: Panel
var _code_input: LineEdit
var _option_bgs: Array[Panel] = []
var _option_labels: Array[Label] = []
var _options: Array[String] = []
var _cursor := 0

var _room_size := 4
var _room_host := -1
var _room_humans: Array = []
var _pending_action := ""
var _pending_code := ""
var _have_snapshot := false
var _snapshot_time := 0.0
var _local_pos := 0.0
var _local_vel := 0.0
var _local_idle := 0.0
var _history_t := PackedFloat64Array()
var _history_p := PackedFloat32Array()
var _history_v := PackedFloat32Array()
var _pending_hits: Array[int] = []
var _ball_error := Vector2.ZERO
var _paddle_error: Array[float] = []
var _over_shown := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = false
	_build_court()
	_build_seat_labels()
	_build_overlay()
	NetworkManager.connection_changed.connect(_on_connection_changed)
	NetworkManager.online_error.connect(_on_online_error)
	NetworkManager.room_joined.connect(_on_room_joined)
	NetworkManager.lobby_changed.connect(_on_lobby_changed)
	NetworkManager.match_started.connect(_on_match_started)
	NetworkManager.snapshot_received.connect(_on_snapshot)
	_enter_title()


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
	_court = ArenaCourt.new()
	_court.corner_radius = ArenaSimulation.CORNER_RADIUS
	add_child(_court)
	for _seat in ArenaSimulation.MAX_PLAYERS:
		var paddle := Sprite2D.new()
		paddle.texture = PADDLE_TEXTURE
		paddle.region_enabled = true
		paddle.region_rect = PADDLE_REGION
		paddle.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		paddle.z_index = 1
		paddle.visible = false
		add_child(paddle)
		_paddles.append(paddle)
	_ball = Sprite2D.new()
	_ball.texture = BALL_TEXTURE
	_ball.region_enabled = true
	_ball.region_rect = BALL_REGION
	_ball.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_ball.scale = Vector2.ONE * (ArenaSimulation.BALL_RADIUS * 2.0 / BALL_REGION.size.x)
	_ball.z_index = 2
	_ball.visible = false
	add_child(_ball)


func _build_seat_labels() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 25
	add_child(layer)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = INK_THEME
	layer.add_child(root)
	for _seat in ArenaSimulation.MAX_PLAYERS:
		var big := _make_label(34, HORIZONTAL_ALIGNMENT_CENTER)
		big.size = Vector2(140.0, 40.0)
		root.add_child(big)
		_seat_big.append(big)
		var small := _make_label(15, HORIZONTAL_ALIGNMENT_CENTER)
		small.size = Vector2(140.0, 20.0)
		root.add_child(small)
		_seat_small.append(small)
	_play_hint = _make_label(16, HORIZONTAL_ALIGNMENT_CENTER)
	_play_hint.position = Vector2(176.0, 612.0)
	_play_hint.size = Vector2(800.0, 24.0)
	_play_hint.visible = false
	root.add_child(_play_hint)


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
	_title = _make_label(64, HORIZONTAL_ALIGNMENT_CENTER)
	_overlay_root.add_child(_title)
	_subtitle = _make_label(18, HORIZONTAL_ALIGNMENT_CENTER)
	_overlay_root.add_child(_subtitle)
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
	_title.add_theme_font_size_override("font_size", 40)
	_title.position = Vector2(176.0, 96.0)
	_title.size = Vector2(800.0, 56.0)
	_subtitle.visible = false
	_status.position = Vector2(226.0, 156.0)
	_status.size = Vector2(700.0, 52.0)
	_status.text = status
	_hint.text = hint
	_hint.position = Vector2(76.0, 572.0)
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
	elif event is InputEventMouseButton and event.pressed:
		_cursor = index
		_refresh_cursor()
		if event.button_index == MOUSE_BUTTON_LEFT:
			_activate(_options[index], 1)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_activate(_options[index], -1)


## direction is +1 for select/right and -1 for left on rows that hold a value.
func _activate(id: String, direction: int = 1) -> void:
	match id:
		"solo":
			SFX.play("confirm")
			_enter_solo_setup()
		"players":
			SFX.play("nav")
			solo_players = _wrap_players(solo_players + direction)
			_enter_solo_setup()
		"skill":
			SFX.play("nav")
			solo_skill = _next_skill(solo_skill, direction)
			_enter_solo_setup()
		"go":
			SFX.play("confirm")
			_start_solo()
		"online":
			SFX.play("confirm")
			_enter_online_menu()
		"create":
			SFX.play("confirm")
			_request_online("create")
		"join":
			SFX.play("confirm")
			_enter_online_join()
		"join_go":
			_submit_join()
		"size":
			SFX.play("nav")
			NetworkManager.set_room_size(_wrap_players(_room_size + direction))
		"start":
			SFX.play("confirm")
			NetworkManager.request_start()
			_status.text = "STARTING..."
		"copy":
			_copy_code()
		"leave":
			SFX.play("nav")
			NetworkManager.leave_room()
			_enter_online_menu()
		"resume":
			SFX.play("confirm")
			_resume()
		"again":
			SFX.play("confirm")
			_play_again()
		"menu":
			SFX.play("nav")
			_go_to_title()


func _wrap_players(count: int) -> int:
	var span := ArenaSimulation.MAX_PLAYERS - ArenaSimulation.MIN_PLAYERS + 1
	return ArenaSimulation.MIN_PLAYERS + posmod(count - ArenaSimulation.MIN_PLAYERS, span)


func _next_skill(skill: float, direction: int) -> float:
	var steps := [ArenaSimulation.SKILL_EASY, ArenaSimulation.SKILL_NORMAL, ArenaSimulation.SKILL_HARD]
	var index := 1
	if skill <= 0.8:
		index = 0
	elif skill >= 0.97:
		index = 2
	return steps[posmod(index + direction, steps.size())]


func _skill_name(skill: float) -> String:
	if skill <= 0.8:
		return "EASY"
	if skill >= 0.97:
		return "HARD"
	return "NORMAL"


func _go_back() -> void:
	match phase:
		Phase.PLAYING:
			_pause()
		Phase.PAUSED:
			_resume()
		Phase.SOLO_SETUP, Phase.ONLINE_MENU:
			_go_to_title()
		Phase.ONLINE_JOIN:
			_enter_online_menu()
		Phase.ONLINE_ROOM:
			NetworkManager.leave_room()
			_enter_online_menu()
		Phase.OVER:
			_go_to_title()


# --- input --------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		_handle_key(event.physical_keycode)
	elif event is InputEventJoypadButton and event.pressed:
		_handle_pad_button(event.button_index)


func _handle_key(keycode: int) -> void:
	if keycode == KEY_ESCAPE:
		_go_back()
		return
	if phase == Phase.PLAYING:
		if keycode in [KEY_SPACE, KEY_W, KEY_UP, KEY_ENTER, KEY_KP_ENTER]:
			_swing()
		return
	if keycode == KEY_UP or keycode == KEY_W:
		_move_cursor(-1)
	elif keycode == KEY_DOWN or keycode == KEY_S:
		_move_cursor(1)
	elif keycode == KEY_LEFT or keycode == KEY_A:
		_adjust_value(-1)
	elif keycode == KEY_RIGHT or keycode == KEY_D:
		_adjust_value(1)
	elif (keycode == KEY_SPACE or keycode == KEY_ENTER or keycode == KEY_KP_ENTER) and not _options.is_empty():
		_activate(_options[_cursor], 1)


func _handle_pad_button(button: int) -> void:
	if button == JOY_BUTTON_START or button == JOY_BUTTON_BACK:
		_go_back()
		return
	if phase == Phase.PLAYING:
		if button == JOY_BUTTON_A:
			_swing()
		return
	match button:
		JOY_BUTTON_DPAD_UP:
			_move_cursor(-1)
		JOY_BUTTON_DPAD_DOWN:
			_move_cursor(1)
		JOY_BUTTON_DPAD_LEFT:
			_adjust_value(-1)
		JOY_BUTTON_DPAD_RIGHT:
			_adjust_value(1)
		JOY_BUTTON_A:
			if not _options.is_empty():
				_activate(_options[_cursor], 1)
		JOY_BUTTON_B:
			_go_back()


func _adjust_value(direction: int) -> void:
	if _options.is_empty():
		return
	var id := _options[_cursor]
	if id in ["players", "skill", "size"]:
		_activate(id, direction)


## Left/right on screen. Your wall is drawn at the bottom, and along it the
## paddle coordinate grows to the left, so screen-right is negative.
func _move_axis() -> float:
	var axis := 0.0
	if Input.is_physical_key_pressed(KEY_LEFT) or Input.is_physical_key_pressed(KEY_A):
		axis += 1.0
	if Input.is_physical_key_pressed(KEY_RIGHT) or Input.is_physical_key_pressed(KEY_D):
		axis -= 1.0
	for pad in Input.get_connected_joypads():
		var dpad := float(Input.is_joy_button_pressed(pad, JOY_BUTTON_DPAD_LEFT)) - float(Input.is_joy_button_pressed(pad, JOY_BUTTON_DPAD_RIGHT))
		axis += dpad if dpad != 0.0 else -Players.shape_stick(Input.get_joy_axis(pad, JOY_AXIS_LEFT_X))
	return clampf(axis, -1.0, 1.0)


func _swing() -> void:
	if not sim.is_line() or not sim.is_alive(my_seat):
		return
	_swing_flash = 1.0
	if online:
		var at_tick := sim.tick_number + int(round(_lead(_now()) * ArenaSimulation.SIM_RATE))
		_pending_hits.append(at_tick)
		NetworkManager.send_hit(at_tick)
	else:
		sim.press_hit(my_seat)


# --- title and solo -----------------------------------------------------------

func _enter_title() -> void:
	phase = Phase.TITLE
	online = false
	_cursor = 0
	if NetworkManager.state != NetworkManager.STATE_DISCONNECTED:
		NetworkManager.disconnect_from_server()
	_show_overlay("", "", [["solo", "PLAY VS AI"], ["online", "PLAY ONLINE"]], "UP/DOWN MOVE   SPACE SELECT", true, 300.0)
	_title.text = "PADDLE POLYGON"
	_title.add_theme_font_size_override("font_size", 80)
	_title.position = Vector2(176.0, 118.0)
	_title.size = Vector2(800.0, 92.0)
	_subtitle.visible = true
	_subtitle.text = "2 TO 7 PLAYERS   ONE PADDLE PER SIDE"
	_subtitle.position = Vector2(176.0, 218.0)
	_subtitle.size = Vector2(800.0, 30.0)
	_status.text = ""
	_preview_shape(5)


func _enter_solo_setup() -> void:
	phase = Phase.SOLO_SETUP
	var options := [
		["players", "PLAYERS   <  %d  >" % solo_players],
		["skill", "AI   <  %s  >" % _skill_name(solo_skill)],
		["go", "START"],
		["menu", "BACK"],
	]
	_show_overlay("PLAY VS AI", "YOU AND %d AI   %s" % [solo_players - 1, _shape_name(solo_players)], options, "LEFT/RIGHT CHANGE   SPACE SELECT   ESC BACK", true, 250.0)
	_preview_shape(solo_players)


func _shape_name(players: int) -> String:
	return ["1D LINE", "TRIANGLE", "SQUARE", "PENTAGON", "HEXAGON", "HEPTAGON"][clampi(players - 2, 0, 5)]


func _start_solo() -> void:
	online = false
	my_seat = 0
	var cpu_seats := []
	_seat_names.clear()
	for seat in solo_players:
		cpu_seats.append(seat != 0)
		_seat_names.append("YOU" if seat == 0 else "AI")
	sim.cpu_skill = solo_skill
	sim.reset_match(cpu_seats)
	_begin_play()


func _begin_play() -> void:
	phase = Phase.PLAYING
	_over_shown = false
	_shown_walls = sim.wall_count()
	_morph_time = 1.0
	_line_reveal = 1.0 if sim.is_line() else 0.0
	_hide_overlay()


func _preview_shape(players: int) -> void:
	_play_hint.visible = false
	var preview := ArenaSimulation.new()
	var flags := []
	for _seat in players:
		flags.append(true)
	preview.reset_match(flags)
	_view_rotation = 0.0
	_line_flip = 1.0
	_apply_court_shape(preview, 1.0)
	for paddle in _paddles:
		paddle.visible = false
	_ball.visible = false
	for seat in ArenaSimulation.MAX_PLAYERS:
		_seat_big[seat].visible = false
		_seat_small[seat].visible = false


# --- local play ---------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_swing_flash = maxf(_swing_flash - delta * 4.0, 0.0)
	if online:
		_online_physics(delta)
		return
	if phase == Phase.PLAYING:
		if sim.is_alive(my_seat) and not sim.is_line():
			sim.set_axis(my_seat, _move_axis())
		var order_before := sim.order.duplicate()
		var corners_before := _screen_corners(order_before.size(), _view_rotation) if order_before.size() >= 3 else PackedVector2Array()
		sim.tick(delta)
		_play_events(sim.events)
		sim.events.clear()
		if sim.wall_count() != order_before.size():
			_start_morph(order_before, corners_before)
	if phase in [Phase.PLAYING, Phase.PAUSED, Phase.OVER]:
		_render(sim.ball_pos, delta)


## Remembers the old shape on screen so the court can fold one wall away.
func _start_morph(order_before: Array, corners_before: PackedVector2Array) -> void:
	_morph_from = corners_before
	_morph_removed = -1
	for wall in order_before.size():
		if not sim.order.has(order_before[wall]):
			_morph_removed = wall
	_morph_time = 0.0
	if sim.is_line():
		_line_reveal = 0.0


func _render(ball_local: Vector2, delta: float) -> void:
	_update_view()
	_morph_time = minf(_morph_time + delta / MORPH_SECONDS, 1.0)
	if sim.is_line():
		_line_reveal = minf(_line_reveal + delta / MORPH_SECONDS, 1.0)
	_apply_court_shape(sim, _morph_time)
	var morphing := _morph_time < 1.0
	if sim.is_line():
		_place_line_paddles()
	else:
		var walls := sim.wall_count()
		for index in _paddles.size():
			var paddle := _paddles[index]
			if index >= walls or morphing:
				paddle.visible = false
				continue
			var seat := sim.order[index]
			_place_polygon_paddle(paddle, index, walls, _paddle_along(seat))
	_ball.position = _to_screen(ball_local)
	_ball.visible = sim.state != ArenaSimulation.STATE_OVER and not morphing
	_refresh_seat_labels()
	_refresh_play_hint()


## The only in-game instructions: how to move before the first serve, and how
## to swing once the court becomes a line.
func _refresh_play_hint() -> void:
	var playing := phase == Phase.PLAYING and sim.is_alive(my_seat)
	if playing and sim.is_line():
		_play_hint.text = "SPACE WHEN THE BALL IS IN YOUR ZONE"
	elif playing and sim.state == ArenaSimulation.STATE_COUNTDOWN and sim.wall_count() == sim.seat_count:
		_play_hint.text = "LEFT / RIGHT MOVE YOUR PADDLE"
	else:
		_play_hint.text = ""
	_play_hint.visible = not _play_hint.text.is_empty()


func _paddle_along(seat: int) -> float:
	return _paddle_along_online(seat) if online else sim.paddle_pos[seat]


func _update_view() -> void:
	var wall := sim.wall_of(my_seat)
	if sim.is_line():
		_line_flip = -1.0 if wall == 1 else 1.0
		return
	var walls := sim.wall_count()
	_view_rotation = -TAU * wall / walls if wall >= 0 else 0.0


func _to_screen(local: Vector2) -> Vector2:
	if sim.is_line():
		return CENTER + Vector2(local.x * _line_flip, 0.0)
	return CENTER + local.rotated(_view_rotation)


func _screen_corners(walls: int, rotation: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for index in walls:
		points.append(CENTER + ArenaSimulation.vertex(index, walls).rotated(rotation))
	return points


func _apply_court_shape(source: ArenaSimulation, morph: float) -> void:
	var court := _court as ArenaCourt
	var line := source.is_line()
	if line:
		var half := ArenaSimulation.LINE_LENGTH * 0.5
		var reveal := _line_reveal if phase in [Phase.PLAYING, Phase.PAUSED, Phase.OVER] else 1.0
		court.line_from = CENTER + Vector2(-half * reveal, 0.0)
		court.line_to = CENTER + Vector2(half * reveal, 0.0)
		var left_seat := source.order[0] if _line_flip > 0.0 else source.order[1]
		var right_seat := source.order[1] if _line_flip > 0.0 else source.order[0]
		court.line_zones = Vector2(source.zone[left_seat], source.zone[right_seat]) * reveal
		var mine_left := left_seat == my_seat
		court.zone_flash = Vector2(_swing_flash if mine_left else 0.0, 0.0 if mine_left else _swing_flash)
		court.line_alpha = reveal
		court.polygon_alpha = 1.0 - reveal
		if court.polygon_alpha > 0.01 and _morph_from.size() >= 3:
			var center := Vector2.ZERO
			for point in _morph_from:
				center += point
			center /= _morph_from.size()
			var shrunk := PackedVector2Array()
			for point in _morph_from:
				shrunk.append(point.lerp(center, reveal))
			court.corners = shrunk
	else:
		var target := _screen_corners(source.wall_count(), _view_rotation)
		court.line_alpha = 0.0
		court.polygon_alpha = 1.0
		if morph < 1.0 and _morph_from.size() == target.size() + 1 and _morph_removed >= 0:
			court.corners = _fold_corners(_morph_from, target, _morph_removed, morph)
		else:
			court.corners = target
	court.queue_redraw()


## Blends the old polygon into the new one by collapsing the removed wall.
func _fold_corners(from: PackedVector2Array, to: PackedVector2Array, removed: int, weight: float) -> PackedVector2Array:
	var count := to.size()
	var eased := ease(weight, -2.0)
	var points := PackedVector2Array()
	for index in from.size():
		var target_index := index
		if index > removed:
			target_index = index - 1
		points.append(from[index].lerp(to[posmod(target_index, count)], eased))
	return points


func _place_polygon_paddle(paddle: Sprite2D, wall: int, walls: int, along: float) -> void:
	var frame := ArenaSimulation.wall_frame(wall, walls)
	var local: Vector2 = frame[0] + frame[1] * along + frame[2] * ArenaSimulation.PADDLE_INSET
	var tangent: Vector2 = frame[1].rotated(_view_rotation)
	paddle.position = CENTER + local.rotated(_view_rotation)
	paddle.rotation = tangent.angle() - PI * 0.5
	paddle.scale = Vector2(ArenaSimulation.PADDLE_THICKNESS / PADDLE_REGION.size.x, ArenaSimulation.paddle_length(walls) / PADDLE_REGION.size.y)
	paddle.visible = true


func _place_line_paddles() -> void:
	var reveal := _line_reveal
	for index in _paddles.size():
		var paddle := _paddles[index]
		if index >= 2:
			paddle.visible = false
			continue
		var seat := sim.order[index]
		var x := sim.line_end(seat) * _line_flip * reveal
		paddle.position = CENTER + Vector2(x, 0.0)
		paddle.rotation = 0.0
		paddle.scale = Vector2(ArenaSimulation.PADDLE_THICKNESS / PADDLE_REGION.size.x, LINE_PADDLE_LENGTH / PADDLE_REGION.size.y)
		paddle.visible = reveal > 0.5


func _refresh_seat_labels() -> void:
	for seat in ArenaSimulation.MAX_PLAYERS:
		var big := _seat_big[seat]
		var small := _seat_small[seat]
		var shown := seat < sim.seat_count and _morph_time >= 1.0
		var wall := sim.wall_of(seat) if seat < sim.seat_count else -1
		if not shown or wall == -1:
			big.visible = false
			small.visible = false
			continue
		var anchor := Vector2.ZERO
		if sim.is_line():
			var side := -1.0 if sim.line_end(seat) * _line_flip < 0.0 else 1.0
			anchor = CENTER + Vector2(side * (ArenaSimulation.LINE_LENGTH * 0.5 + 70.0), 0.0)
		else:
			var walls := sim.wall_count()
			var middle := (ArenaSimulation.vertex(wall, walls) + ArenaSimulation.vertex(wall + 1, walls)) * 0.5
			var outward := middle.rotated(_view_rotation)
			anchor = CENTER + outward + outward.normalized() * 40.0
		big.visible = true
		small.visible = true
		big.text = str(sim.lives[seat])
		small.text = _seat_names[seat] if seat < _seat_names.size() else ""
		big.position = anchor - Vector2(big.size.x * 0.5, big.size.y * 0.5 + 8.0)
		small.position = anchor + Vector2(-small.size.x * 0.5, 14.0)


func _play_events(events: Array) -> void:
	var speed_ratio := clampf((sim.ball_vel.length() - ArenaSimulation.START_SPEED) / (ArenaSimulation.MAX_SPEED - ArenaSimulation.START_SPEED), 0.0, 1.0)
	for event in events:
		var local := Vector2(float(event.get("x", 0.0)), float(event.get("y", 0.0)))
		var world := _to_screen(local)
		match str(event.get("type", "")):
			"paddle":
				SFX.play("paddle", 0.95 + speed_ratio * 0.85)
				ParticleEffects.spawn_paddle_hit(world, INK)
			"wall":
				SFX.play("wall", 0.9 + speed_ratio * 0.35)
				ParticleEffects.spawn_wall_bounce(world)
			"whiff":
				if int(event.get("seat", -1)) == my_seat:
					SFX.play("nav", 0.7)
			"goal":
				_on_life_lost(int(event.get("seat", -1)), world)
			"win":
				_show_game_over(int(event.get("seat", -1)))


func _on_life_lost(seat: int, where: Vector2) -> void:
	SFX.play_score()
	ParticleEffects.spawn_score(where, INK)
	if seat >= 0 and seat < _seat_big.size():
		var label := _seat_big[seat]
		label.pivot_offset = label.size * 0.5
		label.scale = Vector2.ONE * 1.3
		create_tween().tween_property(label, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _show_game_over(winner: int) -> void:
	phase = Phase.OVER
	SFX.play_win()
	var title := "NO WINNER"
	if winner >= 0:
		title = "YOU WIN" if winner == my_seat else "%s WINS" % _winner_name(winner)
	_cursor = 0
	_show_overlay(title, "", [["again", "PLAY AGAIN"], ["menu", "MENU"]])


func _winner_name(seat: int) -> String:
	var seat_name := _seat_names[seat] if seat < _seat_names.size() else ""
	return seat_name if not seat_name.is_empty() and seat_name != "AI" else "P%d" % (seat + 1)


func _play_again() -> void:
	if online:
		NetworkManager.request_rematch()
		_status.text = "STARTING A NEW MATCH..."
		return
	_start_solo()


func _pause() -> void:
	phase = Phase.PAUSED
	_cursor = 0
	if online:
		_show_overlay("MENU", "THE MATCH KEEPS RUNNING ONLINE", [["resume", "RESUME"], ["leave", "LEAVE MATCH"]])
	else:
		_show_overlay("PAUSED", "", [["resume", "RESUME"], ["menu", "MENU"]])


func _resume() -> void:
	phase = Phase.PLAYING
	_hide_overlay()


func _go_to_title() -> void:
	_enter_title()


# --- online lobby -------------------------------------------------------------

func _enter_online_menu(message: String = "") -> void:
	phase = Phase.ONLINE_MENU
	online = true
	_pending_action = ""
	_have_snapshot = false
	_cursor = 0
	if NetworkManager.state == NetworkManager.STATE_DISCONNECTED:
		NetworkManager.connect_to_server()
	var status := message if not message.is_empty() else NetworkManager.status_message
	_show_overlay("ONLINE", status, [["create", "CREATE ROOM"], ["join", "JOIN ROOM"], ["menu", "BACK"]], "UP TO 7 PLAYERS   EMPTY SIDES PLAY AS AI")
	_preview_shape(4)


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
	SFX.play("confirm")
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
		NetworkManager.create_room(_room_size)
	else:
		NetworkManager.join_room(_pending_code)


func _show_room() -> void:
	phase = Phase.ONLINE_ROOM
	my_seat = NetworkManager.seat
	var host := my_seat == _room_host
	var players := 0
	for human in _room_humans:
		players += 1 if human else 0
	var options := []
	if host:
		options.append(["size", "PLAYERS   <  %d  >" % _room_size])
		options.append(["start", "START MATCH"])
	options.append(["copy", "COPY CODE"])
	options.append(["leave", "LEAVE ROOM"])
	var status := "%d OF %d JOINED   %s" % [players, _room_size, _shape_name(_room_size)]
	status += "   EMPTY SIDES PLAY AS AI" if host else "   WAITING FOR THE HOST"
	_show_overlay("ROOM", status, options, "SHARE THE CODE   LEFT/RIGHT CHANGES PLAYERS", true, 290.0)
	_code.visible = true
	_code.text = NetworkManager.room_code
	_code.position = Vector2(376.0, 210.0)
	_code.size = Vector2(400.0, 56.0)
	_preview_shape(_room_size)


func _copy_code() -> void:
	var code := NetworkManager.room_code.strip_edges()
	if code.is_empty():
		return
	SFX.play("confirm")
	if OS.has_feature("web"):
		JavaScriptBridge.eval("navigator.clipboard.writeText('%s')" % code)
	else:
		DisplayServer.clipboard_set(code)
	_status.text = "ROOM CODE COPIED"


func _on_code_gui(event: InputEvent) -> void:
	if phase == Phase.ONLINE_ROOM and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_copy_code()


func _on_connection_changed(state: int, message: String) -> void:
	if not online:
		return
	if state == NetworkManager.STATE_DISCONNECTED:
		# A failed or dropped connection clears any waiting request so the
		# player sees why and can try again.
		_pending_action = ""
		if phase != Phase.ONLINE_MENU:
			_enter_online_menu(message)
		else:
			_status.text = message
		return
	if phase == Phase.ONLINE_MENU or phase == Phase.ONLINE_JOIN:
		if state == NetworkManager.STATE_CONNECTED and not _pending_action.is_empty():
			_send_pending_action()
		elif _pending_action.is_empty() and not message.is_empty():
			_status.text = message


func _on_online_error(message: String) -> void:
	if not online:
		return
	_pending_action = ""
	if phase in [Phase.ONLINE_MENU, Phase.ONLINE_JOIN, Phase.ONLINE_ROOM, Phase.OVER]:
		_status.text = message


func _on_room_joined(_code_value: String, seat: int) -> void:
	my_seat = seat
	_room_host = seat
	_room_humans = []
	for index in _room_size:
		_room_humans.append(index == seat)
	_cursor = 0
	_show_room()


func _on_lobby_changed(lobby: Dictionary) -> void:
	_room_size = int(lobby.get("size", _room_size))
	var humans = lobby.get("seats", [])
	if humans is Array:
		_room_humans = humans.duplicate()
	my_seat = int(lobby.get("you", my_seat))
	_room_host = int(lobby.get("host", _room_host))
	if phase == Phase.ONLINE_ROOM:
		_show_room()


func _on_match_started() -> void:
	if not online:
		return
	_seat_names.clear()
	for seat in _room_size:
		var human: bool = seat < _room_humans.size() and _room_humans[seat]
		_seat_names.append("YOU" if seat == my_seat else ("P%d" % (seat + 1) if human else "AI"))
	_have_snapshot = false
	_over_shown = false
	_ball_error = Vector2.ZERO
	_paddle_error.clear()
	for _seat in ArenaSimulation.MAX_PLAYERS:
		_paddle_error.append(0.0)
	_history_t.clear()
	_history_p.clear()
	_history_v.clear()
	_pending_hits.clear()
	phase = Phase.PLAYING
	_hide_overlay()


# --- online play --------------------------------------------------------------

func _now() -> float:
	return Time.get_ticks_usec() / 1000000.0


func _lead_rtt() -> float:
	return clampf(NetworkManager.rtt_seconds, 0.0, ONLINE_MAX_LEAD_RTT)


## The view runs ahead of the latest snapshot by its age plus one round trip,
## which is when this player's input lands on the server.
func _lead(now: float) -> float:
	return clampf(now - _snapshot_time, 0.0, ONLINE_MAX_SNAPSHOT_AGE) + _lead_rtt()


func _on_snapshot(data: Dictionary) -> void:
	if not online or not phase in [Phase.PLAYING, Phase.PAUSED, Phase.OVER]:
		return
	var now := _now()
	var walls_before := sim.wall_count()
	var was_playing := sim.state == ArenaSimulation.STATE_PLAY
	var was_line := sim.is_line()
	var old_ball := Vector2.ZERO
	var old_paddles: Array[float] = []
	if _have_snapshot:
		if was_playing:
			old_ball = _predict_ball(now, 0.0)["pos"] + _ball_error
		for seat in sim.seat_count:
			old_paddles.append(_remote_predicted(seat, now) + _paddle_error[seat])
	var previous_lives := sim.lives.duplicate()
	var previous_order := sim.order.duplicate()
	var previous_corners := _screen_corners(walls_before, _view_rotation) if walls_before >= 3 else PackedVector2Array()
	sim.apply_snapshot(data)
	_snapshot_time = now
	var unconfirmed: Array[int] = []
	for at_tick in _pending_hits:
		if at_tick > sim.tick_number:
			unconfirmed.append(at_tick)
	_pending_hits = unconfirmed
	if not _have_snapshot:
		_have_snapshot = true
		_shown_walls = sim.wall_count()
		_line_reveal = 1.0 if sim.is_line() else 0.0
		if sim.wall_of(my_seat) >= 0:
			_local_pos = sim.paddle_pos[my_seat]
		return
	if sim.wall_count() != walls_before:
		_start_morph(previous_order, previous_corners)
		if sim.wall_of(my_seat) >= 0:
			_local_pos = sim.paddle_pos[my_seat]
	_ball_error = Vector2.ZERO
	if sim.state == ArenaSimulation.STATE_PLAY and was_line == sim.is_line():
		# A fresh serve glides out of the centre instead of skipping ahead.
		var shown := old_ball if was_playing else Vector2.ZERO
		_ball_error = shown - _predict_ball(now, 0.0)["pos"]
		if _ball_error.length() > ONLINE_SNAP_DISTANCE:
			_ball_error = Vector2.ZERO
	for seat in mini(old_paddles.size(), sim.seat_count):
		_paddle_error[seat] = old_paddles[seat] - _remote_predicted(seat, now)
		if absf(_paddle_error[seat]) > ONLINE_SNAP_DISTANCE or sim.wall_count() != walls_before:
			_paddle_error[seat] = 0.0
	for seat in mini(previous_lives.size(), sim.seat_count):
		if sim.lives[seat] < int(previous_lives[seat]):
			_on_life_lost(seat, CENTER)
	if sim.state == ArenaSimulation.STATE_OVER:
		if not _over_shown:
			_over_shown = true
			_show_game_over(sim.winner)
	else:
		_over_shown = false


func _online_physics(delta: float) -> void:
	if not _have_snapshot or not phase in [Phase.PLAYING, Phase.PAUSED, Phase.OVER]:
		return
	var now := _now()
	if sim.wall_of(my_seat) >= 0 and not sim.is_line():
		_update_local_paddle(delta, now)
	var decay := exp(-ONLINE_ERROR_DECAY * delta)
	var ball_step := _ball_error * (1.0 - decay)
	_ball_error -= ball_step.limit_length(ONLINE_MAX_CORRECTION_SPEED * delta)
	for seat in _paddle_error.size():
		_paddle_error[seat] *= decay
	var ball_local := Vector2.ZERO
	if sim.state == ArenaSimulation.STATE_PLAY:
		var predicted := _predict_ball(now, delta)
		ball_local = predicted["pos"] + _ball_error
		_play_events(predicted["events"])
	_render(ball_local, delta)


func _paddle_along_online(seat: int) -> float:
	if seat == my_seat:
		return _local_pos
	var walls := maxi(sim.wall_count(), 3)
	return clampf(_remote_predicted(seat, _now()) + _paddle_error[seat], ArenaSimulation.paddle_min(walls), ArenaSimulation.paddle_max(walls))


func _update_local_paddle(delta: float, now: float) -> void:
	var walls := sim.wall_count()
	var axis := _move_axis() if phase == Phase.PLAYING else 0.0
	var before := _local_pos
	_local_pos = clampf(_local_pos + axis * ArenaSimulation.PADDLE_SPEED * delta, ArenaSimulation.paddle_min(walls), ArenaSimulation.paddle_max(walls))
	if absf(_local_pos - before) > 0.001:
		_local_idle = 0.0
	else:
		_local_idle += delta
		# Only reconcile once the server has had time to see us standing still.
		if _local_idle > ONLINE_LOCAL_IDLE_RESYNC + _lead_rtt():
			var server_pos := sim.paddle_pos[my_seat]
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
	if seat == my_seat:
		return _local_at(_snapshot_time - _lead_rtt() + offset)
	var walls := maxi(sim.wall_count(), 3)
	var velocity := sim.paddle_vel[seat]
	var ahead := minf(offset, ONLINE_REMOTE_EXTRAPOLATION)
	var along := clampf(sim.paddle_pos[seat] + velocity * ahead, ArenaSimulation.paddle_min(walls), ArenaSimulation.paddle_max(walls))
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


## Replays the latest server ball forward to this player's view time. In the
## polygon it bounces off paddles where they were; on the line it applies our
## own swings and waits at the opponent's end until the server says what happened.
func _predict_ball(now: float, frame_delta: float) -> Dictionary:
	var lead := _lead(now)
	_predictor.seat_count = sim.seat_count
	_predictor.lives = sim.lives.duplicate()
	_predictor.order = sim.order.duplicate()
	_predictor.zone = sim.zone.duplicate()
	_predictor.cpu = sim.cpu.duplicate()
	_predictor.paddle_pos = sim.paddle_pos.duplicate()
	_predictor.paddle_prev = sim.paddle_pos.duplicate()
	_predictor.paddle_vel = sim.paddle_vel.duplicate()
	_predictor._hit_lock.clear()
	for _seat in sim.seat_count:
		_predictor._hit_lock.append(0.0)
	_predictor.state = ArenaSimulation.STATE_PLAY
	_predictor.ball_pos = sim.ball_pos
	_predictor.ball_vel = sim.ball_vel
	_predictor.hits = sim.hits
	var line := sim.is_line()
	var fresh: Array = []
	var elapsed := 0.0
	var hit_index := 0
	var hits := _pending_hits.duplicate()
	hits.sort()
	while elapsed < lead - 0.000001:
		var step := minf(ONLINE_PREDICT_STEP, lead - elapsed)
		elapsed += step
		_predictor.events.clear()
		var inside := true
		if line:
			var at_tick := sim.tick_number + int(round(elapsed * ArenaSimulation.SIM_RATE))
			while hit_index < hits.size() and hits[hit_index] <= at_tick:
				_predictor._hit_lock[my_seat] = 0.0
				_predictor.press_hit(my_seat)
				hit_index += 1
			inside = _predictor.advance_line(step, false)
			_hold_at_opponent_end()
		else:
			for seat in sim.seat_count:
				var sample := _sample(seat, elapsed)
				_predictor.paddle_prev[seat] = _predictor.paddle_pos[seat]
				_predictor.paddle_pos[seat] = sample.x
				_predictor.paddle_vel[seat] = sample.y
			inside = _predictor.advance_ball(step, false)
		if frame_delta > 0.0 and elapsed > lead - frame_delta:
			fresh.append_array(_predictor.events)
		if not inside:
			break
	_predictor.events.clear()
	return {"pos": _predictor.ball_pos, "vel": _predictor.ball_vel, "events": fresh}


func _hold_at_opponent_end() -> void:
	for seat in _predictor.order:
		if seat == my_seat:
			continue
		var end := _predictor.line_end(seat)
		if end > 0.0 and _predictor.ball_pos.x > end:
			_predictor.ball_pos.x = end
		elif end < 0.0 and _predictor.ball_pos.x < end:
			_predictor.ball_pos.x = end
