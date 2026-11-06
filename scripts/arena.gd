extends Node2D
## Paddle Polygon: Pong for 2 to 7 players.
##
## This script runs the game flow: which screen is showing, what your keys
## do, and starting matches. The other scripts do the actual work:
##   arena_simulation.gd - the rules (also used by the server)
##   court_view.gd       - drawing the court
##   menu_overlay.gd     - the menus
##   online_view.gd      - hiding network delay in online matches

const ArenaSimulation = preload("res://scripts/arena_simulation.gd")
const CourtView = preload("res://scripts/court_view.gd")
const MenuOverlay = preload("res://scripts/menu_overlay.gd")
const OnlineView = preload("res://scripts/online_view.gd")

enum Phase { TITLE, SOLO_SETUP, ONLINE_MENU, ONLINE_JOIN, ONLINE_ROOM, PLAYING, PAUSED, OVER }

const SHAPE_NAMES := ["1D LINE", "TRIANGLE", "SQUARE", "PENTAGON", "HEXAGON", "HEPTAGON"]
const SKILLS := [ArenaSimulation.SKILL_EASY, ArenaSimulation.SKILL_NORMAL, ArenaSimulation.SKILL_HARD]
const SKILL_NAMES := ["EASY", "NORMAL", "HARD"]
const STICK_DEADZONE := 0.18

var phase := Phase.TITLE
var online := false
## The match being played (solo), or a copy of the server's match (online).
var sim := ArenaSimulation.new()
var my_seat := 0
var player_names: Array[String] = []

# Solo setup choices.
var solo_players := 4
var solo_skill := 1

# Online room state.
var room_size := 4
var room_host := -1
var room_people: Array = []
var _waiting_for := ""
var _join_code := ""

var court: CourtView
var menu: MenuOverlay
var online_view := OnlineView.new()


func _ready() -> void:
	court = CourtView.new()
	add_child(court)
	menu = MenuOverlay.new()
	add_child(menu)
	menu.chosen.connect(_on_menu_choice)
	menu.code_clicked.connect(_copy_room_code)
	menu.code_entered.connect(_join_typed_code)
	Network.connection_changed.connect(_on_connection_changed)
	Network.online_error.connect(_on_online_error)
	Network.room_joined.connect(_on_room_joined)
	Network.lobby_changed.connect(_on_lobby_changed)
	Network.match_started.connect(_on_online_match_started)
	Network.snapshot_received.connect(_on_snapshot)
	show_title()


# --- screens ------------------------------------------------------------------

func show_title() -> void:
	phase = Phase.TITLE
	online = false
	menu.cursor = 0
	if Network.state != Network.STATE_DISCONNECTED:
		Network.disconnect_from_server()
	menu.open("", "", [["solo", "PLAY VS AI"], ["online", "PLAY ONLINE"]], "UP/DOWN MOVE   SPACE SELECT")
	menu.show_big_title("PADDLE POLYGON", "2 TO 7 PLAYERS   ONE PADDLE PER SIDE")
	court.show_preview(5)


func show_solo_setup() -> void:
	phase = Phase.SOLO_SETUP
	var buttons := [
		["players", "PLAYERS   <  %d  >" % solo_players],
		["skill", "AI   <  %s  >" % SKILL_NAMES[solo_skill]],
		["go", "START"],
		["back", "BACK"],
	]
	var description := "YOU AND %d AI   %s" % [solo_players - 1, _shape_name(solo_players)]
	menu.open("PLAY VS AI", description, buttons, "LEFT/RIGHT CHANGE   SPACE SELECT   ESC BACK", 250.0)
	court.show_preview(solo_players)


func show_online_menu(message: String = "") -> void:
	phase = Phase.ONLINE_MENU
	online = true
	_waiting_for = ""
	online_view.have_snapshot = false
	menu.cursor = 0
	if Network.state == Network.STATE_DISCONNECTED:
		Network.connect_to_server()
	var status := message if not message.is_empty() else Network.status_message
	menu.open("ONLINE", status, [["create", "CREATE ROOM"], ["join", "JOIN ROOM"], ["back", "BACK"]], "UP TO 7 PLAYERS   EMPTY SIDES PLAY AS AI")
	court.show_preview(4)


