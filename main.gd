extends Node2D

const BALL_RADIUS := 21.0

@onready var ball = $ball
@onready var left_label = $leftScore
@onready var right_label = $rightScore
@onready var paddle_left = $paddleLeft
@onready var paddle_right = $paddleRight

var playfield_size := Vector2.ZERO


func _ready() -> void:
	playfield_size = get_viewport_rect().size
	GameState.score_changed.connect(_on_score_changed)
	GameState.serving_changed.connect(_on_serving_changed)
	GameState.reset_game()


func _physics_process(_delta: float) -> void:
	if GameState.serving or GameState.is_game_over:
		return
	if ball.position.x + BALL_RADIUS < 0.0:
		GameState.add_point("right")
	elif ball.position.x - BALL_RADIUS > playfield_size.x:
		GameState.add_point("left")


func _on_score_changed(left_score: int, right_score: int) -> void:
	left_label.text = str(left_score)
	right_label.text = str(right_score)
	if not (left_score == 0 and right_score == 0):
		SFX.play("score")


func _on_serving_changed(serving: bool) -> void:
	if serving:
		ball.position = playfield_size * 0.5
		ball.velocity = Vector2.ZERO
		ball.reset_color()
		paddle_left.position.y = playfield_size.y * 0.5
		paddle_right.position.y = playfield_size.y * 0.5
	else:
		ball.launch()
