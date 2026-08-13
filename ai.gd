extends Node
# Predicts the bounce point when the ball is coming this way.

@export var paddle_path: NodePath
@export var ball_path: NodePath

@onready var paddle = get_node(paddle_path)
@onready var ball = get_node(ball_path)

var speed := Constants.AI_BASE_SPEED
var center_y := 0.0
var difficulty := Constants.DIFFICULTY_NORMAL
var _incoming := false
var _aim_offset := 0.0
var _serve_target := 0.0


func _ready() -> void:
	center_y = get_viewport().get_visible_rect().size.y * 0.5
	_serve_target = center_y
	GameState.ai_difficulty_changed.connect(_on_difficulty_changed)
	GameState.serving_changed.connect(_on_serving_changed)
	_on_difficulty_changed(GameState.ai_difficulty)


func _on_difficulty_changed(value: float) -> void:
	difficulty = value
	speed = Constants.AI_BASE_SPEED * difficulty


func _on_serving_changed(serving: bool) -> void:
	if serving and _ai_is_server():
		_serve_target = randf_range(paddle.top_limit, paddle.bottom_limit)


func _ai_is_server() -> bool:
	return GameState.mode == Constants.MODE_AI and not GameState.serve_toward_right


func _physics_process(delta: float) -> void:
	if GameState.mode != Constants.MODE_AI:
		return
	if GameState.is_game_over:
		return
	if GameState.serving:
		if _ai_is_server() and GameState.mode_selected:
			_move_toward(_serve_target, delta)
		else:
			_move_toward(center_y, delta)
		return
	_move_toward(_aim_y(), delta)


func _move_toward(target_y: float, delta: float) -> void:
	var paddle_y: float = paddle.position.y
	var move := clampf(target_y - paddle_y, -speed * delta, speed * delta)
	var top: float = paddle.top_limit
	var bottom: float = paddle.bottom_limit
	paddle.position.y = clampf(paddle_y + move, top, bottom)
	paddle.last_vy = move / delta if delta > 0.0 else 0.0


func _aim_y() -> float:
	var vel: Vector2 = ball.velocity
	if vel.x <= 0.0:
		_incoming = false
		return center_y
	if not _incoming:
		_incoming = true
		var error: float = (1.35 - difficulty) * 55.0
		_aim_offset = randf_range(-error, error)
	var face_x: float = paddle.position.x - Constants.PADDLE_WIDTH * 0.5
	if ball.position.x >= face_x:
		return ball.position.y
	var time: float = (face_x - ball.position.x) / vel.x
	if time < 0.0:
		return center_y
	var predicted: float = ball.position.y + vel.y * time
	var height: float = get_viewport().get_visible_rect().size.y
	var period: float = maxf(height * 2.0, 1.0)
	predicted = fposmod(predicted, period)
	if predicted > height:
		predicted = period - predicted
	return predicted + _aim_offset
