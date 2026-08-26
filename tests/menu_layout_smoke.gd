extends SceneTree

var failures: Array[String] = []


func _initialize() -> void:
	var packed: PackedScene = load("res://main.tscn")
	var scene: Node = packed.instantiate()
	root.add_child(scene)
	await process_frame
	var game_state: Node = get_root().get_node("GameState")
	var serve = scene.get_node("serveOverlay")
	var pause_card: Control = scene.get_node("pause/Root/Card")
	var game_over_card: Control = scene.get_node("gameOver/Root/Card")
	serve._step = serve.Step.MODE
	game_state.reset_game()
	serve._refresh()
	_check(serve.option1_bg.position.x == 336.0 and serve.option2_bg.position.x == 336.0 and serve.option3_bg.position.x == 336.0, "main menu buttons share one column")
	_check(serve.option1_bg.size.x == 480.0 and serve.option2_bg.size.x == 480.0 and serve.option3_bg.size.x == 480.0, "main menu buttons share one width")
	_check(serve.option2_bg.position.y - serve.option1_bg.position.y == 78.0 and serve.option3_bg.position.y - serve.option2_bg.position.y == 78.0, "main menu rows use one gap")
	_check(pause_card.position == Vector2(316.0, 64.0) and pause_card.size == Vector2(520.0, 520.0), "pause card uses the shared frame")
	_check(game_over_card.position == Vector2(316.0, 64.0) and game_over_card.size == Vector2(520.0, 520.0), "game-over card uses the shared frame")
	serve._open_online_lobby()
	var input_style := serve.online_input.get_theme_stylebox("normal") as StyleBoxFlat
	_check(serve.online_card is Control and not serve.online_card is Panel, "Online lobby has no background card")
	_check(input_style != null and input_style.border_width_left == 0 and input_style.border_width_top == 0 and input_style.border_width_right == 0 and input_style.border_width_bottom == 0, "room-code input has no outline")
	_check(serve.online_option_bgs[0].size == Vector2(480.0, 58.0) and serve.online_option_bgs[1].position.y - serve.online_option_bgs[0].position.y == 70.0, "Online rows match the shared width and gap")
	serve._online_countdown_active = true
	game_state.begin_online_match("left")
	serve.online_status.text = "3"
	serve._refresh()
	_check(serve.online_overlay.visible and serve.online_title.text == "MATCH READY" and serve.online_status.text == "3", "Online countdown stays visible and keeps its countdown text")
	serve._cancel_online_countdown()
	game_state.cancel_online_match()
	serve._close_online_lobby()
	scene.free()
	if failures.is_empty():
		print("PONG menu layout smoke: passed")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
