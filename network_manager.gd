extends Node

signal connection_changed(state: int, message: String)
signal room_changed(code: String, side: String, status: String)
signal opponent_changed(connected: bool)
signal match_ready
signal rematch_started
signal snapshot_received(snapshot: Dictionary)
signal online_error(message: String)

const STATE_DISCONNECTED := 0
const STATE_CONNECTING := 1
const STATE_CONNECTED := 2
const STATE_IN_ROOM := 3
const STATE_PLAYING := 4

var state := STATE_DISCONNECTED
var socket: WebSocketPeer
var server_url := ""
var room_code := ""
var player_side := ""
var status_message := ""
var _connect_started := 0.0
var _connection_timeout := 20.0
var _last_input_sent := 0.0
var _input_send_interval := 1.0 / 30.0


func _process(delta: float) -> void:
	if socket == null:
		return
	socket.poll()
	var ready := socket.get_ready_state()
	if ready == WebSocketPeer.STATE_OPEN:
		if state == STATE_CONNECTING:
			_set_state(STATE_CONNECTED, "CONNECTED TO ONLINE SERVER")
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
	var result := socket.connect_to_url(server_url)
	if result != OK:
		_reset_connection("COULDN'T START CONNECTION")
		return
	_connect_started = Time.get_ticks_msec() / 1000.0
	_connection_timeout = 8.0 if server_url.begins_with("ws://127.0.0.1") or server_url.begins_with("ws://localhost") else 20.0
	var wake_message := "START server/server_main.tscn FOR LOCAL PLAY" if _connection_timeout < 10.0 else "FREE SERVER MAY TAKE A MOMENT TO WAKE UP"
	_set_state(STATE_CONNECTING, "CONNECTING TO ONLINE SERVER...\n" + wake_message)


func disconnect_from_server() -> void:
	if socket != null:
		socket.close()
	_reset_connection("DISCONNECTED")


func create_room() -> void:
	_send({"type": "create_room"})
	_set_state(STATE_CONNECTED, "CREATING ROOM...")


func join_room(code: String) -> void:
	var normalized := code.strip_edges().to_upper()
	var room_regex := RegEx.new()
	room_regex.compile("^[A-Z0-9]{6}$")
	if normalized.length() != 6 or room_regex.search(normalized) == null:
		_emit_error("ROOM CODE MUST BE SIX CHARACTERS")
		return
	_send({"type": "join_room", "code": normalized})
	_set_state(STATE_CONNECTED, "JOINING ROOM %s..." % normalized)


func leave_room() -> void:
	_send({"type": "leave_room"})
	room_code = ""
	player_side = ""
	_set_state(STATE_CONNECTED, "LEFT ROOM")


func send_input(axis: float, target_y: float = -1.0) -> void:
	if state != STATE_PLAYING:
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_input_sent < _input_send_interval:
		return
	_last_input_sent = now
	_send({"type": "input", "axis": clampf(axis, -1.0, 1.0), "target_y": target_y})


func request_serve(aim: float) -> void:
	_send({"type": "serve", "aim": clampf(aim, -1.0, 1.0)})


func request_rematch() -> void:
	_send({"type": "rematch"})


func connection_is_open() -> bool:
	return socket != null and socket.get_ready_state() == WebSocketPeer.STATE_OPEN


func _send(message: Dictionary) -> void:
	if not connection_is_open():
		_emit_error("NOT CONNECTED TO ONLINE SERVER")
		return
	socket.send_text(JSON.stringify(message))


func _handle_packet(packet: PackedByteArray) -> void:
	var text := packet.get_string_from_utf8().strip_edges()
	if text.is_empty():
		return
	var parsed = JSON.parse_string(text)
	if not parsed is Dictionary:
		_emit_error("SERVER SENT INVALID DATA")
		return
	var message: Dictionary = parsed
	var message_type := str(message.get("type", ""))
	match message_type:
		"room_created":
			room_code = str(message.get("code", ""))
			player_side = str(message.get("side", "left"))
			_set_state(STATE_IN_ROOM, "ROOM CREATED")
			room_changed.emit(room_code, player_side, "WAITING FOR OPPONENT...")
		"room_joined":
			room_code = str(message.get("code", ""))
			player_side = str(message.get("side", "right"))
			_set_state(STATE_IN_ROOM, "ROOM JOINED")
			room_changed.emit(room_code, player_side, "WAITING FOR OPPONENT...")
		"opponent_connected":
			opponent_changed.emit(true)
			_set_state(STATE_PLAYING, "OPPONENT CONNECTED")
			match_ready.emit()
		"snapshot":
			snapshot_received.emit(message)
		"opponent_disconnected":
			opponent_changed.emit(false)
			_set_state(STATE_IN_ROOM, "OPPONENT DISCONNECTED")
		"rematch_started":
			rematch_started.emit()
		"error":
			_emit_error(str(message.get("message", "ONLINE ERROR")))
		"left_room":
			room_code = ""
			player_side = ""
			_set_state(STATE_CONNECTED, "LEFT ROOM")
		_:
			pass


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
	room_code = ""
	player_side = ""
	_set_state(STATE_DISCONNECTED, message)
