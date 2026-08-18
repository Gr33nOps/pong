class_name RoomManager
extends RefCounted

const CODE_ALPHABET := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
const ROOM_CODE_LENGTH := 6
const MAX_ROOMS := 512
const MATCH_ROOM_SCRIPT = preload("res://match_room.gd")

var rooms: Dictionary = {}
var peer_rooms: Dictionary = {}
var _send_callback: Callable
var _close_callback: Callable
var _rng := RandomNumberGenerator.new()


func configure(send_callback: Callable, close_callback: Callable) -> void:
	_send_callback = send_callback
	_close_callback = close_callback
	_rng.randomize()


func create_room(peer_id: int) -> String:
	if peer_rooms.has(peer_id):
		_send_error(peer_id, "ALREADY IN A ROOM")
		return ""
	if rooms.size() >= MAX_ROOMS:
		_send_error(peer_id, "SERVER ROOM LIMIT REACHED")
		return ""
	var code := _new_code()
	var room = MATCH_ROOM_SCRIPT.new()
	room.configure(code, _send_callback, _close_callback)
	if not room.add_creator(peer_id):
		_send_error(peer_id, "COULD NOT CREATE ROOM")
		return ""
	rooms[code] = room
	peer_rooms[peer_id] = code
	return code


func join_room(peer_id: int, code: String) -> bool:
	if peer_rooms.has(peer_id):
		_send_error(peer_id, "ALREADY IN A ROOM")
		return false
	var normalized := code.strip_edges().to_upper()
	if not rooms.has(normalized):
		_send_error(peer_id, "ROOM NOT FOUND")
		return false
	var room = rooms[normalized]
	if room.is_full():
		_send_error(peer_id, "ROOM IS FULL")
		return false
	if not room.add_joiner(peer_id):
		_send_error(peer_id, "COULD NOT JOIN ROOM")
		return false
	peer_rooms[peer_id] = normalized
	return true


func leave_room(peer_id: int) -> void:
	if not peer_rooms.has(peer_id):
		_send_error(peer_id, "NOT IN A ROOM")
		return
	var code := str(peer_rooms[peer_id])
	peer_rooms.erase(peer_id)
	if not rooms.has(code):
		_send_callback.call(peer_id, {"type": "left_room"})
		return
	var room = rooms[code]
	room.remove_peer(peer_id)
	_send(peer_id, {"type": "left_room"})
	if room.peers().is_empty():
		rooms.erase(code)


func handle_message(peer_id: int, message: Dictionary) -> void:
	var message_type := str(message.get("type", ""))
	match message_type:
		"create_room":
			create_room(peer_id)
		"join_room":
			join_room(peer_id, str(message.get("code", "")))
		"leave_room":
			leave_room(peer_id)
		"input", "serve", "rematch":
			if not peer_rooms.has(peer_id):
				_send_error(peer_id, "JOIN A ROOM FIRST")
				return
			var code := str(peer_rooms[peer_id])
			if rooms.has(code):
				var room = rooms[code]
				room.handle_message(peer_id, message)
		_:
			_send_error(peer_id, "UNKNOWN MESSAGE TYPE")


func disconnect_peer(peer_id: int) -> void:
	if not peer_rooms.has(peer_id):
		return
	var code := str(peer_rooms[peer_id])
	peer_rooms.erase(peer_id)
	if not rooms.has(code):
		return
	var room = rooms[code]
	room.remove_peer(peer_id)
	if room.peers().is_empty():
		rooms.erase(code)


func tick(delta: float) -> void:
	for room_value in rooms.values():
		var room = room_value
		room.tick(delta)


func _new_code() -> String:
	for _attempt in 32:
		var code := ""
		for _i in ROOM_CODE_LENGTH:
			code += CODE_ALPHABET[_rng.randi_range(0, CODE_ALPHABET.length() - 1)]
		if not rooms.has(code):
			return code
	return "%06d" % _rng.randi_range(0, 999999)


func _send(peer_id: int, message: Dictionary) -> void:
	if _send_callback.is_valid():
		_send_callback.call(peer_id, message)


func _send_error(peer_id: int, message: String) -> void:
	_send(peer_id, {"type": "error", "message": message})
