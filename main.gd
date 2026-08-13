extends Node2D

@onready var ball = $ball
@onready var left_label = $leftScore
@onready var right_label = $rightScore
@onready var paddle_left = $paddleLeft
@onready var paddle_right = $paddleRight
@onready var divider = $Divider
@onready var rally_label = $rallyLabel

var playfield_size := Vector2.ZERO


func _ready() -> void:
	_update_playfield_size()
	GameState.score_changed.connect(_on_score_changed)
	GameState.serving_changed.connect(_on_serving_changed)
	GameState.game_over.connect(_on_game_over)
	ball.rally_changed.connect(_on_rally_changed)
	GameState.reset_game()
	get_tree().root.connect("size_changed", _update_playfield_size)
	rally_label.visible = false


func _physics_process(_delta: float) -> void:
	if GameState.is_game_over:
		return
	if GameState.serving:
		if GameState.mode_selected:
			_place_serve_ball()
		return
	if ball.position.x + Constants.BALL_RADIUS < 0.0:
		GameState.add_point("right")
		ScreenShake.shake(lerpf(8.0, 16.0, ball.speed_ratio()))
		ParticleEffects.spawn_score(Vector2(playfield_size.x * 0.5, playfield_size.y * 0.5))
	elif ball.position.x - Constants.BALL_RADIUS > playfield_size.x:
		GameState.add_point("left")
		ScreenShake.shake(lerpf(8.0, 16.0, ball.speed_ratio()))
		ParticleEffects.spawn_score(Vector2(playfield_size.x * 0.5, playfield_size.y * 0.5))


func _place_serve_ball() -> void:
	var server = paddle_left if GameState.serve_toward_right else paddle_right
	var dir := 1.0 if GameState.serve_toward_right else -1.0
	var half_w := Constants.PADDLE_WIDTH * 0.5
	ball.velocity = Vector2.ZERO
	ball.position.x = server.position.x + dir * (half_w + Constants.BALL_RADIUS + 6.0)
	ball.position.y = server.position.y
	if GameState.serve_toward_right:
		ball.reset_color()
	else:
		ball._color_side = "right"
		ball.ball_color = GameState.get_p2_color()


func _serve_aim() -> float:
	var server = paddle_left if GameState.serve_toward_right else paddle_right
	var center_offset: float = (server.position.y - playfield_size.y * 0.5) / maxf(server.half_height(), 1.0)
	return clampf(server.get_move_input() * 0.85 + center_offset * 0.4, -1.0, 1.0)


func _update_playfield_size() -> void:
	playfield_size = get_viewport_rect().size
	ball._playfield_size = playfield_size
	var half_w := Constants.PADDLE_WIDTH * 0.5
	paddle_left.position.x = Constants.PADDLE_MARGIN + half_w
	paddle_right.position.x = playfield_size.x - Constants.PADDLE_MARGIN - half_w
	paddle_left.set_playfield_height(playfield_size.y)
	paddle_right.set_playfield_height(playfield_size.y)
	if divider:
		divider.points = PackedVector2Array([
			Vector2(playfield_size.x * 0.5, 16.0),
			Vector2(playfield_size.x * 0.5, playfield_size.y - 16.0),
		])
	if $AI:
		$AI.center_y = playfield_size.y * 0.5


func _on_score_changed(left_score: int, right_score: int) -> void:
	left_label.text = str(left_score)
	right_label.text = str(right_score)
	if not (left_score == 0 and right_score == 0):
		SFX.play("score")


func _on_serving_changed(serving: bool) -> void:
	if serving:
		ball.velocity = Vector2.ZERO
		ball.rally_hits = 0
		ball.reset_color()
		paddle_left.reset_size()
		paddle_right.reset_size()
		paddle_left.position.y = playfield_size.y * 0.5
		paddle_right.position.y = playfield_size.y * 0.5
		_on_rally_changed(0)
	else:
		ball.launch(GameState.serve_toward_right, _serve_aim())


func _on_rally_changed(hits: int) -> void:
	rally_label.text = "RALLY %d" % hits
	rally_label.visible = hits >= 2
	paddle_left.apply_rally_size(hits)
	paddle_right.apply_rally_size(hits)


func _on_game_over(_winner: String) -> void:
	GameState.update_longest_rally(ball.rally_hits)
	rally_label.visible = false
