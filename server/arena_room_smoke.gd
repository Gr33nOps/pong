extends SceneTree

const ROOM_MANAGER_SCRIPT = preload("res://room_manager.gd")

var failures: Array[String] = []
var sent: Array = []


func _initialize() -> void:
	_test_room_flow()
	_test_full_room()
	_test_held_hit()
	if failures.is_empty():
		print("PONG arena room smoke: passed")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)


func _test_room_flow() -> void:
	var manager = ROOM_MANAGER_SCRIPT.new()
	manager.configure(func(peer_id: int, message: Dictionary) -> void: sent.append([peer_id, message]))
	var code: String = manager.create_room(1, "ali")
	var room = manager.rooms[code]
	_check(_last_of(1, "arena_room").get("seat", -1) == 0 and room.host_peer == 1, "the creator takes the first seat and is the host")
	manager.handle_message(1, {"type": "start"})
	_check(not room.started and _last_of(1, "error").get("message", "") == "NEED AT LEAST 2 PLAYERS", "a match needs at least two players")
	_check(manager.join_room(2, code, "  sara!! "), "a friend joins with the code")
	_check(manager.join_room(3, code, ""), "a third friend joins")
	var lobby := _last_of(3, "arena_lobby")
	_check(lobby.get("names", []) == ["ALI", "SARA", "PLAYER 3"] and int(lobby.get("you", -1)) == 2 and int(lobby.get("host", -1)) == 0, "the lobby lists everyone's cleaned-up name")
	manager.handle_message(2, {"type": "start"})
	_check(not room.started, "only the host can start")
	manager.handle_message(1, {"type": "start"})
	_check(room.started and room.simulation.seat_count == 3 and room.simulation.wall_count() == 3, "three players start on a triangle")
	_check(_last_of(2, "arena_started").get("names", []) == ["ALI", "SARA", "PLAYER 3"], "everyone hears the match started, with the names")
	sent.clear()
	for _i in 30:
		manager.tick(1.0 / 60.0)
	_check(not _last_of(1, "arena_snapshot").is_empty(), "the room streams snapshots")
	_check(not manager.join_room(5, code, "late"), "nobody joins a match in progress")
	manager.disconnect_peer(2)
	_check(room.started and room.simulation.order == [0, 2], "a player who leaves mid-match is knocked out and the others play on")
	manager.disconnect_peer(1)
	_check(room.host_peer == 3, "the host passes on when the host leaves")
	manager.tick(1.0 / 60.0)
	_check(not room.started and room.simulation.winner == 2, "the last player left wins and the room waits again")
	_check(room.names == ["PLAYER 3"] and room.seats == [3], "people who left lose their seats after the match")
	_check(manager.join_room(6, code, "new"), "friends can join between matches")
	manager.disconnect_peer(3)
	manager.disconnect_peer(6)
	_check(not manager.rooms.has(code), "an empty room is removed")


func _test_full_room() -> void:
	var manager = ROOM_MANAGER_SCRIPT.new()
	manager.configure(func(_peer_id: int, _message: Dictionary) -> void: pass)
	var code: String = manager.create_room(1, "host")
	for peer_id in range(2, 11):
		manager.join_room(peer_id, code, "p%d" % peer_id)
	_check(manager.rooms[code].seats.size() == 10, "a room holds ten players")
	_check(not manager.join_room(11, code, "eleven"), "an eleventh player can't join")


func _test_held_hit() -> void:
	var manager = ROOM_MANAGER_SCRIPT.new()
	manager.configure(func(_peer_id: int, _message: Dictionary) -> void: pass)
	var code: String = manager.create_room(1, "a")
	manager.join_room(2, code, "b")
	manager.handle_message(1, {"type": "start"})
	var room = manager.rooms[code]
	var sim = room.simulation
	sim.state = sim.STATE_PLAY
	var end: float = sim.line_end(0)
	sim.ball_pos = Vector2(end + 120.0, 0.0)
	sim.ball_vel = Vector2(-600.0, 0.0)
	# The swing was made for a moment slightly ahead of the server's clock.
	manager.handle_message(1, {"type": "hit", "tick": sim.tick_number + 12})
	for _i in 14:
		room._apply_due_hits()
		sim.tick(1.0 / 120.0)
	_check(sim.ball_vel.x > 0.0, "a swing that reaches the server early is held until the moment the player saw")


func _last_of(peer_id: int, message_type: String) -> Dictionary:
	for index in range(sent.size() - 1, -1, -1):
		var entry: Array = sent[index]
		if entry[0] == peer_id and entry[1].get("type", "") == message_type:
			return entry[1]
	return {}


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
