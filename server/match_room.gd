class_name MatchRoom
extends RefCounted

const SNAPSHOT_INTERVAL := 1.0 / 30.0
const MATCH_SIMULATION_SCRIPT = preload("res://match_simulation.gd")

var code := ""
var left_peer_id := -1
var right_peer_id := -1
var simulation = MATCH_SIMULATION_SCRIPT.new()
var started := false
var _snapshot_timer := 0.0
var _rematch_votes: Dictionary = {}
var _send_callback: Callable
var _close_callback: Callable


func configure(room_code: String, send_callback: Callable, close_callback: Callable) -> void:
	code = room_code
	_send_callback = send_callback
	_close_callback = close_callback
	simulation.reset_match()


func has_peer(peer_id: int) -> bool:
	return peer_id == left_peer_id or peer_id == right_peer_id


func is_full() -> bool:
	return left_peer_id != -1 and right_peer_id != -1


func add_creator(peer_id: int) -> bool:
	if left_peer_id != -1:
		return false
	left_peer_id = peer_id
	_send(peer_id, {"type": "room_created", "code": code, "side": "left"})
	return true


func add_joiner(peer_id: int) -> bool:
	if is_full() or has_peer(peer_id):
		return false
	var joined_side := "right"
	if left_peer_id == -1:
		left_peer_id = peer_id
		joined_side = "left"
	else:
		right_peer_id = peer_id
	_rematch_votes.clear()
	simulation.reset_match()
	_send(peer_id, {"type": "room_joined", "code": code, "side": joined_side})
	_send(left_peer_id, {"type": "opponent_connected", "side": "left"})
	_send(right_peer_id, {"type": "opponent_connected", "side": "right"})
	started = true
	_snapshot_timer = 0.0
	_send_snapshot(true)
	return true


func remove_peer(peer_id: int) -> Array[int]:
	var remaining: Array[int] = []
	if peer_id == left_peer_id:
		left_peer_id = -1
		if right_peer_id != -1:
			remaining.append(right_peer_id)
	elif peer_id == right_peer_id:
		right_peer_id = -1
		if left_peer_id != -1:
			remaining.append(left_peer_id)
	if not remaining.is_empty():
		_send(remaining[0], {"type": "opponent_disconnected"})
	_rematch_votes.clear()
	started = false
	return remaining


func handle_message(peer_id: int, message: Dictionary) -> bool:
	if not has_peer(peer_id):
		return false
	var message_type := str(message.get("type", ""))
	match message_type:
		"input":
			simulation.set_input(_side_for_peer(peer_id), float(message.get("axis", 0.0)), float(message.get("target_y", -1.0)))
		"serve":
			if simulation.serve(_side_for_peer(peer_id), float(message.get("aim", 0.0))):
				_send_snapshot(true)
		"rematch":
			_rematch_votes[peer_id] = true
			if _rematch_votes.size() >= 2 and is_full():
				_rematch_votes.clear()
				simulation.reset_match()
				_send(left_peer_id, {"type": "rematch_started"})
				_send(right_peer_id, {"type": "rematch_started"})
				_send_snapshot(true)
		_:
			return false
	return true


func tick(delta: float) -> void:
	if not is_full() or not started:
		return
	simulation.tick(delta)
	_snapshot_timer += delta
	if _snapshot_timer >= SNAPSHOT_INTERVAL:
		_snapshot_timer = fmod(_snapshot_timer, SNAPSHOT_INTERVAL)
		_send_snapshot(false)


func peers() -> Array[int]:
	var result: Array[int] = []
	if left_peer_id != -1:
		result.append(left_peer_id)
	if right_peer_id != -1:
		result.append(right_peer_id)
	return result


func _send_snapshot(force: bool) -> void:
	if not force and not is_full():
		return
	var snapshot := simulation.snapshot()
	_send(left_peer_id, snapshot)
	_send(right_peer_id, snapshot)


func _send(peer_id: int, message: Dictionary) -> void:
	if peer_id == -1 or not _send_callback.is_valid():
		return
	_send_callback.call(peer_id, message)


func _side_for_peer(peer_id: int) -> String:
	return "left" if peer_id == left_peer_id else "right"
