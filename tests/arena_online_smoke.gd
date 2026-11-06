extends SceneTree
## Drives the real game scene against a local server. Raw sockets play the
## friends: one creates each room, the scene types a name and joins with the
## code. Round one is a triangle with a third friend (paddle input must reach
## the server, the ball must draw smoothly); round two is the line finale (a
## well-timed swing must return the ball on the server).

const ArenaSimulation = preload("res://scripts/arena_simulation.gd")

var host := WebSocketPeer.new()
var friend := WebSocketPeer.new()
var scene: Node
var url := ""
var round_size := 3
var elapsed := 0.0
var round_started_at := 0.0
var host_requested := false
var friend_requested := false
var room_code := ""
var join_sent := false
var start_sent := false
var key_down_at := -1.0
var people_in_room := 0
var latest_snapshot: Dictionary = {}
var ball_seen := false
var last_ball := Vector2.INF
var worst_jump := 0.0
var swing_tick := -1
var swung := false
var paddle_moved := false
var last_paddles: Variant = []
var saved_name := ""


func _initialize() -> void:
	url = OS.get_environment("PONG_TEST_SERVER_URL").strip_edges()
	if url.is_empty():
		url = "ws://127.0.0.1:9081"
	OS.set_environment("PONG_SERVER_URL", url)
	get_root().get_node("Sound").muted = true
	saved_name = get_root().get_node("Settings").player_name()
	scene = load("res://scenes/arena.tscn").instantiate()
	get_root().add_child(scene)
	await process_frame
	_begin_round(3)


func _begin_round(size: int) -> void:
	round_size = size
	round_started_at = elapsed
	host = WebSocketPeer.new()
	friend = WebSocketPeer.new()
	host_requested = false
	friend_requested = false
	room_code = ""
	join_sent = false
	start_sent = false
	people_in_room = 0
	latest_snapshot = {}
	if host.connect_to_url(url) != OK:
		_finish(false, "host connection start failed")
		return
	if size == 3 and friend.connect_to_url(url) != OK:
		_finish(false, "friend connection start failed")
		return
	scene.show_play_menu()
	scene.menu.text_box.text = "tester"


func _process(delta: float) -> bool:
	elapsed += delta
	host.poll()
	friend.poll()
	if host.get_ready_state() == WebSocketPeer.STATE_OPEN and not host_requested:
		host_requested = true
		host.send_text(JSON.stringify({"type": "create_room", "name": "host"}))
	_read_host_packets()
	_read_friend_packets()
	if not room_code.is_empty() and round_size == 3 and not friend_requested and friend.get_ready_state() == WebSocketPeer.STATE_OPEN:
		friend_requested = true
		friend.send_text(JSON.stringify({"type": "join_room", "code": room_code, "name": "friend"}))
	if not room_code.is_empty() and not join_sent and (round_size == 2 or people_in_room >= 2):
		join_sent = true
		scene._on_menu_choice("join")
		scene.menu.text_box.text = room_code.to_lower()
		scene._join_typed_code()
	if people_in_room >= round_size and scene.phase == scene.Phase.ROOM and not start_sent:
		start_sent = true
		host.send_text(JSON.stringify({"type": "start"}))
	if round_size == 3:
		return _triangle_round()
	return _line_round()


func _triangle_round() -> bool:
	if scene.phase == scene.Phase.PLAYING and scene.online_view.have_snapshot and key_down_at < 0.0:
		key_down_at = elapsed
		_press_key(KEY_LEFT, true)
	# Noted as soon as the server shows it: a knockout re-centres every paddle.
	var paddles = latest_snapshot.get("paddles", [])
	var mine: int = scene.my_seat
	if key_down_at > 0.0 and paddles is Array and paddles.size() == 3:
		last_paddles = paddles
		paddle_moved = paddle_moved or float(paddles[mine]) > ArenaSimulation.side_length(3) * 0.5 + 40.0
	if key_down_at > 0.0 and elapsed - key_down_at > 2.5:
		_press_key(KEY_LEFT, false)
		if not paddle_moved:
			return _finish(false, "the joined player's paddle input did not reach the server (%s)" % [last_paddles])
		if not ball_seen:
			return _finish(false, "the served ball was never drawn")
		if worst_jump > 6.0:
			return _finish(false, "the ball jumped %.1f px beyond its speed in one frame" % worst_jump)
		if scene.player_names != ["HOST", "FRIEND", "TESTER"]:
			return _finish(false, "the match didn't get everyone's names (%s)" % [scene.player_names])
		host.close()
		friend.close()
		get_root().get_node("Network").leave_room()
		_begin_round(2)
		return false
	if elapsed - round_started_at > 20.0:
		return _finish(false, "triangle round timed out in phase %d" % scene.phase)
	return false


