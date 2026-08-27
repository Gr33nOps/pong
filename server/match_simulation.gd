class_name MatchSimulation
extends RefCounted

const COURT_WIDTH := 1152.0
const COURT_HEIGHT := 648.0
const HUD_HEIGHT := 72.0
const BALL_RADIUS := 21.0
const START_SPEED := 600.0
const MAX_SPEED := 1020.0
const BALL_COLLISION_STEP := 4.0
const MAX_BALL_SUBSTEPS := 64
const PADDLE_HEIGHT := 156.0
const PADDLE_HALF_HEIGHT := PADDLE_HEIGHT * 0.5
const PADDLE_WIDTH := 21.0
const PADDLE_MARGIN := 16.0
const PADDLE_SPEED := 580.0
const PADDLE_COLLISION_PAD := 2.0
const SPEED_INCREMENT := 1.042
const MAX_BOUNCE_ANGLE_DEG := 72.0
const SERVE_ANGLE_DEG := 28.0
const MIN_HORIZONTAL := 0.38
const ENGLISH := 0.4
const RALLY_SPEED_STEP := 0.006
const WINNER_SCORE := 5
const SCORE_HOLD := 0.4
const INPUT_TIMEOUT := 0.3

var left_score := 0
var right_score := 0
var left_y := 360.0
var right_y := 360.0
var left_previous_y := 360.0
var right_previous_y := 360.0
var left_last_vy := 0.0
var right_last_vy := 0.0
var ball_position := Vector2(576.0, 360.0)
var ball_velocity := Vector2.ZERO
var rally_hits := 0
var serve_toward_right := true
var serving := true
var between_points := false
var game_over := false
var last_point := ""
var tick_number := 0
var _left_axis := 0.0
var _right_axis := 0.0
var _left_target_y := -1.0
var _right_target_y := -1.0
var _serve_cooldown := 0.0
var _left_input_age := 0.0
var _right_input_age := 0.0


func reset_match() -> void:
	left_score = 0
	right_score = 0
	left_y = _court_center_y()
	right_y = _court_center_y()
	left_previous_y = left_y
	right_previous_y = right_y
	left_last_vy = 0.0
	right_last_vy = 0.0
	ball_velocity = Vector2.ZERO
	ball_position = Vector2(576.0, _court_center_y())
	rally_hits = 0
	serve_toward_right = true
	serving = true
	between_points = false
	game_over = false
	last_point = ""
	tick_number = 0
	_serve_cooldown = 0.0
	_left_axis = 0.0
	_right_axis = 0.0
	_left_target_y = -1.0
	_right_target_y = -1.0
	_left_input_age = 0.0
	_right_input_age = 0.0
	_place_ball_for_serve()


func set_input(side: String, axis: float, target_y: float) -> void:
	var clean_axis := clampf(axis, -1.0, 1.0)
	var clean_target := clampf(target_y, HUD_HEIGHT + PADDLE_HALF_HEIGHT, COURT_HEIGHT - 12.0 - PADDLE_HALF_HEIGHT) if target_y >= 0.0 else -1.0
	if side == "left":
		_left_axis = clean_axis
		_left_target_y = clean_target
		_left_input_age = 0.0
		return
	if side == "right":
		_right_axis = clean_axis
		_right_target_y = clean_target
		_right_input_age = 0.0


func serve(side: String, aim: float) -> bool:
	if game_over or not serving or between_points or _serve_cooldown > 0.0:
		return false
	var expected_side := "left" if serve_toward_right else "right"
	if side != expected_side:
		return false
	var clean_aim := clampf(aim, -1.0, 1.0)
	var angle := clampf(clean_aim, -1.0, 1.0) * deg_to_rad(SERVE_ANGLE_DEG)
	var direction := 1.0 if serve_toward_right else -1.0
	_place_ball_for_serve()
	ball_velocity = Vector2(cos(angle) * direction, sin(angle)) * START_SPEED
	serving = false
	between_points = false
	last_point = ""
	rally_hits = 0
	_serve_cooldown = 0.18
	return true


