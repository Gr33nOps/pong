extends SceneTree

const ROOM_MANAGER_SCRIPT = preload("res://room_manager.gd")

var failures: Array[String] = []
var sent: Array = []


func _initialize() -> void:
	var manager = ROOM_MANAGER_SCRIPT.new()
	manager.configure(func(peer_id: int, message: Dictionary) -> void: sent.append([peer_id, message]))
	var code: String = manager.create_room(1, 5)
	var room = manager.rooms[code]
	_check(room.size == 5 and _last_of(1, "arena_room").get("seat", -1) == 0, "the host creates a five-sided room and takes the first seat")
	_check(manager.join_room(2, code), "a friend joins with the code")
	_check(_last_of(2, "arena_room").get("seat", -1) == 1, "the friend takes the next seat")
	var lobby := _last_of(2, "arena_lobby")
	_check(lobby.get("seats", []) == [true, true, false, false, false] and int(lobby.get("size", 0)) == 5, "the lobby lists filled and open seats")
	manager.handle_message(2, {"type": "set_size", "size": 7})
	_check(room.size == 5, "only the host can change the room size")
	manager.handle_message(1, {"type": "set_size", "size": 1})
	_check(room.size == 2, "the room never shrinks below the people already in it")
	manager.handle_message(1, {"type": "set_size", "size": 9})
	_check(room.size == 7, "rooms hold at most seven players")
	manager.handle_message(1, {"type": "set_size", "size": 3})
	manager.handle_message(2, {"type": "start"})
	_check(not room.started, "only the host can start")
	manager.handle_message(1, {"type": "start"})
	_check(room.started and room.simulation.cpu == [false, false, true] and room.simulation.wall_count() == 3, "starting fills the empty side with AI on a triangle")
	_check(not _last_of(2, "arena_started").is_empty(), "everyone hears that the match started")
	sent.clear()
	for _i in 120:
		manager.tick(1.0 / 60.0)
	_check(not _last_of(1, "arena_snapshot").is_empty(), "the room streams snapshots")
	_check(not manager.join_room(5, code), "nobody joins a match in progress")
	manager.disconnect_peer(1)
	_check(room.simulation.cpu[0] and room.host_peer == 2, "a dropped player's seat goes to the AI and the host passes on")
	manager.disconnect_peer(2)
	_check(not manager.rooms.has(code), "an empty room is removed")
	_test_held_hit()
	if failures.is_empty():
		print("PONG arena room smoke: passed")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)


func _test_held_hit() -> void:
	var manager = ROOM_MANAGER_SCRIPT.new()
	manager.configure(func(_peer_id: int, _message: Dictionary) -> void: pass)
	var code: String = manager.create_room(1, 2)
	manager.join_room(2, code)
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
