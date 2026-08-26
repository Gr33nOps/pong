extends SceneTree

var messages: Array[Dictionary] = []
var failures: Array[String] = []


func _initialize() -> void:
	var room = preload("res://match_room.gd").new()
	room.configure("ABC234", _capture_message, Callable())
	_check(room.add_creator(1), "creator can open a room")
	_check(room.add_joiner(2), "second player can join")
	room.handle_message(1, {"type": "rematch"})
	room.simulation.left_score = 4
	room.remove_peer(1)
	_check(room.add_joiner(3), "a replacement can join after the creator leaves")
	_check(room.left_peer_id == 3 and room.right_peer_id == 2, "replacement fills the vacant left side")
	_check(room.simulation.left_score == 0, "a replacement pairing starts a fresh match")
	_check(_has_message(3, "room_joined", "left"), "replacement receives its correct side")
	room.handle_message(2, {"type": "rematch"})
	_check(not _has_message(2, "rematch_started"), "a departed player's rematch vote is discarded")
	if failures.is_empty():
		print("PONG room rejoin smoke: passed")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)


func _capture_message(peer_id: int, message: Dictionary) -> void:
	var captured := message.duplicate(true)
	captured["peer_id"] = peer_id
	messages.append(captured)


func _has_message(peer_id: int, type: String, side: String = "") -> bool:
	for message in messages:
		if int(message.get("peer_id", -1)) != peer_id or str(message.get("type", "")) != type:
			continue
		if side.is_empty() or str(message.get("side", "")) == side:
			return true
	return false


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
