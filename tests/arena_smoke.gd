extends SceneTree

const ArenaSimulation = preload("res://scripts/arena_simulation.gd")

var failures: Array[String] = []
var scene_checks_finished := false


func _initialize() -> void:
	_test_geometry()
	_test_paddle_return()
	_test_one_miss_knocks_out()
	_test_leaving_knocks_out()
	_test_line_finale_hits()
	_test_early_swing_locks()
	_test_late_swing_is_judged_in_the_past()
	_test_idle_matches_finish()
	_test_snapshot_round_trip()
	_test_server_copy_matches()
	_test_names_and_invites()
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
	sim.reset_match(players)
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


func _test_leaving_knocks_out() -> void:
	var sim := _sim(3)
	sim.knock_out(1)
	_check(sim.order == [0, 2] and sim.is_line() and not sim.is_alive(1), "a player who leaves is knocked out")
	sim.knock_out(0)
	_check(sim.state == ArenaSimulation.STATE_OVER and sim.winner == 2, "the last player left wins")


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
	for _i in 30:
		if sim.state != ArenaSimulation.STATE_PLAY:
			break
		sim._advance_line(1.0 / 120.0)
		sim.tick_number += 1
	# By now the ball has gone past the end on the server; the swing arrived late.
	_check(sim.ball_pos.x < end or not sim.is_alive(0), "the ball has passed the end on the server")
	var replay := _sim(2)
	replay.ball_pos = Vector2(end + 60.0, 0.0)
	replay.ball_vel = Vector2(-500.0, 0.0)
	var pressed_at := 0
	for i in 6:
		replay._advance_line(1.0 / 120.0)
		replay.tick_number += 1
		if i == 0:
			pressed_at = replay.tick_number
	_check(replay.press_hit(0, pressed_at) and replay.ball_vel.x > 0.0, "a swing is judged where the ball was when the player pressed")


## Players who never touch the controls still end up with one winner.
func _test_idle_matches_finish() -> void:
	var ok := true
	var saw_line := false
	for players in [2, 3, 5, 10]:
		var sim := ArenaSimulation.new()
		sim.rng.seed = 11 + players
		sim.reset_match(players)
		var ticks := 0
		while sim.state != ArenaSimulation.STATE_OVER and ticks < 120 * 60 * 10:
			sim.tick(1.0 / 120.0)
			saw_line = saw_line or sim.is_line()
			sim.events.clear()
			ticks += 1
		ok = ok and sim.state == ArenaSimulation.STATE_OVER and sim.winner >= 0 and sim.order.size() == 1
	_check(ok, "matches of 2, 3, 5 and 10 players end with one winner")
	_check(saw_line, "matches finish through the line finale")


func _test_snapshot_round_trip() -> void:
	var sim := _sim(6)
	sim.ball_pos = Vector2(12.0, -34.0)
	sim.ball_vel = Vector2(-210.0, 330.0)
	sim.order.erase(4)
	sim.paddle_pos[2] = 100.0
	var data = JSON.parse_string(JSON.stringify(sim.snapshot()))
	var copy := ArenaSimulation.new()
	copy.apply_snapshot(data)
	_check(copy.seat_count == 6 and copy.order == [0, 1, 2, 3, 5] and not copy.is_alive(4), "snapshots carry seats and who is still in")
	_check(copy.ball_pos.is_equal_approx(sim.ball_pos) and is_equal_approx(copy.paddle_pos[2], 100.0), "snapshots carry ball and paddles")


func _test_server_copy_matches() -> void:
	var client_copy := FileAccess.get_file_as_string("res://scripts/arena_simulation.gd")
	var server_copy := FileAccess.get_file_as_string("res://server/arena_simulation.gd")
	_check(not client_copy.is_empty() and client_copy == server_copy, "client and server share an identical arena simulation")


