extends Node
# Central game state. Single source of truth for score, serve, pause,
# game over and mode. Owns the tree-wide pause via _process so no other
# node has to poke get_tree().paused directly.

signal score_changed(left_score: int, right_score: int)
signal serving_changed(serving: bool)
signal paused_changed(paused: bool)
signal game_over(winner: String)
signal mode_changed(mode: int)
signal colorblind_changed(enabled: bool)
signal ai_difficulty_changed(difficulty: float)
signal point_scored(side: String)
signal rematch_started
signal back_pressed

var left_score := 0
var right_score := 0
var is_game_over := false
var serving := true
var paused := false
var mode := Constants.MODE_AI
var mode_selected := false
var colorblind_mode := false
var longest_rally := 0
var last_rally := 0
var ai_difficulty := Constants.DIFFICULTY_NORMAL
var serve_toward_right := true
var between_points := false
var player_is_left := true
var online_player_side := "left"
var _last_input_modality := "keyboard"
var _online_last_point := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_settings()


func _sync_tree_pause() -> void:
	get_tree().paused = paused or is_game_over


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		if mode_selected and not is_game_over and not paused:
			toggle_pause()
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST:
		handle_back()


func is_touch_ui() -> bool:
	return OS.has_feature("mobile") or _last_input_modality == "touch"


func is_controller_ui() -> bool:
	return _last_input_modality == "controller" or not Input.get_connected_joypads().is_empty()


func note_input(modality: String) -> void:
	_last_input_modality = modality


func server_is_left() -> bool:
	return serve_toward_right


func handle_back() -> void:
	if is_game_over or not mode_selected:
		back_pressed.emit()
		return
	toggle_pause()


func _load_settings() -> void:
	var config := Constants.read_config()
	colorblind_mode = config.get_value("game", Constants.KEY_COLORBLIND_MODE, false)
	longest_rally = config.get_value("game", Constants.KEY_HIGH_SCORE, 0)
	player_is_left = config.get_value("game", Constants.KEY_PLAYER_IS_LEFT, true)
	ai_difficulty = _read_difficulty(config)
	colorblind_changed.emit(colorblind_mode)
	ai_difficulty_changed.emit(ai_difficulty)


func _read_difficulty(config: ConfigFile) -> float:
	var named := str(config.get_value("game", Constants.KEY_AI_DIFFICULTY_NAME, ""))
	match named:
		"easy":
			return Constants.DIFFICULTY_EASY
		"normal":
			return Constants.DIFFICULTY_NORMAL
		"hard":
			return Constants.DIFFICULTY_HARD
	var value := float(config.get_value("game", Constants.KEY_AI_DIFFICULTY, Constants.DIFFICULTY_NORMAL))
	if value <= 0.8:
		return Constants.DIFFICULTY_EASY
	if value >= 0.97:
		return Constants.DIFFICULTY_HARD
	return Constants.DIFFICULTY_NORMAL


func _save_settings() -> void:
	var config := Constants.read_config()
	config.set_value("game", Constants.KEY_COLORBLIND_MODE, colorblind_mode)
	config.set_value("game", Constants.KEY_HIGH_SCORE, longest_rally)
	config.set_value("game", Constants.KEY_AI_DIFFICULTY, ai_difficulty)
	config.set_value("game", Constants.KEY_AI_DIFFICULTY_NAME, difficulty_label().to_lower())
	config.set_value("game", Constants.KEY_PLAYER_IS_LEFT, player_is_left)
	Constants.write_config(config)


func reset_game() -> void:
	left_score = 0
	right_score = 0
	is_game_over = false
	serving = true
	paused = false
	mode = Constants.MODE_AI
	mode_selected = false
	between_points = false
	last_rally = 0
	serve_toward_right = true
	score_changed.emit(left_score, right_score)
	serving_changed.emit(serving)
	paused_changed.emit(paused)
	_sync_tree_pause()


func add_point(side: String) -> void:
	if is_game_over or between_points:
		return
	if side == "left":
		left_score += 1
		serve_toward_right = false
	else:
		right_score += 1
		serve_toward_right = true
	score_changed.emit(left_score, right_score)
	if left_score >= Constants.WINNER_SCORE or right_score >= Constants.WINNER_SCORE:
		is_game_over = true
		var winner := "blue" if left_score >= Constants.WINNER_SCORE else "red"
		_sync_tree_pause()
		game_over.emit(winner)
		return
	between_points = true
	point_scored.emit(side)


func update_longest_rally(rally: int) -> void:
	last_rally = rally
	if rally > longest_rally:
		longest_rally = rally
		_save_settings()


func set_serving(value: bool) -> void:
	if serving == value:
		return
	serving = value
	if serving:
		between_points = false
	serving_changed.emit(serving)


func toggle_pause() -> void:
	if is_game_over:
		return
	paused = not paused
	_sync_tree_pause()
	paused_changed.emit(paused)


func select_mode(value: int) -> void:
	if mode_selected:
		return
	mode = value


