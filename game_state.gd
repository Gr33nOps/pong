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

var left_score := 0
var right_score := 0
var is_game_over := false
var serving := true
var paused := false
var mode := Constants.MODE_AI
var mode_selected := false
var colorblind_mode := false
var longest_rally := 0
var ai_difficulty := Constants.DIFFICULTY_NORMAL
var serve_toward_right := true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_settings()


func _process(_delta: float) -> void:
	get_tree().paused = paused or is_game_over


func _load_settings() -> void:
	var config := Constants.read_config()
	colorblind_mode = config.get_value("game", Constants.KEY_COLORBLIND_MODE, false)
	longest_rally = config.get_value("game", Constants.KEY_HIGH_SCORE, 0)
	ai_difficulty = config.get_value("game", Constants.KEY_AI_DIFFICULTY, Constants.DIFFICULTY_NORMAL)
	colorblind_changed.emit(colorblind_mode)
	ai_difficulty_changed.emit(ai_difficulty)


func _save_settings() -> void:
	var config := Constants.read_config()
	config.set_value("game", Constants.KEY_COLORBLIND_MODE, colorblind_mode)
	config.set_value("game", Constants.KEY_HIGH_SCORE, longest_rally)
	config.set_value("game", Constants.KEY_AI_DIFFICULTY, ai_difficulty)
	Constants.write_config(config)


func reset_game() -> void:
	left_score = 0
	right_score = 0
	is_game_over = false
	serving = true
	paused = false
	mode = Constants.MODE_AI
	mode_selected = false
	serve_toward_right = true
	score_changed.emit(left_score, right_score)
	serving_changed.emit(serving)
	paused_changed.emit(paused)


func add_point(side: String) -> void:
	if is_game_over:
		return
	if side == "left":
		left_score += 1
		serve_toward_right = false
	else:
		right_score += 1
		serve_toward_right = true
	score_changed.emit(left_score, right_score)
	serving = true
	serving_changed.emit(serving)
	if left_score >= Constants.WINNER_SCORE or right_score >= Constants.WINNER_SCORE:
		is_game_over = true
		var winner := "blue" if left_score >= Constants.WINNER_SCORE else "red"
		game_over.emit(winner)


func update_longest_rally(rally: int) -> void:
	if rally > longest_rally:
		longest_rally = rally
		_save_settings()


func set_serving(value: bool) -> void:
	if serving != value:
		serving = value
		serving_changed.emit(serving)


func toggle_pause() -> void:
	paused = not paused
	paused_changed.emit(paused)


func select_mode(value: int) -> void:
	if mode_selected:
		return
	mode = value
	mode_selected = true
	mode_changed.emit(mode)


func toggle_colorblind() -> void:
	colorblind_mode = not colorblind_mode
	colorblind_changed.emit(colorblind_mode)
	_save_settings()


func set_ai_difficulty(value: float) -> void:
	ai_difficulty = value
	ai_difficulty_changed.emit(ai_difficulty)
	_save_settings()


func get_p1_color() -> Color:
	return Constants.COLOR_P1_ALT if colorblind_mode else Constants.COLOR_P1


func get_p2_color() -> Color:
	return Constants.COLOR_P2_ALT if colorblind_mode else Constants.COLOR_P2


func difficulty_label() -> String:
	if ai_difficulty <= 0.75:
		return "Easy"
	if ai_difficulty >= 1.25:
		return "Hard"
	return "Normal"
