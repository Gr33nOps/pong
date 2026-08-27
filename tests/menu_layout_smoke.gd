extends SceneTree

const InkGeometry = preload("res://ink_geometry.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var packed: PackedScene = load("res://main.tscn")
	var scene: Node = packed.instantiate()
	root.add_child(scene)
	await process_frame
	var game_state: Node = get_root().get_node("GameState")
	var network_manager: Node = get_root().get_node("NetworkManager")
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
	_check(pause_card.get_node("Bg").get_script().resource_path == "res://ink_panel.gd" and game_over_card.get_node("Bg").get_script().resource_path == "res://ink_panel.gd", "modal cards share the hand-drawn panel component")
	var ink_outline := InkGeometry.rough_rect(Vector2(520.0, 520.0), 4.0, 3.4)
	_check(ink_outline.size() > 8 and ink_outline[0].y != ink_outline[1].y and ink_outline[4].x != ink_outline[5].x, "shared ink outlines vary along horizontal and vertical edges")
	serve._open_online_lobby()
	var input_style := serve.online_input.get_theme_stylebox("normal") as StyleBoxFlat
	_check(serve.online_card is Control and not serve.online_card is Panel, "Online lobby has no background card")
	_check(input_style != null and input_style.border_width_left == 0 and input_style.border_width_top == 0 and input_style.border_width_right == 0 and input_style.border_width_bottom == 0, "room-code input has no outline")
	_check(serve.online_input.position.x == 80.0 and serve.online_input_frame.position.x == 80.0 and serve.online_input.size.x == 360.0, "room-code field and ink frame are centered")
	_check(serve.online_option_bgs[0].size == Vector2(480.0, 58.0) and serve.online_option_bgs[1].position.y - serve.online_option_bgs[0].position.y == 70.0, "Online rows match the shared width and gap")
	network_manager.room_code = "ABC234"
	serve._online_view = serve.OnlineView.WAITING
	serve._update_online_view()
	_check(serve._online_option_count() == 2 and serve.online_option_labels[0].text == "COPY CODE" and serve.online_option_labels[1].text == "LEAVE ROOM", "Online room exposes copy and leave actions")
	serve._copy_online_code()
	_check(serve.online_status.text == "ROOM CODE COPIED", "Online room code copy gives immediate feedback")
	game_state.begin_online_match("right")
	game_state.serve_toward_right = true
	serve._refresh()
	_check(serve.serve_title.text == "OPPONENT SERVES", "Online serve prompt identifies the opponent's turn")
	game_state.serve_toward_right = false
	serve._refresh()
	_check(serve.serve_title.text == "YOUR SERVE", "Online serve prompt identifies the local player's turn")
	serve.online_code.text = ""
	serve._on_online_opponent_changed(false)
	_check(serve.online_code.text == "ABC234" and serve.online_status.text.contains("WAITING FOR A NEW PLAYER"), "a disconnected opponent returns to a shareable room")
	var pause_overlay = scene.get_node("pause")
	pause_overlay._update_hints()
	_check(not "rematch" in pause_overlay._ids() and pause_overlay.menu_label.text == "LEAVE MATCH", "Online pause menu cannot request an invalid mid-match rematch")
	pause_overlay.visible = true
	pause_overlay.root.modulate.a = 1.0
	pause_overlay._on_game_over("blue")
	_check(not pause_overlay.visible and pause_overlay.root.modulate.a == 0.0, "Game-over modal replaces the pause modal")
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
