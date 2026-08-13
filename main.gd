extends Node2D

@onready var ball = $ball
@onready var left_label = $leftScore
@onready var right_label = $rightScore
@onready var paddle_left = $paddleLeft
@onready var paddle_right = $paddleRight
@onready var divider = $Divider
@onready var rally_label = $rallyLabel
@onready var trail = $Trail
@onready var playfield_clip = $PlayfieldClip
@onready var hud = $HUD
@onready var score_flash = $ScoreFlash
@onready var court_bg = $Court/Background
@onready var left_wash = $Court/LeftWash
@onready var right_wash = $Court/RightWash
@onready var top_rail = $Court/TopRail
@onready var bottom_rail = $Court/BottomRail

var playfield_size := Vector2.ZERO
var _rotate_hint: CanvasLayer = null


func _ready() -> void:
	ScreenShake.reset()
	_update_playfield_size()
	GameState.score_changed.connect(_on_score_changed)
	GameState.serving_changed.connect(_on_serving_changed)
	GameState.game_over.connect(_on_game_over)
	GameState.colorblind_changed.connect(_on_colorblind_changed)
	GameState.mode_changed.connect(_on_mode_changed)
	GameState.point_scored.connect(_on_point_scored)
	GameState.rematch_started.connect(_on_rematch_started)
	ball.rally_changed.connect(_on_rally_changed)
	hud.bind_ball(ball)
	GameState.reset_game()
	get_tree().root.connect("size_changed", _update_playfield_size)
	rally_label.visible = false
	left_label.visible = false
	right_label.visible = false
	score_flash.modulate.a = 0.0
	score_flash.visible = false
	_set_match_visible(false)
	if GameState.is_touch_ui():
		_make_rotate_hint()
		_update_rotate_hint()


func _make_rotate_hint() -> void:
	_rotate_hint = CanvasLayer.new()
	_rotate_hint.layer = 90
	_rotate_hint.process_mode = Node.PROCESS_MODE_ALWAYS
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.02, 0.022, 0.03, 0.97)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	var label := Label.new()
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.text = "↻\n\nROTATE YOUR DEVICE\nPONG plays in landscape"
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", Color.WHITE)
	root.add_child(dim)
	root.add_child(label)
	_rotate_hint.add_child(root)
	add_child(_rotate_hint)
	_rotate_hint.visible = false


func _update_rotate_hint() -> void:
	if _rotate_hint == null:
		return
	var size := get_viewport_rect().size
	_rotate_hint.visible = size.y > size.x


func _unhandled_input(event: InputEvent) -> void:
	if GameState.paused or GameState.is_game_over or not GameState.mode_selected:
		return
	var pos := Vector2.INF
	if event is InputEventScreenTouch:
		if event.pressed:
			pos = event.position
		else:
			return
	elif event is InputEventScreenDrag:
		pos = event.position
	elif event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		pos = event.position
	if pos != Vector2.INF:
		_steer_from_pointer(pos)


func _steer_from_pointer(pos: Vector2) -> void:
	if pos.y < Constants.HUD_HEIGHT:
		return
	if GameState.mode == Constants.MODE_AI:
		var paddle = paddle_left if GameState.player_is_left else paddle_right
		paddle.position.y = clampf(pos.y, paddle.top_limit, paddle.bottom_limit)
		return
	if pos.x < playfield_size.x * 0.5:
		paddle_left.position.y = clampf(pos.y, paddle_left.top_limit, paddle_left.bottom_limit)
	else:
		paddle_right.position.y = clampf(pos.y, paddle_right.top_limit, paddle_right.bottom_limit)


func _on_mode_changed(_mode: int) -> void:
	_set_match_visible(true)


func _on_rematch_started() -> void:
	ScreenShake.reset()
	paddle_left.reset_size()
	paddle_right.reset_size()
	trail.clear_points()
	_set_match_visible(true)
	hud.visible = true


func _set_match_visible(on: bool) -> void:
	left_label.visible = false
	right_label.visible = false
	divider.visible = on and not GameState.serving
	left_wash.visible = false
	right_wash.visible = false
	top_rail.visible = on
	bottom_rail.visible = on
	ball.visible = on
	paddle_left.visible = on
	paddle_right.visible = on
	trail.visible = on
	if not on:
		trail.clear_points()
		ball.velocity = Vector2.ZERO
		ball.position = playfield_size * 0.5


