extends Node
## WebSocket client for online polygon rooms: connection, rooms, input,
## swings, heartbeats, round-trip timing and snapshots.

signal connection_changed(state: int, message: String)
signal online_error(message: String)
signal room_joined(code: String, seat: int)
signal lobby_changed(lobby: Dictionary)
signal match_started
signal snapshot_received(snapshot: Dictionary)

const STATE_DISCONNECTED := 0
const STATE_CONNECTING := 1
const STATE_CONNECTED := 2
const STATE_IN_ROOM := 3
const STATE_PLAYING := 4

var state := STATE_DISCONNECTED
var socket: WebSocketPeer
var server_url := ""
var room_code := ""
var seat := -1
var status_message := ""
var _connect_started := 0.0
var _connection_timeout := 20.0
var _last_input_sent := 0.0
var _last_sent_axis := 0.0
var _last_sent_target := -1.0
var _heartbeat_elapsed := 0.0
var _rtt_ping_elapsed := 0.0
var _rtt_sampled := false
var _no_delay_applied := false
## Smoothed round-trip time to the server, used to lead online prediction.
var rtt_seconds := DEFAULT_RTT
const HEARTBEAT_INTERVAL := 10.0
const RTT_PING_INTERVAL := 1.0
const DEFAULT_RTT := 0.12
const MAX_RTT := 1.0
const INPUT_KEEPALIVE := 0.1


func _ready() -> void:
	# Online packets must keep flowing while menus pause the rest of the tree.
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	if socket == null:
		return
	socket.poll()
	var ready := socket.get_ready_state()
	if ready == WebSocketPeer.STATE_OPEN:
		if not _no_delay_applied:
			_no_delay_applied = true
			if not OS.has_feature("web"):
				socket.set_no_delay(true)
		if state == STATE_CONNECTING:
			_heartbeat_elapsed = 0.0
			_rtt_ping_elapsed = RTT_PING_INTERVAL
			_set_state(STATE_CONNECTED, "CONNECTED TO ONLINE SERVER")
		_heartbeat_elapsed += delta
		_rtt_ping_elapsed += delta
		if _rtt_ping_elapsed >= RTT_PING_INTERVAL:
			_rtt_ping_elapsed = 0.0
			_heartbeat_elapsed = 0.0
			_send({"type": "ping", "t": _now()})
		elif _heartbeat_elapsed >= HEARTBEAT_INTERVAL:
			_heartbeat_elapsed = 0.0
			_send({"type": "ping"})
		while socket.get_available_packet_count() > 0:
			_handle_packet(socket.get_packet())
	elif ready == WebSocketPeer.STATE_CLOSED:
		var code := socket.get_close_code()
		_reset_connection("CONNECTION CLOSED (%d)" % code)
	elif state == STATE_CONNECTING and Time.get_ticks_msec() / 1000.0 - _connect_started > _connection_timeout:
		var local_server := server_url.begins_with("ws://127.0.0.1") or server_url.begins_with("ws://localhost")
		if local_server:
			_reset_connection("LOCAL SERVER NOT RUNNING. START server/server_main.tscn")
		else:
			_reset_connection("COULDN'T CONNECT. SERVER MAY BE WAKING UP")


func connect_to_server(url: String = "") -> void:
	if url.is_empty():
		url = Constants.get_online_server_url()
	server_url = url.strip_edges()
	if server_url.is_empty():
		_emit_error("ONLINE SERVER URL IS EMPTY")
		return
	if socket != null:
		disconnect_from_server()
	socket = WebSocketPeer.new()
	_no_delay_applied = false
	var result := socket.connect_to_url(server_url)
	if result != OK:
		_reset_connection("COULDN'T START CONNECTION")
		return
	_connect_started = Time.get_ticks_msec() / 1000.0
	_connection_timeout = 8.0 if server_url.begins_with("ws://127.0.0.1") or server_url.begins_with("ws://localhost") else 45.0
	var wake_message := "START server/server_main.tscn FOR LOCAL PLAY" if _connection_timeout < 10.0 else "FREE SERVER MAY TAKE A MOMENT TO WAKE UP"
	_set_state(STATE_CONNECTING, "CONNECTING TO ONLINE SERVER...\n" + wake_message)


func disconnect_from_server() -> void:
	if socket != null:
		socket.close()
	_reset_connection("DISCONNECTED")


func create_room(size: int) -> void:
	if state != STATE_CONNECTED or not room_code.is_empty():
		_emit_error("FINISH THE CURRENT ONLINE ACTION FIRST")
		return
	if _send({"type": "create_room", "size": size}):
		_set_state(STATE_CONNECTED, "CREATING ROOM...")


