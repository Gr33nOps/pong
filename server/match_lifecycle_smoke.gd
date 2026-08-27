extends SceneTree

var failures: Array[String] = []


func _initialize() -> void:
	var simulation = preload("res://match_simulation.gd").new()
	simulation.reset_match()
	_check(simulation.ball_position.x < 100.0 and is_equal_approx(simulation.ball_position.y, simulation.left_y), "opening ball rests beside the serving paddle")
	simulation.set_input("left", 1.0, -1.0)
	simulation.tick(0.05)
	var moving_snapshot: Dictionary = simulation.snapshot()
	var paddle_velocities = moving_snapshot.get("paddle_velocities", {})
	_check(paddle_velocities is Dictionary and float(paddle_velocities.get("left", 0.0)) > 0.0, "snapshots include paddle velocity for client extrapolation")
	_check(is_equal_approx(simulation.ball_position.y, simulation.left_y), "unserved ball follows its paddle")
	_check(simulation.serve("left", 0.0), "opening server can serve")
	simulation._score("left")
	_check(simulation.between_points and simulation.serving, "a point enters the between-points hold")
	simulation.tick(simulation.SCORE_HOLD + 0.01)
	_check(not simulation.between_points and simulation.serving, "between-points hold returns to a serveable state")
	_check(simulation.ball_position.x > simulation.COURT_WIDTH - 100.0 and is_equal_approx(simulation.ball_position.y, simulation.right_y), "next ball rests beside the new server")
	_check(simulation.serve("right", 0.0), "the next server can continue the match")

	simulation.set_input("left", 1.0, -1.0)
	simulation.reset_match()
	var reset_y: float = simulation.left_y
	simulation.tick(0.1)
	_check(is_equal_approx(simulation.left_y, reset_y), "match reset clears stale movement input")
	simulation.set_input("left", 1.0, -1.0)
	simulation.tick(0.1)
	var moved_y: float = simulation.left_y
	simulation.tick(simulation.INPUT_TIMEOUT + 0.01)
	_check(is_equal_approx(simulation.left_y, moved_y), "stale network input stops instead of moving forever")

	var messages: Array[Dictionary] = []
	var room = preload("res://match_room.gd").new()
	room.configure("ABC234", func(peer_id: int, message: Dictionary) -> void:
		var captured := message.duplicate(true)
		captured["peer_id"] = peer_id
		messages.append(captured)
	, Callable())
	room.add_creator(1)
	room.add_joiner(2)
	room.handle_message(1, {"type": "rematch"})
	room.handle_message(2, {"type": "rematch"})
	_check(not _has_message(messages, "rematch_started"), "rematch votes cannot reset an active match")
	room.simulation.game_over = true
	room.handle_message(1, {"type": "rematch"})
	room.handle_message(2, {"type": "rematch"})
	_check(_has_message(messages, "rematch_started"), "both players can rematch after game over")

	var manager = preload("res://room_manager.gd").new()
	manager.configure(func(peer_id: int, message: Dictionary) -> void:
		var captured := message.duplicate(true)
		captured["peer_id"] = peer_id
		messages.append(captured)
	, Callable())
	manager.handle_message(9, {"type": "ping"})
	_check(_has_message(messages, "pong"), "waiting-room heartbeat receives a pong")

	if failures.is_empty():
		print("PONG server match lifecycle smoke: passed")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)


func _has_message(messages: Array[Dictionary], message_type: String) -> bool:
	for message in messages:
		if str(message.get("type", "")) == message_type:
			return true
	return false


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