func _physics_process(_delta: float) -> void:
	if GameState.is_game_over or GameState.between_points:
		return
	if not GameState.mode_selected:
		ball.visible = false
		paddle_left.visible = false
		paddle_right.visible = false
		trail.visible = false
		trail.clear_points()
		return
	if GameState.serving:
		_place_serve_ball()
		return
	if ball.position.x + Constants.BALL_RADIUS < 0.0:
		_score_goal("right", Vector2(12.0, ball.position.y), GameState.get_p2_color())
	elif ball.position.x - Constants.BALL_RADIUS > playfield_size.x:
		_score_goal("left", Vector2(playfield_size.x - 12.0, ball.position.y), GameState.get_p1_color())


func _score_goal(side: String, impact: Vector2, color: Color) -> void:
	ball.velocity = Vector2.ZERO
	trail.clear_points()
	GameState.update_longest_rally(ball.rally_hits)
	ScreenShake.shake(lerpf(6.0, 12.0, ball.speed_ratio()))
	ParticleEffects.spawn_score(impact, color)
	GameState.add_point(side)


func _on_point_scored(_side: String) -> void:
	ball.visible = false
	trail.visible = false
	trail.clear_points()
	await get_tree().create_timer(Constants.SCORE_HOLD).timeout
	if not is_instance_valid(self) or GameState.is_game_over or not GameState.mode_selected:
		return
	GameState.set_serving(true)
	ball.visible = true
	trail.visible = true


func _place_serve_ball() -> void:
	var server = paddle_left if GameState.serve_toward_right else paddle_right
	var dir := 1.0 if GameState.serve_toward_right else -1.0
	var half_w := Constants.PADDLE_WIDTH * 0.5
	ball.velocity = Vector2.ZERO
	ball.visible = true
	ball.position.x = server.position.x + dir * (half_w + Constants.BALL_RADIUS + 6.0)
	ball.position.y = server.position.y
	if GameState.serve_toward_right:
		ball.reset_color()
	else:
		ball._color_side = "right"
		ball.ball_color = GameState.get_p2_color()


func _serve_aim() -> float:
	var server = paddle_left if GameState.serve_toward_right else paddle_right
	var mid := (playfield_size.y + Constants.HUD_HEIGHT) * 0.5
	var center_offset: float = (server.position.y - mid) / maxf(server.half_height(), 1.0)
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
			Vector2(playfield_size.x * 0.5, Constants.HUD_HEIGHT + 10.0),
			Vector2(playfield_size.x * 0.5, playfield_size.y - 14.0),
		])
	court_bg.size = playfield_size
	var wash_w := 72.0
	left_wash.position = Vector2(0.0, Constants.HUD_HEIGHT)
	left_wash.size = Vector2(wash_w, playfield_size.y - Constants.HUD_HEIGHT)
	right_wash.position = Vector2(playfield_size.x - wash_w, Constants.HUD_HEIGHT)
	right_wash.size = Vector2(wash_w, playfield_size.y - Constants.HUD_HEIGHT)
	top_rail.position = Vector2(20.0, Constants.HUD_HEIGHT)
	top_rail.size = Vector2(playfield_size.x - 40.0, 2.0)
	bottom_rail.position = Vector2(20.0, playfield_size.y - 8.0)
	bottom_rail.size = Vector2(playfield_size.x - 40.0, 2.0)
	score_flash.position = Vector2(0.0, Constants.HUD_HEIGHT)
	score_flash.size = Vector2(playfield_size.x, playfield_size.y - Constants.HUD_HEIGHT)
	playfield_clip.position = Vector2(0.0, Constants.HUD_HEIGHT)
	playfield_clip.size = Vector2(playfield_size.x, playfield_size.y - Constants.HUD_HEIGHT)
	if $AI:
		$AI.center_y = (playfield_size.y + Constants.HUD_HEIGHT) * 0.5
	_update_rotate_hint()


func _on_score_changed(left_score: int, right_score: int) -> void:
	if left_score == 0 and right_score == 0:
		return
	SFX.play_score()


func _on_colorblind_changed(_enabled: bool) -> void:
	left_wash.visible = false
	right_wash.visible = false


func _on_serving_changed(serving: bool) -> void:
	if serving:
		ball.velocity = Vector2.ZERO
		ball.rally_hits = 0
		paddle_left.reset_size()
		paddle_right.reset_size()
		_on_rally_changed(0)
		divider.visible = false
		ball.visible = GameState.mode_selected
	else:
		divider.visible = GameState.mode_selected
		ball.launch(GameState.serve_toward_right, _serve_aim())


func _on_rally_changed(hits: int) -> void:
	rally_label.visible = false
	paddle_left.apply_rally_size(hits)
	paddle_right.apply_rally_size(hits)


func _on_game_over(_winner: String) -> void:
	rally_label.visible = false
	ScreenShake.reset()
	trail.clear_points()
	ball.velocity = Vector2.ZERO