func show_join_screen() -> void:
	phase = Phase.ONLINE_JOIN
	menu.cursor = 0
	menu.open("JOIN ROOM", "TYPE THE ROOM CODE", [["join_code", "JOIN"], ["online", "BACK"]])
	menu.show_code_box()


func show_room() -> void:
	phase = Phase.ONLINE_ROOM
	my_seat = Network.seat
	var i_am_host := my_seat == room_host
	var joined := room_people.count(true)
	var buttons := []
	if i_am_host:
		buttons.append(["size", "PLAYERS   <  %d  >" % room_size])
		buttons.append(["start", "START MATCH"])
	buttons.append(["copy", "COPY CODE"])
	buttons.append(["leave", "LEAVE ROOM"])
	var status := "%d OF %d JOINED   %s" % [joined, room_size, _shape_name(room_size)]
	status += "   EMPTY SIDES PLAY AS AI" if i_am_host else "   WAITING FOR THE HOST"
	menu.open("ROOM", status, buttons, "SHARE THE CODE   LEFT/RIGHT CHANGES PLAYERS", 290.0)
	menu.show_code(Network.room_code)
	court.show_preview(room_size)


func pause() -> void:
	phase = Phase.PAUSED
	menu.cursor = 0
	if online:
		menu.open("MENU", "THE MATCH KEEPS RUNNING ONLINE", [["resume", "RESUME"], ["leave", "LEAVE MATCH"]])
	else:
		menu.open("PAUSED", "", [["resume", "RESUME"], ["back", "MENU"]])


func resume() -> void:
	phase = Phase.PLAYING
	menu.close()


func show_game_over(winner: int) -> void:
	phase = Phase.OVER
	Sound.play_win()
	var heading := "NO WINNER"
	if winner == my_seat:
		heading = "YOU WIN"
	elif winner >= 0:
		var winner_name := player_names[winner] if winner < player_names.size() else "AI"
		heading = "%s WINS" % (winner_name if winner_name != "AI" else "P%d" % (winner + 1))
	menu.cursor = 0
	menu.open(heading, "", [["again", "PLAY AGAIN"], ["back", "MENU"]])


func _shape_name(players: int) -> String:
	return SHAPE_NAMES[clampi(players - 2, 0, SHAPE_NAMES.size() - 1)]


## Player counts go 2, 3, ... 7 and then wrap back to 2.
func _wrap_players(count: int) -> int:
	var span := ArenaSimulation.MAX_PLAYERS - ArenaSimulation.MIN_PLAYERS + 1
	return ArenaSimulation.MIN_PLAYERS + posmod(count - ArenaSimulation.MIN_PLAYERS, span)


# --- menu choices -------------------------------------------------------------

func _on_menu_choice(id: String, direction: int) -> void:
	match id:
		"solo":
			Sound.play("confirm")
			show_solo_setup()
		"players":
			Sound.play("nav")
			solo_players = _wrap_players(solo_players + direction)
			show_solo_setup()
		"skill":
			Sound.play("nav")
			solo_skill = posmod(solo_skill + direction, SKILLS.size())
			show_solo_setup()
		"go":
			Sound.play("confirm")
			start_solo_match()
		"online":
			Sound.play("confirm")
			show_online_menu()
		"create":
			Sound.play("confirm")
			_ask_server("create")
		"join":
			Sound.play("confirm")
			show_join_screen()
		"join_code":
			_join_typed_code()
		"size":
			Sound.play("nav")
			Network.set_room_size(_wrap_players(room_size + direction))
		"start":
			Sound.play("confirm")
			Network.start_match()
			menu.status.text = "STARTING..."
		"copy":
			_copy_room_code()
		"leave":
			Sound.play("nav")
			Network.leave_room()
			show_online_menu()
		"resume":
			Sound.play("confirm")
			resume()
		"again":
			Sound.play("confirm")
			_play_again()
		"back":
			Sound.play("nav")
			show_title()


