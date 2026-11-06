extends Node2D
## Paddle Polygon: online Pong for 2 to 10 friends.
##
## This script runs the game flow: which screen is showing, what your keys
## do, and the room you're in. The other scripts do the actual work:
##   arena_simulation.gd - the rules (the server runs the real match)
##   court_view.gd       - drawing the court
##   menu_overlay.gd     - the menus
##   online_view.gd      - hiding network delay
##
## Screens: TITLE -> PLAY (your name, create or join) -> LOADING (waiting for
## the server) -> ROOM (code, invite link, who's in) -> the match -> OVER (who
## won) -> back to the ROOM.

const ArenaSimulation = preload("res://scripts/arena_simulation.gd")
const CourtView = preload("res://scripts/court_view.gd")
const MenuOverlay = preload("res://scripts/menu_overlay.gd")
const OnlineView = preload("res://scripts/online_view.gd")

enum Phase { TITLE, PLAY, JOIN, LOADING, ROOM, PLAYING, PAUSED, OVER }

const SHAPE_NAMES := ["1D LINE", "TRIANGLE", "SQUARE", "PENTAGON", "HEXAGON", "HEPTAGON", "OCTAGON", "NONAGON", "DECAGON"]
const STICK_DEADZONE := 0.18
## After this long still connecting, the loading screen explains why.
const SLOW_CONNECT_SECONDS := 4.0

var phase := Phase.TITLE
## A copy of the server's match, kept up to date by the online view.
var sim := ArenaSimulation.new()
var my_seat := 0
var player_names: Array[String] = []

# The room you're in.
var room_names: Array = []
var room_host := -1
## A room code from an invite link, joined as soon as you have a name.
var invite_code := ""
var _waiting_for := ""
var _join_code := ""
## The screen to go back to if loading is cancelled or fails.
var _loading_from := Phase.PLAY
var _loading_time := 0.0

var court: CourtView
var menu: MenuOverlay
var online_view := OnlineView.new()


func _ready() -> void:
	court = CourtView.new()
	add_child(court)
	menu = MenuOverlay.new()
	add_child(menu)
	menu.chosen.connect(_on_menu_choice)
	menu.text_entered.connect(menu.press)
	Network.connection_changed.connect(_on_connection_changed)
	Network.online_error.connect(_on_online_error)
	Network.room_joined.connect(_on_room_joined)
	Network.lobby_changed.connect(_on_lobby_changed)
	Network.match_started.connect(_on_match_started)
	Network.snapshot_received.connect(_on_snapshot)
	invite_code = Settings.invite_code_from_page()
	if invite_code.is_empty():
		show_title()
	else:
		show_play_menu()
		if not Settings.player_name().is_empty():
			_join_room(invite_code)


# --- screens ------------------------------------------------------------------

func show_title() -> void:
	phase = Phase.TITLE
	menu.cursor = 0
	if Network.state != Network.STATE_DISCONNECTED:
		Network.disconnect_from_server()
	menu.open("", "", [["play", "PLAY"]], "SPACE SELECT   M MUTE")
	menu.show_big_title("PADDLE POLYGON", "ONLINE PONG FOR 2 TO 10 FRIENDS")
	court.show_preview(5)


## Type your name, then create a room or join one.
func show_play_menu(message: String = "") -> void:
	phase = Phase.PLAY
	_waiting_for = ""
	online_view.have_snapshot = false
	menu.cursor = 0
	if Network.state == Network.STATE_DISCONNECTED:
		Network.connect_to_server()
	var status := message
	if status.is_empty() and Network.state != Network.STATE_CONNECTED:
		status = Network.status_message
	var buttons := [["create", "CREATE ROOM"], ["join", "JOIN ROOM"], ["back", "BACK"]]
	if not invite_code.is_empty():
		buttons = [["join_invite", "JOIN ROOM %s" % invite_code], ["back", "BACK"]]
	menu.open("PLAY", status, buttons, "TYPE YOUR NAME   UP/DOWN MOVE   ENTER SELECT")
	menu.show_text_box("YOUR NAME", Settings.MAX_NAME_LENGTH, Settings.player_name())
	court.show_preview(4)


func show_join_screen(message: String = "", code: String = "") -> void:
	phase = Phase.JOIN
	menu.cursor = 0
	var status := message if not message.is_empty() else "TYPE THE ROOM CODE YOUR FRIEND SENT YOU"
	menu.open("JOIN ROOM", status, [["join_code", "JOIN"], ["back", "BACK"]])
	menu.show_text_box("ROOM CODE", 6, code)


## Waiting for the server to make or find the room.
func show_loading(heading: String) -> void:
	_loading_from = phase if phase == Phase.JOIN else Phase.PLAY
	_loading_time = 0.0
	phase = Phase.LOADING
	menu.show_loading(heading, _loading_detail())


