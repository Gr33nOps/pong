extends Node
## Talks to the online server over a WebSocket: connecting, rooms, paddle
## input, swings, and the snapshots the server sends back. It also measures
## the round-trip time, which the game uses to hide network delay.

signal connection_changed(state: int, message: String)
signal online_error(message: String)
signal room_joined
signal lobby_changed(lobby: Dictionary)
signal match_started(names: Array)
signal snapshot_received(snapshot: Dictionary)

const STATE_DISCONNECTED := 0
const STATE_CONNECTING := 1
const STATE_CONNECTED := 2
const STATE_IN_ROOM := 3
const STATE_PLAYING := 4

const PING_INTERVAL := 1.0
const DEFAULT_RTT := 0.12
const MAX_RTT := 1.0
## Unchanged input is re-sent this often so the server knows we're still here.
const INPUT_KEEPALIVE := 0.1

var state := STATE_DISCONNECTED
var status_message := ""
var room_code := ""
var seat := -1
## Smoothed round-trip time to the server, in seconds.
var rtt_seconds := DEFAULT_RTT

var _socket: WebSocketPeer
var _server_url := ""
var _connect_started := 0.0
var _connect_timeout := 45.0
var _ping_elapsed := 0.0
var _rtt_measured := false
var _last_input_time := 0.0
var _last_target := -1.0


func _ready() -> void:
	# Keep talking to the server while menus are open.
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	if _socket == null:
		return
	_socket.poll()
	match _socket.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			if state == STATE_CONNECTING:
				_on_connected()
			_ping_elapsed += delta
			if _ping_elapsed >= PING_INTERVAL:
				_ping_elapsed = 0.0
				_send({"type": "ping", "t": _now()})
			while _socket.get_available_packet_count() > 0:
				_handle_packet(_socket.get_packet())
		WebSocketPeer.STATE_CLOSED:
			_reset("COULDN'T REACH THE SERVER. TRY AGAIN" if state == STATE_CONNECTING else "LOST CONNECTION TO THE SERVER")
		_:
			if state == STATE_CONNECTING and _now() - _connect_started > _connect_timeout:
				_reset("LOCAL SERVER NOT RUNNING. START server/server_main.tscn" if _is_local() else "COULDN'T CONNECT. SERVER MAY BE WAKING UP")


# --- actions the game calls ---------------------------------------------------

func connect_to_server() -> void:
	_server_url = Settings.online_server_url()
	if _socket != null:
		disconnect_from_server()
	_socket = WebSocketPeer.new()
	if _socket.connect_to_url(_server_url) != OK:
		_reset("COULDN'T START CONNECTION")
		return
	_connect_started = _now()
	_connect_timeout = 8.0 if _is_local() else 45.0
	var hint := "START server/server_main.tscn FOR LOCAL PLAY" if _is_local() else "FREE SERVER MAY TAKE A MOMENT TO WAKE UP"
	_set_state(STATE_CONNECTING, "CONNECTING TO ONLINE SERVER...\n" + hint)


func disconnect_from_server() -> void:
	if _socket != null:
		_socket.close()
	_reset("DISCONNECTED")


func create_room(player_name: String) -> void:
	if state != STATE_CONNECTED or not room_code.is_empty():
		_report_error("FINISH THE CURRENT ONLINE ACTION FIRST")
		return
	if _send({"type": "create_room", "name": player_name}):
		_set_state(STATE_CONNECTED, "CREATING ROOM...")


func join_room(code: String, player_name: String) -> void:
	if state != STATE_CONNECTED or not room_code.is_empty():
		_report_error("FINISH THE CURRENT ONLINE ACTION FIRST")
		return
	var clean := code.strip_edges().to_upper()
	if _send({"type": "join_room", "code": clean, "name": player_name}):
		_set_state(STATE_CONNECTED, "JOINING ROOM %s..." % clean)


func leave_room() -> void:
	if room_code.is_empty():
		return
	_send({"type": "leave_room"})
	room_code = ""
	seat = -1
	_set_state(STATE_CONNECTED, "LEFT ROOM")