## Esc / controller Start: one step back.
func _go_back() -> void:
	match phase:
		Phase.PLAYING:
			pause()
		Phase.PAUSED:
			resume()
		Phase.SOLO_SETUP, Phase.ONLINE_MENU, Phase.OVER:
			show_title()
		Phase.ONLINE_JOIN:
			show_online_menu()
		Phase.ONLINE_ROOM:
			Network.leave_room()
			show_online_menu()


# --- keyboard and controller --------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		handle_key(event.physical_keycode)
	elif event is InputEventJoypadButton and event.pressed:
		_handle_pad_button(event.button_index)


func handle_key(key: int) -> void:
	if key == KEY_ESCAPE:
		_go_back()
	elif phase == Phase.PLAYING:
		if key in [KEY_SPACE, KEY_W, KEY_UP, KEY_ENTER, KEY_KP_ENTER]:
			swing()
	elif key in [KEY_UP, KEY_W]:
		menu.move_cursor(-1)
	elif key in [KEY_DOWN, KEY_S]:
		menu.move_cursor(1)
	elif key in [KEY_LEFT, KEY_A]:
		_change_value(-1)
	elif key in [KEY_RIGHT, KEY_D]:
		_change_value(1)
	elif key in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]:
		menu.press()


func _handle_pad_button(button: int) -> void:
	if button == JOY_BUTTON_START or button == JOY_BUTTON_BACK:
		_go_back()
	elif phase == Phase.PLAYING:
		if button == JOY_BUTTON_A:
			swing()
	elif button == JOY_BUTTON_DPAD_UP:
		menu.move_cursor(-1)
	elif button == JOY_BUTTON_DPAD_DOWN:
		menu.move_cursor(1)
	elif button == JOY_BUTTON_DPAD_LEFT:
		_change_value(-1)
	elif button == JOY_BUTTON_DPAD_RIGHT:
		_change_value(1)
	elif button == JOY_BUTTON_A:
		menu.press()
	elif button == JOY_BUTTON_B:
		_go_back()


## Left/right on a button that holds a value (players, AI level, room size).
func _change_value(direction: int) -> void:
	if menu.selected() in ["players", "skill", "size"]:
		menu.press(direction)


## Left/right as a number from -1 to 1. Your wall is drawn at the bottom and
## the paddle's position along it grows to the left, so right is negative.
func paddle_input() -> float:
	var axis := 0.0
	if Input.is_physical_key_pressed(KEY_LEFT) or Input.is_physical_key_pressed(KEY_A):
		axis += 1.0
	if Input.is_physical_key_pressed(KEY_RIGHT) or Input.is_physical_key_pressed(KEY_D):
		axis -= 1.0
	for pad in Input.get_connected_joypads():
		var dpad := float(Input.is_joy_button_pressed(pad, JOY_BUTTON_DPAD_LEFT)) - float(Input.is_joy_button_pressed(pad, JOY_BUTTON_DPAD_RIGHT))
		axis += dpad if dpad != 0.0 else -_stick(Input.get_joy_axis(pad, JOY_AXIS_LEFT_X))
	return clampf(axis, -1.0, 1.0)


## Ignores tiny stick drift and makes small pushes a bit gentler.
func _stick(value: float) -> float:
	var amount := absf(value)
	if amount <= STICK_DEADZONE:
		return 0.0
	return signf(value) * pow((amount - STICK_DEADZONE) / (1.0 - STICK_DEADZONE), 1.15)


## Space in the line finale.
func swing() -> void:
	if not sim.is_line() or not sim.is_alive(my_seat):
		return
	court.flash_swing()
	if online:
		Network.send_swing(online_view.swing())
	else:
		sim.press_hit(my_seat)