func show_room() -> void:
	phase = Phase.ROOM
	var i_am_host := Network.seat == room_host
	var count := room_names.size()
	var buttons := []
	if i_am_host:
		buttons.append(["start", "START MATCH"])
	buttons.append(["link", "COPY INVITE LINK"])
	buttons.append(["leave", "LEAVE ROOM"])
	var status := "1 PLAYER" if count == 1 else "%d PLAYERS   %s" % [count, _shape_name(count)]
	if i_am_host:
		status += "   START WHEN EVERYONE IS IN" if count >= 2 else "   INVITE AT LEAST ONE FRIEND"
	else:
		status += "   WAITING FOR %s TO START" % _room_name(room_host)
	menu.open("ROOM  %s" % Network.room_code, status, buttons, "COPY THE LINK AND SEND IT TO YOUR FRIENDS", 300.0)
	menu.show_players(_players_text())
	court.show_preview(clampi(count, ArenaSimulation.MIN_PLAYERS, ArenaSimulation.MAX_PLAYERS))


func pause() -> void:
	phase = Phase.PAUSED
	menu.cursor = 0
	menu.open("MENU", "THE MATCH KEEPS RUNNING", [["resume", "RESUME"], ["leave", "LEAVE ROOM"]])


func resume() -> void:
	phase = Phase.PLAYING
	menu.close()


func show_game_over(winner: int) -> void:
	phase = Phase.OVER
	Sound.play_win()
	var heading := "NO WINNER"
	if winner == my_seat:
		heading = "YOU WIN"
	elif winner >= 0 and winner < player_names.size():
		heading = "%s WINS" % player_names[winner]
	menu.cursor = 0
	menu.open(heading, "", [["room", "BACK TO ROOM"], ["leave", "LEAVE ROOM"]])


func _loading_detail() -> String:
	if Network.state != Network.STATE_CONNECTING:
		return ""
	if _loading_time < SLOW_CONNECT_SECONDS:
		return "CONNECTING TO THE SERVER"
	return "WAKING UP THE SERVER\nTHIS CAN TAKE UP TO A MINUTE"


func _shape_name(players: int) -> String:
	return SHAPE_NAMES[clampi(players - 2, 0, SHAPE_NAMES.size() - 1)]


func _room_name(seat: int) -> String:
	return str(room_names[seat]) if seat >= 0 and seat < room_names.size() else "THE HOST"


## "ALI (HOST)   SARA   ZAIN (YOU)"
func _players_text() -> String:
	var parts: Array[String] = []
	for seat in room_names.size():
		var text := str(room_names[seat])
		if seat == room_host:
			text += " (HOST)"
		elif seat == Network.seat:
			text += " (YOU)"
		parts.append(text)
	return "   ".join(parts)


# --- menu choices -------------------------------------------------------------

func _on_menu_choice(id: String) -> void:
	match id:
		"play":
			Sound.play("confirm")
			show_play_menu()
		"create":
			if _take_name():
				_ask_server("create")
		"join":
			if _take_name():
				Sound.play("confirm")
				show_join_screen()
		"join_invite":
			if _take_name():
				_join_room(invite_code)
		"join_code":
			_join_typed_code()
		"start":
			Sound.play("confirm")
			Network.start_match()
			menu.status.text = "STARTING..."
		"link":
			_copy_invite_link()
		"leave":
			Sound.play("nav")
			Network.leave_room()
			show_play_menu()
		"resume":
			Sound.play("confirm")
			resume()
		"room":
			Sound.play("confirm")
			show_room()
		"back", "cancel":
			Sound.play("nav")
			_go_back()


## Esc / controller Start: one step back.
func _go_back() -> void:
	match phase:
		Phase.LOADING:
			_waiting_for = ""
			_leave_loading("")
		Phase.PLAYING:
			pause()
		Phase.PAUSED:
			resume()
		Phase.PLAY:
			invite_code = ""
			show_title()
		Phase.JOIN:
			show_play_menu()
		Phase.ROOM, Phase.OVER:
			Network.leave_room()
			show_play_menu()


## Saves the name typed in the box. Returns false (and asks for one) if empty.
func _take_name() -> bool:
	var player_name := Settings.clean_name(menu.text_box.text)
	if player_name.is_empty():
		menu.status.text = "TYPE YOUR NAME FIRST"
		menu.text_box.grab_focus()
		return false
	Settings.save_player_name(player_name)
	return true


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
	elif key in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]:
		menu.press()


func _handle_pad_button(button: int) -> void:
	if button == JOY_BUTTON_START or button == JOY_BUTTON_BACK or button == JOY_BUTTON_B:
		_go_back()
	elif phase == Phase.PLAYING:
		if button == JOY_BUTTON_A:
			swing()
	elif button == JOY_BUTTON_DPAD_UP:
		menu.move_cursor(-1)
	elif button == JOY_BUTTON_DPAD_DOWN:
		menu.move_cursor(1)
	elif button == JOY_BUTTON_A:
		menu.press()


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
	Network.send_swing(online_view.swing())