func tick(delta: float) -> void:
	tick_number += 1
	_serve_cooldown = maxf(_serve_cooldown - delta, 0.0)
	_expire_stale_input(delta)
	_update_paddle("left", delta)
	_update_paddle("right", delta)
	if between_points:
		if _serve_cooldown > 0.0:
			return
		between_points = false
		last_point = ""
	if serving:
		_place_ball_for_serve()
		return
	if game_over or ball_velocity == Vector2.ZERO:
		return
	var travel := ball_velocity.length() * delta
	var steps := clampi(ceili(travel / BALL_COLLISION_STEP), 1, MAX_BALL_SUBSTEPS)
	var step_delta := delta / float(steps)
	for _i in steps:
		var previous := ball_position
		ball_position += ball_velocity * step_delta
		_bounce_walls()
		if _try_paddle_hit(previous):
			break
	if ball_position.x + BALL_RADIUS < 0.0:
		_score("right")
	elif ball_position.x - BALL_RADIUS > COURT_WIDTH:
		_score("left")


func snapshot() -> Dictionary:
	return {
		"type": "snapshot",
		"tick": tick_number,
		"ball": {"x": ball_position.x, "y": ball_position.y, "vx": ball_velocity.x, "vy": ball_velocity.y},
		"paddles": {"left": left_y, "right": right_y},
		"scores": {"left": left_score, "right": right_score},
		"serving": serving,
		"serve_toward_right": serve_toward_right,
		"between_points": between_points,
		"game_over": game_over,
		"last_point": last_point,
		"rally_hits": rally_hits,
	}


func _update_paddle(side: String, delta: float) -> void:
	var current_y := left_y if side == "left" else right_y
	var previous_y := current_y
	var target_y := _left_target_y if side == "left" else _right_target_y
	var axis := _left_axis if side == "left" else _right_axis
	if target_y >= 0.0:
		current_y = move_toward(current_y, target_y, PADDLE_SPEED * delta)
	else:
		current_y += axis * PADDLE_SPEED * delta
	current_y = clampf(current_y, HUD_HEIGHT + PADDLE_HALF_HEIGHT, COURT_HEIGHT - 12.0 - PADDLE_HALF_HEIGHT)
	if side == "left":
		left_previous_y = previous_y
		left_y = current_y
		left_last_vy = (current_y - previous_y) / delta if delta > 0.0 else 0.0
	else:
		right_previous_y = previous_y
		right_y = current_y
		right_last_vy = (current_y - previous_y) / delta if delta > 0.0 else 0.0


func _bounce_walls() -> void:
	var min_y := HUD_HEIGHT + BALL_RADIUS
	var max_y := COURT_HEIGHT - 10.0 - BALL_RADIUS
	if ball_position.y < min_y:
		ball_position.y = min_y
		if ball_velocity.y < 0.0:
			ball_velocity.y = -ball_velocity.y
	elif ball_position.y > max_y:
		ball_position.y = max_y
		if ball_velocity.y > 0.0:
			ball_velocity.y = -ball_velocity.y


func _try_paddle_hit(previous: Vector2) -> bool:
	var left_x := PADDLE_MARGIN + PADDLE_WIDTH * 0.5
	var right_x := COURT_WIDTH - PADDLE_MARGIN - PADDLE_WIDTH * 0.5
	if _hit_front_face(previous, "left", left_x, left_previous_y, left_y, left_last_vy):
		return true
	return _hit_front_face(previous, "right", right_x, right_previous_y, right_y, right_last_vy)