func _test_names_and_invites() -> void:
	var settings = get_root().get_node("Settings")
	_check(settings.clean_name("  al!i   b ") == "ALI B", "names keep letters, digits and single spaces, in capitals")
	_check(settings.clean_name("abcdefghijklmnop") == "ABCDEFGHIJKL", "names are at most twelve characters")
	_check(settings.invite_link("AB12CD") == settings.GAME_URL + "?room=AB12CD", "an invite link opens the game at the room")


func _test_scene_flow() -> void:
	get_root().get_node("Sound").muted = true
	# The menus try to connect; point them at a port where nothing answers.
	OS.set_environment("PONG_SERVER_URL", "ws://127.0.0.1:9")
	var settings = get_root().get_node("Settings")
	var network = get_root().get_node("Network")
	var saved_name: String = settings.player_name()
	settings.save_player_name("")
	var scene: Node = load("res://scenes/arena.tscn").instantiate()
	get_root().add_child(scene)
	await process_frame
	var menu = scene.menu
	var court = scene.court
	_check(scene.phase == scene.Phase.TITLE and menu.options == ["play"], "the game opens on a single PLAY button")
	_check(menu.title.text == "PADDLE POLYGON" and ProjectSettings.get_setting("application/config/name") == "Paddle Polygon", "the game is called Paddle Polygon")
	scene._on_menu_choice("play")
	_check(scene.phase == scene.Phase.PLAY and menu.options == ["create", "join", "back"] and menu.text_box.visible, "PLAY asks for your name, then create or join")
	scene._on_menu_choice("create")
	_check(menu.status.text == "TYPE YOUR NAME FIRST", "you need a name before making a room")
	menu.text_box.text = "zain"
	scene._on_menu_choice("join")
	_check(scene.phase == scene.Phase.JOIN and settings.player_name() == "ZAIN", "your name is saved and the join screen asks for a code")
	scene._go_back()
	scene._go_back()
	_check(scene.phase == scene.Phase.TITLE, "Esc steps back to the title")
	network.disconnect_from_server()

	# A seven-player match, fed by snapshots as if they came from the server.
	var names := ["ALI", "SARA", "ZAIN", "OMAR", "LINA", "SAM", "NOOR"]
	var server_sim := ArenaSimulation.new()
	server_sim.reset_match(names.size())
	network.seat = 0
	scene._on_match_started(names)
	scene._on_snapshot(server_sim.snapshot())
	for _i in 30:
		scene._physics_process(1.0 / 60.0)
	var visible_paddles := 0
	for paddle in court.paddles:
		visible_paddles += 1 if paddle.visible else 0
	_check(scene.phase == scene.Phase.PLAYING and visible_paddles == 7, "every player's wall shows a paddle")
	var bottom: Vector2 = court.paddles[0].position
	_check(bottom.y > court.CENTER.y + 150.0 and absf(bottom.x - court.CENTER.x) < 140.0, "your own paddle is drawn at the bottom")
	_check(court.name_labels[3].visible and court.name_labels[3].text == "OMAR", "players' names are shown by their walls")
	server_sim.knock_out(3)
	scene._on_snapshot(server_sim.snapshot())
	for _i in 60:
		scene._physics_process(1.0 / 60.0)
	_check(court.lines.corners.size() == 6, "a knockout folds the court into the next polygon")
	server_sim.knock_out(0)
	scene._on_snapshot(server_sim.snapshot())
	scene._physics_process(1.0 / 60.0)
	_check(court.hint_label.text.begins_with("YOU'RE OUT"), "a knocked-out player keeps watching")
	scene.handle_key(KEY_ESCAPE)
	_check(scene.phase == scene.Phase.PAUSED, "Esc opens the menu during a match")
	scene.handle_key(KEY_ESCAPE)
	for seat in [1, 2, 4, 5]:
		server_sim.knock_out(seat)
	scene._on_snapshot(server_sim.snapshot())
	_check(scene.phase == scene.Phase.OVER and menu.title.text == "NOOR WINS", "the game over screen names the winner")
	_check(menu.options == ["room", "leave"], "after a match you go back to the room or leave")
	network.seat = -1
	scene.free()
	settings.save_player_name(saved_name)
	scene_checks_finished = true


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
