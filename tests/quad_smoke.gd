extends SceneTree

const QuadSimulation = preload("res://quad_simulation.gd")

var failures: Array[String] = []


func _initialize() -> void:
	_test_paddle_return()
	_test_goal_costs_a_life()
	_test_knocked_out_wall_rebounds()
	_test_corner_rebounds()
	_test_cpu_match_finishes()
	_test_snapshot_round_trip()
	_test_server_copy_matches()
	await _test_cpu_scene()
	await _test_local_join_scene()
	await _test_failed_connection_clears_request()
	if failures.is_empty():
		print("PONG four-player smoke: passed")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)


func _playing_sim() -> QuadSimulation:
	var sim := QuadSimulation.new()
	sim.reset_match([false, false, false, false])
	sim.state = QuadSimulation.STATE_PLAY
	return sim


func _test_paddle_return() -> void:
	var sim := _playing_sim()
	sim.ball_pos = Vector2(QuadSimulation.contact_plane(QuadSimulation.LEFT) + 20.0, QuadSimulation.SIZE * 0.5)
	sim.ball_vel = Vector2(-500.0, 0.0)
	for _i in 12:
		sim.tick(1.0 / 120.0)
	_check(sim.ball_vel.x > 0.0 and sim.hits == 1, "the left paddle returns a ball aimed at its centre")
	_check(sim.events.any(func(event: Dictionary) -> bool: return event["type"] == "paddle" and event["seat"] == QuadSimulation.LEFT), "a paddle return reports a paddle event")


func _test_goal_costs_a_life() -> void:
	var sim := _playing_sim()
	sim.paddle_pos[QuadSimulation.LEFT] = QuadSimulation.paddle_max()
	sim.ball_pos = Vector2(60.0, QuadSimulation.paddle_min() - 20.0)
	sim.ball_vel = Vector2(-600.0, 0.0)
	for _i in 30:
		sim.tick(1.0 / 120.0)
	_check(sim.lives[QuadSimulation.LEFT] == QuadSimulation.STARTING_LIVES - 1, "a missed ball costs the left player a life")
	_check(sim.state == QuadSimulation.STATE_COUNTDOWN and sim.serve_seat == QuadSimulation.LEFT, "the next serve goes to the player who lost the life")


func _test_knocked_out_wall_rebounds() -> void:
	var sim := _playing_sim()
	sim.lives[QuadSimulation.TOP] = 0
	sim.ball_pos = Vector2(QuadSimulation.SIZE * 0.5, 60.0)
	sim.ball_vel = Vector2(40.0, -600.0)
	for _i in 30:
		sim.tick(1.0 / 120.0)
	_check(sim.ball_vel.y > 0.0 and sim.lives[QuadSimulation.TOP] == 0, "a knocked-out wall turns solid")
	_check(absf(sim.ball_vel.x) >= sim.ball_vel.length() * QuadSimulation.MIN_AXIS - 0.01, "wall rebounds keep the ball moving across the court")


func _test_corner_rebounds() -> void:
	var sim := _playing_sim()
	sim.ball_pos = Vector2(80.0, 80.0)
	sim.ball_vel = Vector2(-400.0, -400.0)
	for _i in 30:
		sim.tick(1.0 / 120.0)
	var lost := false
	for seat in QuadSimulation.SEATS:
		lost = lost or sim.lives[seat] < QuadSimulation.STARTING_LIVES
	_check(not lost and sim.ball_vel.x > 0.0 and sim.ball_vel.y > 0.0, "a corner block sends a ball back into the court")


func _test_cpu_match_finishes() -> void:
	var sim := QuadSimulation.new()
	sim.rng.seed = 7
	sim.reset_match([true, true, true, true])
	var ticks := 0
	var max_ticks := 120 * 60 * 20
	var in_bounds := true
	while sim.state != QuadSimulation.STATE_OVER and ticks < max_ticks:
		sim.tick(1.0 / 120.0)
		sim.events.clear()
		ticks += 1
		if not is_finite(sim.ball_pos.x) or not is_finite(sim.ball_pos.y):
			in_bounds = false
			break
	_check(in_bounds, "the ball position stays finite")
	_check(sim.state == QuadSimulation.STATE_OVER and sim.winner >= 0 and sim.alive_count() == 1, "an all-CPU match ends with one survivor")


