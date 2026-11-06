extends SceneTree

const ArenaSimulation = preload("res://scripts/arena_simulation.gd")

var failures: Array[String] = []
var scene_checks_finished := false


func _initialize() -> void:
	_test_geometry()
	_test_paddle_return()
	_test_one_miss_knocks_out()
	_test_line_finale_hits()
	_test_early_swing_locks()
	_test_late_swing_is_judged_in_the_past()
	_test_cpu_matches_finish()
	_test_snapshot_round_trip()
	_test_server_copy_matches()
	await _test_scene_flow()
	_check(scene_checks_finished, "the scene checks ran to the end (a script error stops them early)")
	if failures.is_empty():
		print("PONG arena smoke: passed")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)


func _sim(players: int) -> ArenaSimulation:
	var sim := ArenaSimulation.new()
	var flags := []
	for _seat in players:
		flags.append(false)
	sim.reset_match(flags)
	sim.state = ArenaSimulation.STATE_PLAY
	return sim


func _test_geometry() -> void:
	var ok := true
	for walls in range(3, 11):
		for index in walls:
			ok = ok and is_equal_approx(ArenaSimulation.vertex(index, walls).length(), ArenaSimulation.RADIUS)
		var bottom := (ArenaSimulation.vertex(0, walls) + ArenaSimulation.vertex(1, walls)) * 0.5
		ok = ok and absf(bottom.x) < 0.01 and bottom.y > 0.0
		ok = ok and ArenaSimulation.paddle_min(walls) < ArenaSimulation.paddle_max(walls)
	_check(ok, "every polygon from 3 to 10 sides has wall 0 at the bottom and room for a paddle")


func _test_paddle_return() -> void:
	var sim := _sim(5)
	var frame := ArenaSimulation.wall_frame(0, 5)
	var center: Vector2 = frame[0] + frame[1] * sim.paddle_pos[0] + frame[2] * (ArenaSimulation.contact_plane() + 30.0)
	sim.ball_pos = center
	sim.ball_vel = -frame[2] * 500.0
	for _i in 20:
		sim.tick(1.0 / 120.0)
	_check(sim.ball_vel.dot(frame[2]) > 0.0 and sim.hits == 1, "a pentagon paddle returns a ball aimed at its centre")


func _test_one_miss_knocks_out() -> void:
	var sim := _sim(4)
	var frame := ArenaSimulation.wall_frame(2, 4)
	sim.paddle_pos[2] = ArenaSimulation.paddle_max(4)
	sim.ball_pos = frame[0] + frame[1] * ArenaSimulation.paddle_min(4) + frame[2] * 60.0
	sim.ball_vel = -frame[2] * 600.0
	for _i in 40:
		sim.tick(1.0 / 120.0)
	_check(sim.order == [0, 1, 3] and sim.wall_count() == 3, "one miss knocks the player out and the square becomes a triangle")
	_check(sim.events.any(func(event: Dictionary) -> bool: return event["type"] == "out" and event["wall"] == 2), "the knockout reports which wall disappeared")
	_check(sim.state == ArenaSimulation.STATE_COUNTDOWN and sim.order.has(sim.serve_seat), "play goes on with a serve to a player still in")


func _test_line_finale_hits() -> void:
	var sim := _sim(2)
	_check(sim.is_line(), "two players play the line finale")
	var end := sim.line_end(0)
	sim.ball_pos = Vector2(end + sim.zone[0] * 0.8, 0.0)
	sim.ball_vel = Vector2(-500.0, 0.0)
	_check(sim.press_hit(0), "a swing inside your zone returns the ball")
	var early_speed := sim.ball_vel.x
	var deep := _sim(2)
	deep.ball_pos = Vector2(end + 15.0, 0.0)
	deep.ball_vel = Vector2(-500.0, 0.0)
	deep.press_hit(0)
	_check(early_speed > 0.0 and deep.ball_vel.x > early_speed, "a later, deeper swing sends the ball back faster")


func _test_early_swing_locks() -> void:
	var sim := _sim(2)
	sim.ball_pos = Vector2(0.0, 0.0)
	sim.ball_vel = Vector2(-500.0, 0.0)
	_check(not sim.press_hit(0), "a swing before the ball reaches your zone misses")
	sim.ball_pos = Vector2(sim.line_end(0) + 40.0, 0.0)
	_check(not sim.press_hit(0), "a missed swing locks you out briefly")
	for _i in int(ArenaSimulation.WHIFF_LOCK * 120.0) + 2:
		sim._hit_lock[0] = maxf(sim._hit_lock[0] - 1.0 / 120.0, 0.0)
	_check(sim.press_hit(0), "after the lockout you can swing again")


func _test_late_swing_is_judged_in_the_past() -> void:
	var sim := _sim(2)
	var end := sim.line_end(0)
	sim.ball_pos = Vector2(end + 60.0, 0.0)
	sim.ball_vel = Vector2(-500.0, 0.0)
	var pressed_at := 0
	for i in 30:
		if sim.state != ArenaSimulation.STATE_PLAY:
			break
		sim._advance_line(1.0 / 120.0)
		sim.tick_number += 1
		if i == 0:
			pressed_at = sim.tick_number
	# By now the ball has gone past the end on the server; the swing arrived late.
	_check(sim.ball_pos.x < end or sim.lives[0] < ArenaSimulation.STARTING_LIVES, "the ball has passed the end on the server")
	var replay := _sim(2)
	replay.ball_pos = Vector2(end + 60.0, 0.0)
	replay.ball_vel = Vector2(-500.0, 0.0)
	for i in 6:
		replay._advance_line(1.0 / 120.0)
		replay.tick_number += 1
		if i == 0:
			pressed_at = replay.tick_number
	_check(replay.press_hit(0, pressed_at) and replay.ball_vel.x > 0.0, "a swing is judged where the ball was when the player pressed")