func _hit_front_face(previous: Vector2, side: String, paddle_x: float, previous_y: float, current_y: float, paddle_vy: float) -> bool:
	if side == "left" and ball_velocity.x >= 0.0:
		return false
	if side == "right" and ball_velocity.x <= 0.0:
		return false
	var direction := 1.0 if side == "left" else -1.0
	var face_x := paddle_x + direction * PADDLE_WIDTH * 0.5
	var contact_x := face_x + direction * BALL_RADIUS
	var crossed := previous.x > contact_x and ball_position.x <= contact_x if side == "left" else previous.x < contact_x and ball_position.x >= contact_x
	if not crossed:
		return false
	var span := previous.x - ball_position.x
	var t := 1.0
	if absf(span) > 0.0001:
		t = clampf((previous.x - contact_x) / span, 0.0, 1.0)
	var contact_y := previous.y + (ball_position.y - previous.y) * t
	var impact_center := lerpf(previous_y, current_y, t)
	var y_limit := PADDLE_HALF_HEIGHT + BALL_RADIUS + PADDLE_COLLISION_PAD
	if absf(contact_y - impact_center) > y_limit:
		return false
	contact_y = clampf(contact_y, impact_center - PADDLE_HALF_HEIGHT, impact_center + PADDLE_HALF_HEIGHT)
	var hit := clampf((contact_y - impact_center) / PADDLE_HALF_HEIGHT, -1.0, 1.0)
	var edge := absf(hit)
	var angle := hit * deg_to_rad(MAX_BOUNCE_ANGLE_DEG)
	var base := ball_velocity.length() * SPEED_INCREMENT
	base *= 1.0 + float(rally_hits) * RALLY_SPEED_STEP
	base *= lerpf(1.08, 0.95, edge)
	var speed := minf(base, MAX_SPEED)
	var velocity_y := sin(angle) * speed + paddle_vy * ENGLISH
	var min_vx := speed * MIN_HORIZONTAL
	var velocity_x := direction * maxf(absf(cos(angle) * speed), min_vx)
	ball_velocity = Vector2(velocity_x, velocity_y)
	if ball_velocity.length() > MAX_SPEED:
		ball_velocity = ball_velocity.limit_length(MAX_SPEED)
	min_vx = ball_velocity.length() * MIN_HORIZONTAL
	if absf(ball_velocity.x) < min_vx:
		var max_vy := sqrt(maxf(ball_velocity.length_squared() - min_vx * min_vx, 0.0))
		ball_velocity.x = direction * min_vx
		ball_velocity.y = signf(ball_velocity.y) * max_vy
	ball_position.x = contact_x + direction * 1.0
	ball_position.y = clampf(contact_y, HUD_HEIGHT + BALL_RADIUS, COURT_HEIGHT - 10.0 - BALL_RADIUS)
	rally_hits += 1
	return true


func _score(side: String) -> void:
	ball_velocity = Vector2.ZERO
	last_point = side
	if side == "left":
		left_score += 1
		serve_toward_right = false
	else:
		right_score += 1
		serve_toward_right = true
	if left_score >= WINNER_SCORE or right_score >= WINNER_SCORE:
		game_over = true
	else:
		between_points = true
		serving = true
		_serve_cooldown = SCORE_HOLD
		ball_position = Vector2(576.0, _court_center_y())


func _court_center_y() -> float:
	return (HUD_HEIGHT + COURT_HEIGHT) * 0.5


func _expire_stale_input(delta: float) -> void:
	_left_input_age += delta
	_right_input_age += delta
	if _left_input_age > INPUT_TIMEOUT:
		_left_axis = 0.0
		_left_target_y = -1.0
	if _right_input_age > INPUT_TIMEOUT:
		_right_axis = 0.0
		_right_target_y = -1.0


func _place_ball_for_serve() -> void:
	var direction := 1.0 if serve_toward_right else -1.0
	var paddle_y := left_y if serve_toward_right else right_y
	var paddle_x := PADDLE_MARGIN + PADDLE_WIDTH * 0.5 if serve_toward_right else COURT_WIDTH - PADDLE_MARGIN - PADDLE_WIDTH * 0.5
	ball_position = Vector2(paddle_x + direction * (PADDLE_WIDTH * 0.5 + BALL_RADIUS + 6.0), paddle_y)