# --- playing ------------------------------------------------------------------

func start_solo_match() -> void:
	online = false
	my_seat = 0
	var ai_seats := []
	player_names.clear()
	for seat in solo_players:
		ai_seats.append(seat != 0)
		player_names.append("YOU" if seat == 0 else "AI")
	sim = ArenaSimulation.new()
	sim.cpu_skill = SKILLS[solo_skill]
	sim.reset_match(ai_seats)
	_begin_playing()


func _begin_playing() -> void:
	phase = Phase.PLAYING
	court.start_match(sim)
	menu.close()


func _play_again() -> void:
	if online:
		Network.ask_for_rematch()
		menu.status.text = "STARTING A NEW MATCH..."
	else:
		start_solo_match()


func _physics_process(delta: float) -> void:
	if online:
		_online_frame(delta)
	elif phase in [Phase.PLAYING, Phase.PAUSED, Phase.OVER]:
		if phase == Phase.PLAYING:
			_solo_step(delta)
		draw_frame(sim.ball_pos, func(seat: int) -> float: return sim.paddle_pos[seat], delta)


func _solo_step(delta: float) -> void:
	if sim.is_alive(my_seat) and not sim.is_line():
		sim.set_axis(my_seat, paddle_input())
	var order_before := sim.order.duplicate()
	var corners_before := court.corners_on_screen(order_before.size()) if order_before.size() >= 3 else PackedVector2Array()
	sim.tick(delta)
	_react_to(sim.events)
	sim.events.clear()
	if sim.wall_count() != order_before.size():
		court.start_fold(sim, order_before, corners_before)


func draw_frame(ball_position: Vector2, paddle_position: Callable, delta: float) -> void:
	court.draw_match(sim, my_seat, player_names, ball_position, paddle_position, _hint_text(), delta)


## The only in-game instructions.
func _hint_text() -> String:
	if phase != Phase.PLAYING or not sim.is_alive(my_seat):
		return ""
	if sim.is_line():
		return "SPACE WHEN THE BALL IS IN YOUR ZONE"
	if sim.state == ArenaSimulation.STATE_COUNTDOWN and sim.wall_count() == sim.seat_count:
		return "LEFT / RIGHT MOVE YOUR PADDLE"
	return ""


## Sounds and ink splats for things that just happened.
func _react_to(events: Array) -> void:
	var speed := clampf((sim.ball_vel.length() - ArenaSimulation.START_SPEED) / (ArenaSimulation.MAX_SPEED - ArenaSimulation.START_SPEED), 0.0, 1.0)
	for event in events:
		var where := court.to_screen(sim, Vector2(float(event.get("x", 0.0)), float(event.get("y", 0.0))))
		match str(event.get("type", "")):
			"paddle":
				Sound.play("paddle", 0.95 + speed * 0.85)
				InkEffects.paddle_hit(where)
			"wall":
				Sound.play("wall", 0.9 + speed * 0.35)
				InkEffects.wall_hit(where)
			"whiff":
				if int(event.get("seat", -1)) == my_seat:
					Sound.play("nav", 0.7)
			"goal":
				_player_out(where)
			"win":
				show_game_over(int(event.get("seat", -1)))


## Someone missed the ball and is out.
func _player_out(where: Vector2) -> void:
	Sound.play_point()
	InkEffects.point_lost(where)


# --- online lobby -------------------------------------------------------------

func _ask_server(action: String) -> void:
	_waiting_for = action
	menu.status.text = "JOINING ROOM..." if action == "join" else "CREATING ROOM..."
	if Network.state == Network.STATE_DISCONNECTED:
		Network.connect_to_server()
	_send_waiting_request()


func _send_waiting_request() -> void:
	if _waiting_for.is_empty() or Network.state != Network.STATE_CONNECTED:
		return
	var action := _waiting_for
	_waiting_for = ""
	if action == "create":
		Network.create_room(room_size)
	else:
		Network.join_room(_join_code)


