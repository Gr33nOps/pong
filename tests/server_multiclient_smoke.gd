extends SceneTree

var first := WebSocketPeer.new()
var second := WebSocketPeer.new()
var elapsed := 0.0
var first_requested := false
var second_requested := false
var room_code := ""
var first_opponent := false
var second_opponent := false
var first_snapshot := false
var second_snapshot := false


func _initialize() -> void:
	var first_result := first.connect_to_url("ws://127.0.0.1:9081")
	var second_result := second.connect_to_url("ws://127.0.0.1:9081")
	if first_result != OK or second_result != OK:
		print("PONG multiclient server smoke: connection start failed")
		quit(1)


func _process(delta: float) -> bool:
	elapsed += delta
	first.poll()
	second.poll()
	if first.get_ready_state() == WebSocketPeer.STATE_OPEN and not first_requested:
		first_requested = true
		first.send_text(JSON.stringify({"type": "create_room"}))
	_read_first_packets()
	if not room_code.is_empty() and second.get_ready_state() == WebSocketPeer.STATE_OPEN and not second_requested:
		second_requested = true
		second.send_text(JSON.stringify({"type": "join_room", "code": room_code}))
	_read_second_packets()
	if first_opponent and second_opponent and first_snapshot and second_snapshot:
		print("PONG multiclient server smoke: passed")
		first.close()
		second.close()
		quit(0)
		return false
	if elapsed > 8.0:
		print("PONG multiclient server smoke: timed out")
		quit(1)
		return false
	return true


func _read_first_packets() -> void:
	if first.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	while first.get_available_packet_count() > 0:
		var parsed = JSON.parse_string(first.get_packet().get_string_from_utf8())
		if not parsed is Dictionary:
			continue
		var message_type := str(parsed.get("type", ""))
		if message_type == "room_created":
			room_code = str(parsed.get("code", ""))
		elif message_type == "opponent_connected":
			first_opponent = true
		elif message_type == "snapshot":
			first_snapshot = true


func _read_second_packets() -> void:
	if second.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	while second.get_available_packet_count() > 0:
		var parsed = JSON.parse_string(second.get_packet().get_string_from_utf8())
		if not parsed is Dictionary:
			continue
		var message_type := str(parsed.get("type", ""))
		if message_type == "opponent_connected":
			second_opponent = true
		elif message_type == "snapshot":
			second_snapshot = true