func join_room(code: String) -> void:
	if state != STATE_CONNECTED or not room_code.is_empty():
		_emit_error("FINISH THE CURRENT ONLINE ACTION FIRST")
		return
	var normalized := code.strip_edges().to_upper()
	var room_regex := RegEx.new()
	room_regex.compile("^[A-Z0-9]{6}$")
	if normalized.length() != 6 or room_regex.search(normalized) == null:
		_emit_error("ROOM CODE MUST BE SIX CHARACTERS")
		return
	if _send({"type": "join_room", "code": normalized}):
		_set_state(STATE_CONNECTED, "JOINING ROOM %s..." % normalized)


func leave_room() -> void:
	if room_code.is_empty():
		return
	_send({"type": "leave_room"})
	room_code = ""
	seat = -1
	_set_state(STATE_CONNECTED, "LEFT ROOM")


func set_room_size(size: int) -> void:
	_send({"type": "set_size", "size": size})


func request_start() -> void:
	_send({"type": "start"})


func request_rematch() -> void:
	_send({"type": "rematch"})


func send_input(axis: float, target: float = -1.0) -> void:
	if state != STATE_PLAYING:
		return
	var clean_axis := snappedf(clampf(axis, -1.0, 1.0), 0.01)
	var clean_target := snappedf(target, 0.1) if target >= 0.0 else -1.0
	var now := _now()
	var changed := clean_axis != _last_sent_axis or absf(clean_target - _last_sent_target) >= 0.1
	# Unchanged input is only repeated often enough to beat the server timeout.
	if not changed and now - _last_input_sent < INPUT_KEEPALIVE:
		return
	_last_input_sent = now
	_last_sent_axis = clean_axis
	_last_sent_target = clean_target
	_send({"type": "input", "axis": clean_axis, "target_y": clean_target})


## A swing in the line finale, stamped with the server tick the player saw.
func send_hit(at_tick: int) -> void:
	if state == STATE_PLAYING:
		_send({"type": "hit", "tick": at_tick})


func connection_is_open() -> bool:
	return socket != null and socket.get_ready_state() == WebSocketPeer.STATE_OPEN


func _now() -> float:
	return Time.get_ticks_usec() / 1000000.0


func _send(message: Dictionary) -> bool:
	if not connection_is_open():
		_emit_error("NOT CONNECTED TO ONLINE SERVER")
		return false
	var result := socket.send_text(JSON.stringify(message))
	if result != OK:
		_emit_error("COULDN'T SEND DATA TO ONLINE SERVER")
		return false
	return true


func _handle_packet(packet: PackedByteArray) -> void:
	var text := packet.get_string_from_utf8().strip_edges()
	if text.is_empty():
		return
	var parsed = JSON.parse_string(text)
	if not parsed is Dictionary:
		_emit_error("SERVER SENT INVALID DATA")
		return
	var message: Dictionary = parsed
	_heartbeat_elapsed = 0.0
	match str(message.get("type", "")):
		"arena_room":
			room_code = str(message.get("code", ""))
			seat = int(message.get("seat", -1))
			_set_state(STATE_IN_ROOM, "ROOM READY")
			room_joined.emit(room_code, seat)
		"arena_lobby":
			seat = int(message.get("you", seat))
			lobby_changed.emit(message)
		"arena_started":
			_set_state(STATE_PLAYING, "MATCH STARTED")
			match_started.emit()
		"arena_snapshot":
			snapshot_received.emit(message)
		"error":
			var server_message := str(message.get("message", "ONLINE ERROR"))
			if server_message != "UNKNOWN MESSAGE TYPE":
				_emit_error(server_message)
		"left_room":
			room_code = ""
			seat = -1
			_set_state(STATE_CONNECTED, "LEFT ROOM")
		"pong":
			_record_rtt(message.get("t"))


func _record_rtt(sent_at) -> void:
	if not (sent_at is float or sent_at is int):
		return
	var sample := _now() - float(sent_at)
	if sample < 0.0 or sample > MAX_RTT * 3.0:
		return
	sample = minf(sample, MAX_RTT)
	if not _rtt_sampled:
		rtt_seconds = sample
		_rtt_sampled = true
		return
	# Rise quickly to protect against misses, fall slowly to ignore one-off fast replies.
	var weight := 0.35 if sample > rtt_seconds else 0.12
	rtt_seconds = lerpf(rtt_seconds, sample, weight)


func _set_state(next_state: int, message: String) -> void:
	state = next_state
	status_message = message
	connection_changed.emit(state, message)


func _emit_error(message: String) -> void:
	status_message = message
	online_error.emit(message)
	connection_changed.emit(state, message)


func _reset_connection(message: String) -> void:
	socket = null
	_heartbeat_elapsed = 0.0
	_rtt_ping_elapsed = 0.0
	_rtt_sampled = false
	rtt_seconds = DEFAULT_RTT
	_last_sent_axis = 0.0
	_last_sent_target = -1.0
	room_code = ""
	seat = -1
	_set_state(STATE_DISCONNECTED, message)