func _join_typed_code() -> void:
	var typed := menu.code_box.text.strip_edges().to_upper()
	if typed.length() != 6:
		menu.status.text = "ENTER THE SIX-CHARACTER ROOM CODE"
		return
	Sound.play("confirm")
	_join_code = typed
	menu.code_box.release_focus()
	_ask_server("join")


func _copy_room_code() -> void:
	if phase != Phase.ONLINE_ROOM or Network.room_code.is_empty():
		return
	Sound.play("confirm")
	if OS.has_feature("web"):
		JavaScriptBridge.eval("navigator.clipboard.writeText('%s')" % Network.room_code)
	else:
		DisplayServer.clipboard_set(Network.room_code)
	menu.status.text = "ROOM CODE COPIED"


func _on_connection_changed(state: int, message: String) -> void:
	if not online:
		return
	if state == Network.STATE_DISCONNECTED:
		# Show why, and forget any waiting request so the player can try again.
		_waiting_for = ""
		if phase == Phase.ONLINE_MENU:
			menu.status.text = message
		else:
			show_online_menu(message)
	elif phase in [Phase.ONLINE_MENU, Phase.ONLINE_JOIN]:
		if state == Network.STATE_CONNECTED and not _waiting_for.is_empty():
			_send_waiting_request()
		elif _waiting_for.is_empty() and not message.is_empty():
			menu.status.text = message


func _on_online_error(message: String) -> void:
	if not online:
		return
	_waiting_for = ""
	if phase in [Phase.ONLINE_MENU, Phase.ONLINE_JOIN, Phase.ONLINE_ROOM, Phase.OVER]:
		menu.status.text = message


func _on_room_joined(_code: String, seat: int) -> void:
	my_seat = seat
	room_host = seat
	room_people = []
	for index in room_size:
		room_people.append(index == seat)
	menu.cursor = 0
	show_room()


func _on_lobby_changed(lobby: Dictionary) -> void:
	room_size = int(lobby.get("size", room_size))
	room_people = lobby.get("seats", room_people).duplicate()
	my_seat = int(lobby.get("you", my_seat))
	room_host = int(lobby.get("host", room_host))
	if phase == Phase.ONLINE_ROOM:
		show_room()


func _on_online_match_started() -> void:
	if not online:
		return
	player_names.clear()
	for seat in room_size:
		var person: bool = seat < room_people.size() and room_people[seat]
		player_names.append("YOU" if seat == my_seat else ("P%d" % (seat + 1) if person else "AI"))
	online_view.start(my_seat)
	sim = online_view.sim
	phase = Phase.PLAYING
	menu.close()


# --- online playing -----------------------------------------------------------

func _on_snapshot(data: Dictionary) -> void:
	if not online or not phase in [Phase.PLAYING, Phase.PAUSED, Phase.OVER]:
		return
	var corners_before := court.corners_on_screen(sim.wall_count()) if sim.wall_count() >= 3 else PackedVector2Array()
	var change := online_view.take_snapshot(data)
	if change["first"]:
		court.start_match(sim)
		return
	if sim.wall_count() != change["order_before"].size():
		court.start_fold(sim, change["order_before"], corners_before)
		_player_out(CourtView.CENTER)
	if sim.state == ArenaSimulation.STATE_OVER and phase != Phase.OVER:
		show_game_over(sim.winner)


func _online_frame(delta: float) -> void:
	if not online_view.have_snapshot or not phase in [Phase.PLAYING, Phase.PAUSED, Phase.OVER]:
		return
	online_view.move_my_paddle(paddle_input() if phase == Phase.PLAYING else 0.0, delta)
	online_view.fade_corrections(delta)
	var ball_position := Vector2.ZERO
	if sim.state == ArenaSimulation.STATE_PLAY:
		var ball := online_view.predict_ball(Time.get_ticks_usec() / 1000000.0, delta)
		ball_position = ball["position"]
		_react_to(ball["events"])
	draw_frame(ball_position, online_view.paddle_position, delta)