func _line_round() -> bool:
	if scene.phase == scene.Phase.PLAYING and scene.online_view.have_snapshot and scene.sim.is_line() and scene.sim.state == "play" and not swung:
		var predicted: Vector2 = scene.online_view.predict_ball(Time.get_ticks_usec() / 1000000.0, 0.0)["position"]
		var sim = scene.sim
		var end: float = sim.line_end(scene.my_seat)
		var toward: bool = sim.ball_vel.x < 0.0 if end < 0.0 else sim.ball_vel.x > 0.0
		var depth := absf(end - predicted.x)
		if toward and depth < ArenaSimulation.ZONE_LENGTH * 0.6:
			swung = true
			swing_tick = sim.tick_number
			scene.swing()
	if swung and not latest_snapshot.is_empty() and int(latest_snapshot.get("tick", 0)) > swing_tick + 20:
		var ball = latest_snapshot.get("ball", [])
		var order = latest_snapshot.get("order", [])
		var my_end: float = scene.sim.line_end(scene.my_seat)
		var away: bool = float(ball[2]) > 0.0 if my_end < 0.0 else float(ball[2]) < 0.0
		var returned: bool = away or int(latest_snapshot.get("hits", 0)) > 0
		# JSON numbers arrive as decimals (1.0), so compare them as whole numbers.
		var still_in := false
		for seat in order:
			still_in = still_in or int(seat) == scene.my_seat
		if not still_in:
			return _finish(false, "the timed swing missed: the player was knocked out")
		if not returned:
			return _finish(false, "the timed swing did not return the ball")
		return _finish(true, "")
	if elapsed - round_started_at > 20.0:
		return _finish(false, "line round timed out in phase %d" % scene.phase)
	return false


func _physics_process(delta: float) -> bool:
	if scene == null or not is_instance_valid(scene) or scene.phase != scene.Phase.PLAYING or round_size != 3:
		return false
	var ball_position: Vector2 = scene.court.ball.position
	if scene.sim.state == "play" and scene.court.ball.visible:
		ball_seen = true
		if last_ball != Vector2.INF:
			worst_jump = maxf(worst_jump, ball_position.distance_to(last_ball) - ArenaSimulation.MAX_SPEED * delta)
		last_ball = ball_position
	else:
		last_ball = Vector2.INF
	return false


func _press_key(keycode: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	event.pressed = pressed
	Input.parse_input_event(event)


func _read_host_packets() -> void:
	if host.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	while host.get_available_packet_count() > 0:
		var parsed = JSON.parse_string(host.get_packet().get_string_from_utf8())
		if not parsed is Dictionary:
			continue
		match str(parsed.get("type", "")):
			"arena_room":
				room_code = str(parsed.get("code", ""))
			"arena_lobby":
				people_in_room = parsed.get("names", []).size()
			"arena_snapshot":
				latest_snapshot = parsed
				_host_swings_back(parsed)


func _read_friend_packets() -> void:
	if friend.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	while friend.get_available_packet_count() > 0:
		friend.get_packet()


## In the line round the host (seat 0, left end) returns balls that reach its
## zone, so serves don't all go to an idle host who loses at once.
func _host_swings_back(snapshot: Dictionary) -> void:
	if round_size != 2 or str(snapshot.get("state", "")) != "play":
		return
	var ball = snapshot.get("ball", [])
	if not (ball is Array and ball.size() == 4):
		return
	var end: float = -ArenaSimulation.LINE_LENGTH * 0.5
	if float(ball[2]) < 0.0 and float(ball[0]) - end < ArenaSimulation.ZONE_LENGTH * 0.5:
		host.send_text(JSON.stringify({"type": "hit", "tick": -1}))


func _finish(passed: bool, reason: String) -> bool:
	if passed:
		print("PONG arena online smoke: passed")
	else:
		print("PONG arena online smoke: FAILED - " + reason)
	host.close()
	friend.close()
	get_root().get_node("Settings").save_player_name(saved_name)
	if is_instance_valid(scene):
		scene.free()
	quit(0 if passed else 1)
	return true
