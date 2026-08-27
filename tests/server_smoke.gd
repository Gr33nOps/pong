extends SceneTree

var socket := WebSocketPeer.new()
var elapsed := 0.0
var requested := false


func _initialize() -> void:
	var url := OS.get_environment("PONG_TEST_SERVER_URL").strip_edges()
	if url.is_empty():
		url = "ws://127.0.0.1:9081"
	var result := socket.connect_to_url(url)
	if result != OK:
		print("PONG server smoke: connection start failed")
		quit(1)


func _process(delta: float) -> bool:
	elapsed += delta
	socket.poll()
	if socket.get_ready_state() == WebSocketPeer.STATE_OPEN and not requested:
		requested = true
		socket.send_text(JSON.stringify({"type": "create_room"}))
	if socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		while socket.get_available_packet_count() > 0:
			var parsed = JSON.parse_string(socket.get_packet().get_string_from_utf8())
			if parsed is Dictionary and str(parsed.get("type", "")) == "room_created":
				var valid: bool = str(parsed.get("code", "")).length() == 6 and str(parsed.get("side", "")) == "left"
				print("PONG server smoke: %s" % ("passed" if valid else "failed"))
				socket.close()
				quit(0 if valid else 1)
				return true
	if elapsed > 8.0:
		print("PONG server smoke: timed out")
		quit(1)
		return true
	return false