func _test_cpu_matches_finish() -> void:
	var ok := true
	var saw_line := false
	for players in [2, 3, 5, 7, 10]:
		var sim := ArenaSimulation.new()
		sim.rng.seed = 11 + players
		var flags := []
		for _seat in players:
			flags.append(true)
		sim.reset_match(flags)
		var ticks := 0
		while sim.state != ArenaSimulation.STATE_OVER and ticks < 120 * 60 * 20:
			sim.tick(1.0 / 120.0)
			saw_line = saw_line or sim.is_line()
			sim.events.clear()
			ticks += 1
			if not is_finite(sim.ball_pos.x) or not is_finite(sim.ball_pos.y):
				ok = false
				break
		ok = ok and sim.state == ArenaSimulation.STATE_OVER and sim.winner >= 0 and sim.order.size() == 1
	_check(ok, "all-CPU matches of 2, 3, 5, 7 and 10 players end with one winner")
	_check(saw_line, "matches finish through the line finale")


func _test_snapshot_round_trip() -> void:
	var sim := _sim(6)
	sim.ball_pos = Vector2(12.0, -34.0)
	sim.ball_vel = Vector2(-210.0, 330.0)
	sim.lives[4] = 0
	sim.order.erase(4)
	sim.paddle_pos[2] = 100.0
	var data = JSON.parse_string(JSON.stringify(sim.snapshot()))
	var copy := ArenaSimulation.new()
	copy.apply_snapshot(data)
	_check(copy.seat_count == 6 and copy.order == [0, 1, 2, 3, 5] and copy.lives[4] == 0, "snapshots carry seats, order and lives")
	_check(copy.ball_pos.is_equal_approx(sim.ball_pos) and is_equal_approx(copy.paddle_pos[2], 100.0), "snapshots carry ball and paddles")


func _test_server_copy_matches() -> void:
	var client_copy := FileAccess.get_file_as_string("res://scripts/arena_simulation.gd")
	var server_copy := FileAccess.get_file_as_string("res://server/arena_simulation.gd")
	_check(not client_copy.is_empty() and client_copy == server_copy, "client and server share an identical arena simulation")


func _test_scene_flow() -> void:
	get_root().get_node("Sound").muted = true
	var scene: Node = load("res://scenes/arena.tscn").instantiate()
	get_root().add_child(scene)
	await process_frame
	var menu = scene.menu
	var court = scene.court
	_check(scene.phase == scene.Phase.TITLE and menu.options == ["solo", "online"], "the game opens on PLAY VS AI and PLAY ONLINE")
	_check(menu.title.text == "PADDLE POLYGON" and ProjectSettings.get_setting("application/config/name") == "Paddle Polygon", "the game is called Paddle Polygon")
	scene._on_menu_choice("solo", 1)
	scene.solo_players = 9
	scene._on_menu_choice("players", 1)
	_check(scene.solo_players == 10 and menu.button_labels[0].text.contains("10"), "the solo setup picks up to ten players")
	scene._on_menu_choice("players", 1)
	_check(scene.solo_players == 2, "the player count wraps from ten back to two")
	scene.solo_players = 10
	scene._on_menu_choice("go", 1)
	_check(scene.phase == scene.Phase.PLAYING and scene.sim.seat_count == 10 and scene.sim.cpu.count(true) == 9, "you play against nine AI on a decagon")
	for _i in 150:
		scene._physics_process(1.0 / 60.0)
	var visible_paddles := 0
	for paddle in court.paddles:
		visible_paddles += 1 if paddle.visible else 0
	_check(visible_paddles == scene.sim.wall_count() and court.ball.visible, "every wall shows its paddle and the ball is drawn")
	var bottom: Vector2 = court.paddles[scene.sim.wall_of(0)].position
	_check(bottom.y > court.CENTER.y + 150.0 and absf(bottom.x - court.CENTER.x) < 140.0, "your own paddle is drawn at the bottom")
	var order_before: Array = scene.sim.order.duplicate()
	var corners_before: PackedVector2Array = court.corners_on_screen(order_before.size())
	scene.sim._lose_life(order_before[3])
	court.start_fold(scene.sim, order_before, corners_before)
	var paddles := func(seat: int) -> float: return scene.sim.paddle_pos[seat]
	scene.draw_frame(Vector2.ZERO, paddles, 1.0 / 60.0)
	_check(court.lines.corners.size() == order_before.size(), "the court starts folding from the old shape")
	for _i in 60:
		scene.draw_frame(Vector2.ZERO, paddles, 1.0 / 60.0)
	_check(court.lines.corners.size() == order_before.size() - 1, "a knockout folds the court into the next polygon")
	scene.show_title()
	scene.solo_players = 2
	scene.start_solo_match()
	scene.sim.state = ArenaSimulation.STATE_PLAY
	var end: float = scene.sim.line_end(0)
	scene.sim.ball_pos = Vector2(end + 40.0, 0.0)
	scene.sim.ball_vel = Vector2(-500.0, 0.0)
	scene.handle_key(KEY_SPACE)
	_check(scene.sim.ball_vel.x > 0.0, "Space swings in the line finale")
	scene.handle_key(KEY_ESCAPE)
	_check(scene.phase == scene.Phase.PAUSED, "Esc pauses a solo match")
	scene.free()
	scene_checks_finished = true

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