func select_side(is_left: bool) -> void:
	if mode_selected:
		return
	player_is_left = is_left
	mode_selected = true
	serve_toward_right = randf() >= 0.5
	_save_settings()
	mode_changed.emit(mode)
	serving_changed.emit(serving)


func begin_online_match(side: String) -> void:
	mode = Constants.MODE_ONLINE
	online_player_side = "right" if side == "right" else "left"
	player_is_left = online_player_side == "left"
	mode_selected = true
	left_score = 0
	right_score = 0
	is_game_over = false
	paused = false
	serving = true
	between_points = false
	serve_toward_right = true
	_online_last_point = ""
	score_changed.emit(left_score, right_score)
	mode_changed.emit(mode)
	paused_changed.emit(paused)
	_sync_tree_pause()
	serving_changed.emit(serving)


func apply_online_snapshot(snapshot: Dictionary) -> void:
	if mode != Constants.MODE_ONLINE:
		return
	var scores = snapshot.get("scores", {})
	var next_left := int(scores.get("left", left_score)) if scores is Dictionary else left_score
	var next_right := int(scores.get("right", right_score)) if scores is Dictionary else right_score
	var score_changed_now := next_left != left_score or next_right != right_score
	left_score = next_left
	right_score = next_right
	serve_toward_right = bool(snapshot.get("serve_toward_right", serve_toward_right))
	var next_serving := bool(snapshot.get("serving", serving))
	between_points = bool(snapshot.get("between_points", between_points))
	var point := str(snapshot.get("last_point", ""))
	if score_changed_now:
		score_changed.emit(left_score, right_score)
	if point.is_empty():
		_online_last_point = ""
	elif point != _online_last_point:
		_online_last_point = point
		point_scored.emit(point)
	if serving != next_serving:
		serving = next_serving
		serving_changed.emit(serving)
	var next_game_over := bool(snapshot.get("game_over", false))
	if next_game_over and not is_game_over:
		is_game_over = true
		_sync_tree_pause()
		game_over.emit("blue" if left_score >= Constants.WINNER_SCORE else "red")
	elif not next_game_over and is_game_over:
		is_game_over = false
		_sync_tree_pause()


func online_rematch_started() -> void:
	if mode != Constants.MODE_ONLINE:
		return
	left_score = 0
	right_score = 0
	is_game_over = false
	paused = false
	serving = true
	between_points = false
	serve_toward_right = true
	_online_last_point = ""
	score_changed.emit(left_score, right_score)
	paused_changed.emit(paused)
	_sync_tree_pause()
	rematch_started.emit()
	serving_changed.emit(serving)


func is_cpu_serving() -> bool:
	if mode != Constants.MODE_AI:
		return false
	return serve_toward_right != player_is_left


func is_p1_serving() -> bool:
	return serve_toward_right == player_is_left


func rematch() -> void:
	if mode == Constants.MODE_ONLINE:
		NetworkManager.request_rematch()
		return
	left_score = 0
	right_score = 0
	is_game_over = false
	paused = false
	between_points = false
	last_rally = 0
	serving = true
	serve_toward_right = randf() >= 0.5
	score_changed.emit(left_score, right_score)
	paused_changed.emit(paused)
	_sync_tree_pause()
	rematch_started.emit()
	serving_changed.emit(serving)


func cycle_difficulty(direction: int) -> void:
	var steps := [Constants.DIFFICULTY_EASY, Constants.DIFFICULTY_NORMAL, Constants.DIFFICULTY_HARD]
	var index := 1
	if ai_difficulty <= 0.8:
		index = 0
	elif ai_difficulty >= 0.97:
		index = 2
	index = clampi(index + direction, 0, steps.size() - 1)
	set_ai_difficulty(steps[index])


func advance_difficulty() -> void:
	var steps := [Constants.DIFFICULTY_EASY, Constants.DIFFICULTY_NORMAL, Constants.DIFFICULTY_HARD]
	var index := 1
	if ai_difficulty <= 0.8:
		index = 0
	elif ai_difficulty >= 0.97:
		index = 2
	set_ai_difficulty(steps[(index + 1) % steps.size()])


func toggle_colorblind() -> void:
	colorblind_mode = not colorblind_mode
	colorblind_changed.emit(colorblind_mode)
	_save_settings()


func set_ai_difficulty(value: float) -> void:
	ai_difficulty = clampf(value, Constants.DIFFICULTY_EASY, Constants.DIFFICULTY_HARD)
	ai_difficulty_changed.emit(ai_difficulty)
	_save_settings()


func get_p1_color() -> Color:
	return Constants.COLOR_P1_ALT if colorblind_mode else Constants.COLOR_P1


func get_p2_color() -> Color:
	return Constants.COLOR_P2_ALT if colorblind_mode else Constants.COLOR_P2


func difficulty_label() -> String:
	if ai_difficulty <= 0.8:
		return "Easy"
	if ai_difficulty >= 0.97:
		return "Hard"
	return "Normal"
