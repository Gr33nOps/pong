extends Area2D
# Classic Pong ball. Collides only with the inner face of each paddle.

signal rally_changed(hits: int)

var velocity := Vector2.ZERO
var ball_color := Constants.COLOR_P1
var _color_side := "left"
var rally_hits := 0

var _playfield_size := Vector2.ZERO
var _last_paddle := ""


func _ready() -> void:
	monitoring = false
	monitorable = false
	_playfield_size = get_viewport_rect().size
	GameState.colorblind_changed.connect(_on_colorblind_changed)


func launch(toward_right: bool, aim: float) -> void:
	rally_hits = 0
	rally_changed.emit(0)
	_last_paddle = "left" if toward_right else "right"
	var angle := clampf(aim, -1.0, 1.0) * deg_to_rad(Constants.SERVE_ANGLE_DEG)
	var dir := 1.0 if toward_right else -1.0
	velocity = Vector2(cos(angle) * dir, sin(angle)) * Constants.START_SPEED
	_color_side = _last_paddle
	ball_color = GameState.get_p1_color() if toward_right else GameState.get_p2_color()


func reset_color() -> void:
	_color_side = "left"
	ball_color = GameState.get_p1_color()


func speed_ratio() -> float:
	return clampf(
		(velocity.length() - Constants.START_SPEED) / (Constants.MAX_SPEED - Constants.START_SPEED),
		0.0,
		1.0
	)


func _physics_process(delta: float) -> void:
	if velocity == Vector2.ZERO:
		return
	var travel := velocity.length() * delta
	var steps := clampi(ceili(travel / 8.0), 1, 16)
	var dt := delta / float(steps)
	for i in steps:
		var previous := position
		position += velocity * dt
		_bounce_walls()
		if _try_paddle_hit(previous):
			break


func _bounce_walls() -> void:
	var min_y := Constants.BALL_RADIUS
	var max_y := _playfield_size.y - Constants.BALL_RADIUS
	if position.y < min_y:
		position.y = min_y
		if velocity.y < 0.0:
			velocity.y = -velocity.y
			SFX.play("wall", 0.9 + speed_ratio() * 0.35)
			ParticleEffects.spawn_wall_bounce(global_position)
	elif position.y > max_y:
		position.y = max_y
		if velocity.y > 0.0:
			velocity.y = -velocity.y
			SFX.play("wall", 0.9 + speed_ratio() * 0.35)
			ParticleEffects.spawn_wall_bounce(global_position)


func _try_paddle_hit(previous: Vector2) -> bool:
	for node in get_tree().get_nodes_in_group("paddles"):
		var paddle := node as Area2D
		if paddle == null:
			continue
		if _hit_front_face(previous, paddle):
			return true
	return false


func _hit_front_face(previous: Vector2, paddle: Area2D) -> bool:
	var is_left: bool = bool(paddle.get("is_left"))
	var side := "left" if is_left else "right"
	if _last_paddle == side:
		return false

	var half_w := Constants.PADDLE_WIDTH * 0.5
	var half_h: float = paddle.half_height()
	var face_x: float = paddle.position.x + half_w if is_left else paddle.position.x - half_w
	var contact_x: float = face_x + Constants.BALL_RADIUS if is_left else face_x - Constants.BALL_RADIUS

	var crossed := false
	if is_left:
		crossed = previous.x > contact_x and position.x <= contact_x and velocity.x < 0.0
	else:
		crossed = previous.x < contact_x and position.x >= contact_x and velocity.x > 0.0
	if not crossed:
		return false

	var span := previous.x - position.x
	var t := 1.0
	if absf(span) > 0.0001:
		t = (previous.x - contact_x) / span
	t = clampf(t, 0.0, 1.0)
	var contact_y: float = previous.y + (position.y - previous.y) * t
	if absf(contact_y - paddle.position.y) > half_h + Constants.BALL_RADIUS * 0.15:
		return false

	_reflect(paddle, is_left, contact_x, contact_y, half_h)
	return true


func _reflect(paddle: Area2D, is_left: bool, contact_x: float, contact_y: float, half_h: float) -> void:
	var hit := clampf((contact_y - paddle.position.y) / half_h, -1.0, 1.0)
	var edge := absf(hit)
	var angle := hit * deg_to_rad(Constants.MAX_BOUNCE_ANGLE_DEG)
	var dir := 1.0 if is_left else -1.0
	var base := velocity.length() * Constants.SPEED_INCREMENT
	base *= 1.0 + float(rally_hits) * Constants.RALLY_SPEED_STEP
	base *= lerpf(1.08, 0.95, edge)
	var speed := minf(base, Constants.MAX_SPEED)
	var paddle_vy: float = float(paddle.get("last_vy"))
	var vy := sin(angle) * speed + paddle_vy * Constants.ENGLISH
	var vx := dir * maxf(absf(cos(angle) * speed), speed * Constants.MIN_HORIZONTAL)
	velocity = Vector2(vx, vy).limit_length(Constants.MAX_SPEED)

	position.x = contact_x + dir * 1.0
	position.y = clampf(contact_y, Constants.BALL_RADIUS, _playfield_size.y - Constants.BALL_RADIUS)

	_last_paddle = "left" if is_left else "right"
	_color_side = _last_paddle
	ball_color = GameState.get_p1_color() if is_left else GameState.get_p2_color()
	rally_hits += 1
	rally_changed.emit(rally_hits)

	var ratio := speed_ratio()
	SFX.play("paddle", 0.95 + ratio * 0.85)
	ScreenShake.shake(lerpf(4.0, 18.0, ratio))
	ParticleEffects.spawn_paddle_hit(global_position, ball_color)


func _on_colorblind_changed(_enabled: bool) -> void:
	ball_color = GameState.get_p1_color() if _color_side == "left" else GameState.get_p2_color()