# --- rooms --------------------------------------------------------------------

func _ask_server(action: String) -> void:
	Sound.play("confirm")
	_waiting_for = action
	if Network.state == Network.STATE_DISCONNECTED:
		Network.connect_to_server()
	show_loading("JOINING ROOM %s" % _join_code if action == "join" else "CREATING ROOM")
	_send_waiting_request()


## Back to the screen the loading started from, with a message if it failed.
func _leave_loading(message: String) -> void:
	if _loading_from == Phase.JOIN:
		show_join_screen(message, _join_code)
	else:
		show_play_menu(message)


func _send_waiting_request() -> void:
	if _waiting_for.is_empty() or Network.state != Network.STATE_CONNECTED:
		return
	var action := _waiting_for
	_waiting_for = ""
	if action == "create":
		Network.create_room(Settings.player_name())
	else:
		Network.join_room(_join_code, Settings.player_name())


func _join_room(code: String) -> void:
	_join_code = code
	_ask_server("join")


func _join_typed_code() -> void:
	var typed := menu.text_box.text.strip_edges().to_upper()
	if typed.length() != 6:
		menu.status.text = "ENTER THE SIX-CHARACTER ROOM CODE"
		return
	menu.text_box.release_focus()
	_join_room(typed)


func _copy_invite_link() -> void:
	if Network.room_code.is_empty():
		return
	Sound.play("confirm")
	var link := Settings.invite_link(Network.room_code)
	if OS.has_feature("web"):
		JavaScriptBridge.eval("navigator.clipboard.writeText(%s)" % JSON.stringify(link))
	else:
		DisplayServer.clipboard_set(link)
	menu.status.text = "LINK COPIED. SEND IT TO YOUR FRIENDS"


func _process(delta: float) -> void:
	if phase == Phase.LOADING:
		_loading_time += delta
		menu.status.text = _loading_detail()


func _on_connection_changed(state: int, message: String) -> void:
	if phase == Phase.TITLE:
		return
	if state == Network.STATE_DISCONNECTED:
		# Show why, and forget any waiting request so the player can try again.
		_waiting_for = ""
		if phase == Phase.PLAY:
			menu.status.text = message
		else:
			show_play_menu(message)
	elif phase == Phase.LOADING:
		if state == Network.STATE_CONNECTED:
			_send_waiting_request()
	elif phase == Phase.PLAY and not message.is_empty():
		menu.status.text = message


func _on_online_error(message: String) -> void:
	_waiting_for = ""
	if phase == Phase.LOADING:
		_leave_loading(message)
	elif phase in [Phase.PLAY, Phase.JOIN, Phase.ROOM, Phase.OVER]:
		menu.status.text = message


## The server put us in a room; the full list of names follows right after.
func _on_room_joined() -> void:
	if phase != Phase.LOADING:
		# The player cancelled while the server was making the room.
		Network.leave_room()
		return
	invite_code = ""
	room_host = Network.seat
	room_names = [Settings.player_name()]
	menu.cursor = 0
	show_room()


func _on_lobby_changed(lobby: Dictionary) -> void:
	var names = lobby.get("names", room_names)
	room_names = names.duplicate() if names is Array else room_names
	room_host = int(lobby.get("host", room_host))
	if phase == Phase.ROOM:
		show_room()


func _on_match_started(names: Array) -> void:
	my_seat = Network.seat
	player_names.clear()
	for seat_name in names:
		player_names.append(str(seat_name))
	online_view.start(my_seat)
	sim = online_view.sim
	phase = Phase.PLAYING
	menu.close()


# --- playing ------------------------------------------------------------------

func _physics_process(delta: float) -> void:
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


func draw_frame(ball_position: Vector2, paddle_position: Callable, delta: float) -> void:
	court.draw_match(sim, my_seat, player_names, ball_position, paddle_position, _hint_text(), delta)


## The only in-game instructions.
func _hint_text() -> String:
	if phase != Phase.PLAYING:
		return ""
	if not sim.is_alive(my_seat):
		return "YOU'RE OUT   WATCHING UNTIL THE END   ESC MENU"
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


func _on_snapshot(data: Dictionary) -> void:
	if not phase in [Phase.PLAYING, Phase.PAUSED, Phase.OVER]:
		return
	var corners_before := court.corners_on_screen(sim.wall_count()) if sim.wall_count() >= 3 else PackedVector2Array()
	var change := online_view.take_snapshot(data)
	if change["first"]:
		court.start_match(sim)
		return
	if sim.wall_count() != change["order_before"].size():
		court.start_fold(sim, change["order_before"], corners_before)
		Sound.play("point")
		InkEffects.point_lost(CourtView.CENTER)
	if sim.state == ArenaSimulation.STATE_OVER and phase != Phase.OVER:
		show_game_over(sim.winner)
