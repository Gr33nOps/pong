extends SceneTree

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var constants = get_root().get_node("Constants")
	var game_state = get_root().get_node("GameState")
	_check(constants.WINNER_SCORE == 5, "winner score remains first-to-five")
	_check(constants.PADDLE_SPEED > 0.0, "paddle speed is positive")

	game_state.reset_game()
	game_state.select_mode(constants.MODE_AI)
	game_state.select_side(true)
	_check(game_state.mode == constants.MODE_AI and game_state.mode_selected, "AI mode still starts")
	game_state.reset_game()
	game_state.select_mode(constants.MODE_2P)
	game_state.select_side(true)
	_check(game_state.mode_selected, "mode and side selection completes")
	_check(game_state.server_is_left() == game_state.serve_toward_right, "serve-side resolution matches serve direction")
	game_state.add_point("left")
	_check(game_state.left_score == 1 and not game_state.serve_toward_right, "left score updates and serve changes direction")
	game_state.between_points = false
	game_state.add_point("right")
	_check(game_state.right_score == 1 and game_state.serve_toward_right, "right score updates and serve changes direction")
	game_state.reset_game()
	game_state.select_mode(constants.MODE_2P)
	game_state.select_side(true)
	for _i in constants.WINNER_SCORE - 1:
		game_state.add_point("left")
		game_state.between_points = false
	_check(not game_state.is_game_over, "first-to-five remains unfinished before final point")
	game_state.add_point("left")
	_check(game_state.is_game_over and game_state.left_score == constants.WINNER_SCORE, "first-to-five ends on the final point")
	game_state.reset_game()
	var legacy_settings := ConfigFile.new()
	legacy_settings.set_value("game", constants.KEY_AI_DIFFICULTY, 0.55)
	_check(is_equal_approx(game_state._read_difficulty(legacy_settings), constants.DIFFICULTY_EASY), "legacy difficulty settings migrate to easy")
	legacy_settings.set_value("game", constants.KEY_AI_DIFFICULTY_NAME, "hard")
	_check(is_equal_approx(game_state._read_difficulty(legacy_settings), constants.DIFFICULTY_HARD), "named difficulty settings take precedence")
	var ai = load("res://ai.gd").new()
	ai.difficulty = constants.DIFFICULTY_EASY
	var easy_delay: float = ai._reaction_delay()
	var easy_error: float = ai._aim_error()
	ai.difficulty = constants.DIFFICULTY_HARD
	_check(ai._reaction_delay() < easy_delay and ai._aim_error() < easy_error, "hard AI reacts faster and predicts more accurately")
	ai.free()
	game_state.paused = false
	game_state.toggle_pause()
	_check(game_state.paused, "pause transition enters paused state")
	game_state.toggle_pause()
	_check(not game_state.paused, "pause transition resumes cleanly")

	var ball_script = load("res://ball.gd")
	var ball = ball_script.new()
	ball.launch(true, 1.0)
	_check(ball.velocity.x > 0.0 and is_equal_approx(ball.velocity.length(), constants.START_SPEED), "serve launches toward the requested side")
	_check(absf(ball.velocity.x) >= constants.START_SPEED * constants.MIN_HORIZONTAL, "serve keeps a playable horizontal component")
	ball.free()

	var paddle_script = load("res://paddle.gd")
	var paddle = paddle_script.new()
	paddle.is_left = true
	paddle.set_playfield_height(648.0)
	paddle.position.y = 324.0
	_check(paddle.begin_pointer(7, paddle.bottom_limit), "human paddle accepts its first pointer")
	_check(not paddle.begin_pointer(8, paddle.top_limit), "human paddle rejects competing pointer ownership")
	var before_y: float = paddle.position.y
	paddle._physics_process(1.0 / 60.0)
	_check(absf(paddle.position.y - before_y) <= constants.PADDLE_SPEED / 60.0 + 0.01, "pointer movement is speed limited")
	paddle.release_pointer(7)
	_check(not paddle.has_pointer_target(), "pointer release clears paddle ownership")
	paddle.free()

	# Exercise the real scene's swept collision path at an intentionally high speed.
	var sfx = get_root().get_node("SFX")
	var was_muted: bool = sfx.muted
	sfx.muted = true
	var main_scene = load("res://main.tscn").instantiate()
	get_root().add_child(main_scene)
	await process_frame
	game_state.mode = constants.MODE_2P
	game_state.mode_selected = true
	game_state.serving = false
	game_state.between_points = false
	var scene_ball = main_scene.get_node("ball")
	var scene_left = main_scene.get_node("paddleLeft")
	scene_left.position.y = 324.0
	scene_ball.position = Vector2(90.0, scene_left.position.y)
	scene_ball.velocity = Vector2(-2400.0, 0.0)
	scene_ball._last_paddle = "right"
	scene_ball.rally_hits = 0
	scene_ball._physics_process(1.0 / 60.0)
	_check(scene_ball.velocity.x > 0.0 and scene_ball.rally_hits == 1, "swept collision catches a high-speed paddle hit once")
	scene_ball._physics_process(1.0 / 60.0)
	_check(scene_ball.rally_hits == 1, "paddle hit cannot score twice on the next physics step")
	scene_ball.position = Vector2(576.0, Constants.HUD_HEIGHT + Constants.BALL_RADIUS + 1.0)
	scene_ball.velocity = Vector2(300.0, -900.0)
	scene_ball._physics_process(1.0 / 60.0)
	_check(scene_ball.velocity.y >= 0.0, "wall reflection keeps the ball inside the playfield")
	sfx.stop_all()
	sfx.muted = was_muted
	main_scene.free()

	if _failures.is_empty():
		print("PONG smoke tests passed")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
