extends Node
# Predicts the bounce point when the ball is coming this way.

@export var left_paddle_path: NodePath
@export var right_paddle_path: NodePath
@export var ball_path: NodePath

@onready var paddle_left = get_node(left_paddle_path)
@onready var paddle_right = get_node(right_paddle_path)
@onready var ball = get_node(ball_path)

var speed := Constants.PADDLE_SPEED
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


func _cpu_paddle():
	return paddle_left if not GameState.player_is_left else paddle_right


func _cpu_is_left() -> bool:
	return not GameState.player_is_left


func _on_difficulty_changed(value: float) -> void:
	difficulty = value
	speed = minf(Constants.PADDLE_SPEED * difficulty, Constants.PADDLE_SPEED)


func _on_serving_changed(serving: bool) -> void:
	if serving and GameState.is_cpu_serving():
		var paddle = _cpu_paddle()
		_serve_target = randf_range(paddle.top_limit, paddle.bottom_limit)


func _physics_process(delta: float) -> void:
	if GameState.mode != Constants.MODE_AI:
		return
	if GameState.is_game_over or GameState.between_points:
		return
	var paddle = _cpu_paddle()
	if GameState.serving:
		if GameState.is_cpu_serving() and GameState.mode_selected:
			_move_toward(paddle, _serve_target, delta)
		else:
			_move_toward(paddle, center_y, delta)
		return
	_move_toward(paddle, _aim_y(paddle), delta)


func _move_toward(paddle, target_y: float, delta: float) -> void:
	var paddle_y: float = paddle.position.y
	var move := clampf(target_y - paddle_y, -speed * delta, speed * delta)
	var top: float = paddle.top_limit
	var bottom: float = paddle.bottom_limit
	paddle.position.y = clampf(paddle_y + move, top, bottom)
	paddle.last_vy = move / delta if delta > 0.0 else 0.0


func _aim_error() -> float:
	if difficulty <= 0.8:
		return 85.0
	if difficulty >= 0.97:
		return 12.0
	return 38.0


func _aim_y(paddle) -> float:
	var vel: Vector2 = ball.velocity
	var cpu_left := _cpu_is_left()
	var incoming: bool = vel.x < 0.0 if cpu_left else vel.x > 0.0
	if not incoming:
		_incoming = false
		return center_y
	if not _incoming:
		_incoming = true
		var error := _aim_error()
		_aim_offset = randf_range(-error, error)
	var face_x: float = paddle.position.x + Constants.PADDLE_WIDTH * 0.5 if cpu_left else paddle.position.x - Constants.PADDLE_WIDTH * 0.5
	var past_face: bool = ball.position.x <= face_x if cpu_left else ball.position.x >= face_x
	if past_face:
		return ball.position.y
	var time: float = (face_x - ball.position.x) / vel.x
	if time < 0.0:
		return center_y
	var height: float = get_viewport().get_visible_rect().size.y
	var min_y := Constants.HUD_HEIGHT + Constants.BALL_RADIUS
	var max_y := height - 10.0 - Constants.BALL_RADIUS
	var play_h := maxf(max_y - min_y, 1.0)
	var predicted: float = (ball.position.y - min_y) + vel.y * time
	var period := play_h * 2.0
	predicted = fposmod(predicted, period)
	if predicted > play_h:
		predicted = period - predicted
	return clampf(min_y + predicted + _aim_offset, min_y, max_y)
