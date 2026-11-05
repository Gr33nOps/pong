extends SceneTree

const ROOM_MANAGER_SCRIPT = preload("res://room_manager.gd")

var failures: Array[String] = []
var sent: Array = []


func _initialize() -> void:
	var manager = ROOM_MANAGER_SCRIPT.new()
	manager.configure(func(peer_id: int, message: Dictionary) -> void: sent.append([peer_id, message]), func(_peer_id: int) -> void: pass)
	var code: String = manager.create_room(1, "quad")
	_check(_last_of(1, "quad_room").get("seat", -1) == 0, "the creator takes the first seat")
	_check(manager.join_room(2, code, "quad"), "a second player joins a four-player room")
	_check(_last_of(2, "quad_room").get("seat", -1) == 1, "the second player takes the next seat")
	_check(not manager.join_room(3, code), "a two-player client cannot join a four-player room")
	_check(str(_last_of(3, "error").get("message", "")).contains("4-PLAYER"), "the wrong-mode join explains the room type")
	var duel_code: String = manager.create_room(9)
	_check(not manager.join_room(4, duel_code, "quad"), "a four-player client cannot join a two-player room")
	var lobby := _last_of(2, "quad_lobby")
	_check(lobby.get("seats", []) == [true, true, false, false] and int(lobby.get("host", -1)) == 0, "the lobby lists filled seats and the host")
	manager.handle_message(2, {"type": "start"})
	var room = manager.rooms[code]
	_check(not room.started, "only the host can start")
	manager.handle_message(1, {"type": "start"})
	_check(room.started and room.simulation.cpu == [false, false, true, true], "starting fills empty seats with CPU paddles")
	_check(not _last_of(2, "quad_started").is_empty(), "everyone hears that the match started")
	sent.clear()
	manager.handle_message(2, {"type": "input", "axis": 0.0, "target_y": 400.0})
	for _i in 120:
		manager.tick(1.0 / 60.0)
	_check(not _last_of(1, "quad_snapshot").is_empty(), "the room streams snapshots")
	_check(room.simulation.paddle_pos[1] > 300.0, "a player's reported paddle position drives their seat")
	_check(not manager.join_room(5, code, "quad"), "nobody joins a match in progress")
	manager.disconnect_peer(1)
	_check(room.simulation.cpu[0] and room.host_peer == 2, "a dropped player's seat goes to the CPU and the host passes on")
	manager.disconnect_peer(2)
	_check(not manager.rooms.has(code), "an empty four-player room is removed")
	if failures.is_empty():
		print("PONG four-player room smoke: passed")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)


func _last_of(peer_id: int, message_type: String) -> Dictionary:
	for index in range(sent.size() - 1, -1, -1):
		var entry: Array = sent[index]
		if entry[0] == peer_id and entry[1].get("type", "") == message_type:
			return entry[1]
	return {}


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
