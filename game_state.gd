extends Node
# Central game state. Single source of truth for score, serve, pause,
# game over and mode. Owns the tree-wide pause via _process so no other
# node has to poke get_tree().paused directly.

signal score_changed(left_score: int, right_score: int)
signal serving_changed(serving: bool)
signal paused_changed(paused: bool)
signal game_over(winner: String)
signal mode_changed(mode: int)

const WINNER_SCORE := 5
const MODE_AI := 1
const MODE_2P := 2

var left_score := 0
var right_score := 0
var is_game_over := false
var serving := true
var paused := false
var mode := MODE_AI
var mode_selected := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(_delta: float) -> void:
	get_tree().paused = paused or serving or is_game_over


func reset_game() -> void:
	left_score = 0
	right_score = 0
	is_game_over = false
	serving = true
	paused = false
	mode = MODE_AI
	mode_selected = false
	score_changed.emit(left_score, right_score)
	serving_changed.emit(serving)
	paused_changed.emit(paused)


func add_point(side: String) -> void:
	if is_game_over:
		return
	if side == "left":
		left_score += 1
	else:
		right_score += 1
	score_changed.emit(left_score, right_score)
	serving = true
	serving_changed.emit(serving)
	if left_score >= WINNER_SCORE or right_score >= WINNER_SCORE:
		is_game_over = true
		var winner := "blue" if left_score >= WINNER_SCORE else "red"
		game_over.emit(winner)


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
