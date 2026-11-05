extends SceneTree
## A raw socket hosts a four-player room; the real quad scene joins it, the
## host starts, and the scene's paddle input must reach the server.

var host := WebSocketPeer.new()
var scene: Node
var elapsed := 0.0
var host_requested := false
var room_code := ""
var join_sent := false
var start_sent := false
var key_pressed_at := -1.0
var host_lobby_players := 0
var latest_snapshot: Dictionary = {}
var ball_seen := false
var last_ball := Vector2.INF
var last_ball_state := ""
var worst_jump := 0.0


func _initialize() -> void:
	var url := OS.get_environment("PONG_TEST_SERVER_URL").strip_edges()
	if url.is_empty():
		url = "ws://127.0.0.1:9081"
	OS.set_environment("PONG_SERVER_URL", url)
	get_root().get_node("SFX").muted = true
	get_root().get_node("GameState").quad_mode = "online"
	scene = load("res://quad.tscn").instantiate()
	get_root().add_child(scene)
	if host.connect_to_url(url) != OK:
		_finish(false, "host connection start failed")


func _process(delta: float) -> bool:
	elapsed += delta
	host.poll()
	if host.get_ready_state() == WebSocketPeer.STATE_OPEN and not host_requested:
		host_requested = true
		host.send_text(JSON.stringify({"type": "create_room", "mode": "quad"}))
	_read_host_packets()
	var network_manager = get_root().get_node("NetworkManager")
	if not room_code.is_empty() and not join_sent and network_manager.state == network_manager.STATE_CONNECTED:
		join_sent = true
		scene._code_input.text = room_code.to_lower()
		scene._submit_join()
	if host_lobby_players >= 2 and scene.phase == scene.Phase.ONLINE_ROOM and not start_sent:
		start_sent = true
		host.send_text(JSON.stringify({"type": "start"}))
	if scene.phase == scene.Phase.PLAYING and scene._have_snapshot and key_pressed_at < 0.0:
		key_pressed_at = elapsed
		var press := InputEventKey.new()
		press.physical_keycode = KEY_S
		press.pressed = true
		Input.parse_input_event(press)
	if scene._ball.visible and scene.sim.state == "play":
		ball_seen = true
	if key_pressed_at > 0.0 and elapsed - key_pressed_at > 2.2:
		var paddles = latest_snapshot.get("paddles", [])
		var moved: bool = paddles is Array and paddles.size() == 4 and float(paddles[1]) > 330.0
		var release := InputEventKey.new()
		release.physical_keycode = KEY_S
		release.pressed = false
		Input.parse_input_event(release)
		if not moved:
			return _finish(false, "the joined player's paddle input did not reach the server (%s)" % [paddles])
		if not ball_seen:
			return _finish(false, "the served ball was never drawn")
		if worst_jump > 6.0:
			return _finish(false, "the ball jumped %.1f px beyond its speed in one frame" % worst_jump)
		if scene._seat_small[1].text != "YOU" or scene._seat_small[0].text != "P1" or scene._seat_small[2].text != "CPU":
			return _finish(false, "seat names are wrong: %s %s %s" % [scene._seat_small[0].text, scene._seat_small[1].text, scene._seat_small[2].text])
		return _finish(true, "")
	if elapsed > 20.0:
		return _finish(false, "timed out in phase %d" % scene.phase)
	return false


func _physics_process(delta: float) -> bool:
	if scene == null or not is_instance_valid(scene) or scene.phase != scene.Phase.PLAYING:
		return false
	var state: String = scene.sim.state
	var ball_position: Vector2 = scene._ball.position
	if state == "play" and last_ball_state == "play" and last_ball != Vector2.INF:
		var allowed: float = scene.sim.MAX_SPEED * delta
		worst_jump = maxf(worst_jump, ball_position.distance_to(last_ball) - allowed)
	last_ball = ball_position
	last_ball_state = state
	return false


func _read_host_packets() -> void:
	if host.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	while host.get_available_packet_count() > 0:
		var parsed = JSON.parse_string(host.get_packet().get_string_from_utf8())
		if not parsed is Dictionary:
			continue
		match str(parsed.get("type", "")):
			"quad_room":
				room_code = str(parsed.get("code", ""))
			"quad_lobby":
				host_lobby_players = 0
				for human in parsed.get("seats", []):
					host_lobby_players += 1 if human else 0
			"quad_snapshot":
				latest_snapshot = parsed
		# Keep the host's own seat alive so the server doesn't time it out.
	if start_sent:
		host.send_text(JSON.stringify({"type": "input", "axis": 0.0, "target_y": 270.0}))


func _finish(passed: bool, reason: String) -> bool:
	if passed:
		print("PONG four-player online smoke: passed")
	else:
		print("PONG four-player online smoke: FAILED - " + reason)
	host.close()
	if is_instance_valid(scene):
		scene.free()
	quit(0 if passed else 1)
	return true