func start_match() -> void:
	_send({"type": "start"})


## Sends where our paddle is. Only sends when it changed, or as a keepalive.
func send_paddle(position: float) -> void:
	if state != STATE_PLAYING:
		return
	position = snappedf(position, 0.1)
	var now := _now()
	var changed := absf(position - _last_target) >= 0.1
	if not changed and now - _last_input_time < INPUT_KEEPALIVE:
		return
	_last_input_time = now
	_last_target = position
	_send({"type": "input", "target_y": position})


## A swing in the line finale, stamped with the server tick the player saw.
func send_swing(at_tick: int) -> void:
	if state == STATE_PLAYING:
		_send({"type": "hit", "tick": at_tick})


func is_open() -> bool:
	return _socket != null and _socket.get_ready_state() == WebSocketPeer.STATE_OPEN


# --- internals ----------------------------------------------------------------

func _on_connected() -> void:
	if not OS.has_feature("web"):
		# Send small packets right away instead of batching them (lower lag).
		_socket.set_no_delay(true)
	_ping_elapsed = PING_INTERVAL
	_set_state(STATE_CONNECTED, "CONNECTED TO ONLINE SERVER")


func _handle_packet(packet: PackedByteArray) -> void:
	var message = JSON.parse_string(packet.get_string_from_utf8())
	if not message is Dictionary:
		_report_error("SERVER SENT INVALID DATA")
		return
	match str(message.get("type", "")):
		"arena_room":
			room_code = str(message.get("code", ""))
			seat = int(message.get("seat", -1))
			_set_state(STATE_IN_ROOM, "ROOM READY")
			room_joined.emit()
		"arena_lobby":
			seat = int(message.get("you", seat))
			if not message.get("started", false) and state == STATE_PLAYING:
				_set_state(STATE_IN_ROOM, "MATCH OVER")
			lobby_changed.emit(message)
		"arena_started":
			_set_state(STATE_PLAYING, "MATCH STARTED")
			var names = message.get("names", [])
			match_started.emit(names if names is Array else [])
		"arena_snapshot":
			snapshot_received.emit(message)
		"left_room":
			room_code = ""
			seat = -1
			_set_state(STATE_CONNECTED, "LEFT ROOM")
		"pong":
			_measure_rtt(message.get("t"))
		"error":
			_report_error(str(message.get("message", "ONLINE ERROR")))


func _measure_rtt(sent_at) -> void:
	if not (sent_at is float or sent_at is int):
		return
	var sample := _now() - float(sent_at)
	if sample < 0.0 or sample > MAX_RTT * 3.0:
		return
	sample = minf(sample, MAX_RTT)
	if not _rtt_measured:
		_rtt_measured = true
		rtt_seconds = sample
		return
	# Rise quickly when the connection gets worse, settle slowly when it improves.
	rtt_seconds = lerpf(rtt_seconds, sample, 0.35 if sample > rtt_seconds else 0.12)


func _send(message: Dictionary) -> bool:
	if not is_open():
		_report_error("NOT CONNECTED TO ONLINE SERVER")
		return false
	if _socket.send_text(JSON.stringify(message)) != OK:
		_report_error("COULDN'T SEND DATA TO ONLINE SERVER")
		return false
	return true


func _set_state(next_state: int, message: String) -> void:
	state = next_state
	status_message = message
	connection_changed.emit(state, message)


func _report_error(message: String) -> void:
	status_message = message
	online_error.emit(message)
	connection_changed.emit(state, message)


func _reset(message: String) -> void:
	_socket = null
	_ping_elapsed = 0.0
	_rtt_measured = false
	rtt_seconds = DEFAULT_RTT
	_last_target = -1.0
	room_code = ""
	seat = -1
	_set_state(STATE_DISCONNECTED, message)


func _is_local() -> bool:
	return _server_url.begins_with("ws://127.0.0.1") or _server_url.begins_with("ws://localhost")


func _now() -> float:
	return Time.get_ticks_usec() / 1000000.0
