extends SceneTree

var first := WebSocketPeer.new()
var second := WebSocketPeer.new()
var elapsed := 0.0
var room_code := ""
var create_sent := false
var join_sent := false
var match_ready := false
var left_serve_sent := false
var point_scored := false
var right_serve_sent := false
var input_timer := 0.0


func _initialize() -> void:
	var url := OS.get_environment("PONG_TEST_SERVER_URL").strip_edges()
	if url.is_empty():
		url = "ws://127.0.0.1:9081"
	if first.connect_to_url(url) != OK or second.connect_to_url(url) != OK:
		quit(1)


func _process(delta: float) -> bool:
	elapsed += delta
	input_timer += delta
	first.poll()
	second.poll()
	if first.get_ready_state() == WebSocketPeer.STATE_OPEN and not create_sent:
		create_sent = true
		first.send_text(JSON.stringify({"type": "create_room"}))
	_read_packets(first, true)
	if not room_code.is_empty() and second.get_ready_state() == WebSocketPeer.STATE_OPEN and not join_sent:
		join_sent = true
		second.send_text(JSON.stringify({"type": "join_room", "code": room_code}))
	_read_packets(second, false)
	if match_ready and not left_serve_sent and input_timer >= 0.08:
		input_timer = 0.0
		second.send_text(JSON.stringify({"type": "input", "axis": 0.0, "target_y": 150.0}))
	if right_serve_sent:
		print("PONG online match lifecycle smoke: passed")
		first.close()
		second.close()
		quit(0)
		return true
	if elapsed > 12.0:
		push_error("Online match did not progress through score and second serve")
		quit(1)
		return true
	return false


func _read_packets(peer: WebSocketPeer, is_first: bool) -> void:
	if peer.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	while peer.get_available_packet_count() > 0:
		var message = JSON.parse_string(peer.get_packet().get_string_from_utf8())
		if not message is Dictionary:
			continue
		match str(message.get("type", "")):
			"room_created":
				room_code = str(message.get("code", ""))
			"opponent_connected":
				match_ready = true
			"snapshot":
				_handle_snapshot(message, is_first)


func _handle_snapshot(snapshot: Dictionary, is_first: bool) -> void:
	var paddles = snapshot.get("paddles", {})
	var scores = snapshot.get("scores", {})
	var ball = snapshot.get("ball", {})
	if not left_serve_sent and is_first and paddles is Dictionary and float(paddles.get("right", 360.0)) <= 170.0:
		left_serve_sent = true
		first.send_text(JSON.stringify({"type": "serve", "aim": 0.0}))
	if scores is Dictionary and int(scores.get("left", 0)) == 1:
		point_scored = true
	if point_scored and not bool(snapshot.get("between_points", true)) and bool(snapshot.get("serving", false)) and not right_serve_sent and not is_first:
		second.send_text(JSON.stringify({"type": "serve", "aim": 0.0}))
	if point_scored and is_first and ball is Dictionary and float(ball.get("vx", 0.0)) < -100.0:
		right_serve_sent = true