func _test_snapshot_round_trip() -> void:
	var sim := _playing_sim()
	sim.ball_pos = Vector2(123.0, 321.0)
	sim.ball_vel = Vector2(-210.0, 330.0)
	sim.lives[QuadSimulation.RIGHT] = 2
	sim.paddle_pos[QuadSimulation.TOP] = 200.0
	var data = JSON.parse_string(JSON.stringify(sim.snapshot()))
	var copy := QuadSimulation.new()
	copy.apply_snapshot(data)
	_check(copy.ball_pos.is_equal_approx(sim.ball_pos) and copy.ball_vel.is_equal_approx(sim.ball_vel), "snapshots carry the ball state")
	_check(copy.lives[QuadSimulation.RIGHT] == 2 and is_equal_approx(copy.paddle_pos[QuadSimulation.TOP], 200.0) and copy.state == QuadSimulation.STATE_PLAY, "snapshots carry lives, paddles and match state")


func _test_server_copy_matches() -> void:
	var client_copy := FileAccess.get_file_as_string("res://quad_simulation.gd")
	var server_copy := FileAccess.get_file_as_string("res://server/quad_simulation.gd")
	_check(not client_copy.is_empty() and client_copy == server_copy, "client and server share an identical four-player simulation")


func _open_scene(quad_mode: String) -> Node:
	get_root().get_node("GameState").quad_mode = quad_mode
	get_root().get_node("SFX").muted = true
	var scene: Node = load("res://quad.tscn").instantiate()
	get_root().add_child(scene)
	await process_frame
	return scene


func _test_cpu_scene() -> void:
	var scene = await _open_scene("cpu")
	_check(scene.phase == scene.Phase.PLAYING and scene.sim.cpu == [false, true, true, true], "the CPU mode starts with you on the left and three CPUs")
	var ball_drawn_in_play := false
	for _i in 240:
		scene._physics_process(1.0 / 60.0)
		ball_drawn_in_play = ball_drawn_in_play or (scene.sim.state == QuadSimulation.STATE_PLAY and scene._ball.visible)
	_check(ball_drawn_in_play, "the CPU match serves and the ball is drawn")
	_check(scene._seat_big[QuadSimulation.LEFT].text == str(scene.sim.lives[QuadSimulation.LEFT]) and scene._seat_small[QuadSimulation.LEFT].text == "YOU", "lives show next to each wall")
	scene._handle_key(KEY_ESCAPE)
	_check(scene.phase == scene.Phase.PAUSED and scene._options == ["resume", "menu"], "Esc pauses a local match")
	var before: Vector2 = scene.sim.ball_pos
	scene._physics_process(1.0 / 60.0)
	_check(scene.sim.ball_pos == before, "a paused match stands still")
	scene._handle_key(KEY_ESCAPE)
	_check(scene.phase == scene.Phase.PLAYING, "Esc resumes")
	scene.free()


func _test_local_join_scene() -> void:
	var scene = await _open_scene("local")
	_check(scene.phase == scene.Phase.LOCAL_JOIN, "local play opens the join screen")
	scene._handle_key(KEY_SPACE)
	_check(scene.phase == scene.Phase.LOCAL_JOIN, "a local match needs at least one player")
	scene._handle_key(KEY_S)
	scene._handle_key(KEY_N)
	scene._claim_pad_seat(0)
	_check(scene._seat_names[QuadSimulation.LEFT] == "P1" and scene._seat_names[QuadSimulation.BOTTOM] == "P2" and scene._seat_names[QuadSimulation.RIGHT] == "P3", "keys claim their own wall and a controller takes the next free one")
	scene._handle_key(KEY_SPACE)
	_check(scene.phase == scene.Phase.PLAYING and scene.sim.cpu == [false, false, true, false], "unclaimed walls are played by the CPU")
	scene.free()


func _test_failed_connection_clears_request() -> void:
	var scene = await _open_scene("online")
	scene._pending_action = "create"
	scene._status.text = "CREATING ROOM..."
	scene._on_connection_changed(0, "COULDN'T CONNECT. SERVER MAY BE WAKING UP")
	_check(scene._pending_action.is_empty() and scene._status.text.begins_with("COULDN'T CONNECT"), "a failed connection shows why and lets the player retry")
	scene.free()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
