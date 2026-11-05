extends RefCounted
# Forward simulation of the authoritative online ball. Mirrors the wall and
# front-face paddle rules in server/match_simulation.gd so the client can draw
# the ball at the moment its own paddle input will reach the server.

const STEP_DISTANCE := 4.0
const MAX_STEPS := 192


## sample_paddle(side: String, offset: float) -> Vector2(y, vy) returns where a
## paddle is `offset` seconds after the snapshot the ball state came from.
func advance(pos: Vector2, vel: Vector2, rally_hits: int, duration: float, court: Vector2, sample_paddle: Callable) -> Dictionary:
	var result := {"pos": pos, "vel": vel, "rally_hits": rally_hits}
	if duration <= 0.0 or vel == Vector2.ZERO:
		return result
	var steps := clampi(ceili(vel.length() * duration / STEP_DISTANCE), 1, MAX_STEPS)
	var dt := duration / float(steps)
	var elapsed := 0.0
	var min_y := Constants.HUD_HEIGHT + Constants.BALL_RADIUS
	var max_y := court.y - 10.0 - Constants.BALL_RADIUS
	for _i in steps:
		if pos.x + Constants.BALL_RADIUS < 0.0 or pos.x - Constants.BALL_RADIUS > court.x:
			break
		var previous := pos
		pos += vel * dt
		elapsed += dt
		if pos.y < min_y:
			pos.y = min_y
			vel.y = absf(vel.y)
		elif pos.y > max_y:
			pos.y = max_y
			vel.y = -absf(vel.y)
		var side := "left" if vel.x < 0.0 else "right"
		var paddle: Vector2 = sample_paddle.call(side, elapsed)
		var hit := _hit_front_face(previous, pos, vel, side, paddle.x, paddle.y, rally_hits, court)
		if not hit.is_empty():
			pos = hit["pos"]
			vel = hit["vel"]
			rally_hits += 1
	result["pos"] = pos
	result["vel"] = vel
	result["rally_hits"] = rally_hits
	return result


func _hit_front_face(previous: Vector2, pos: Vector2, vel: Vector2, side: String, paddle_y: float, paddle_vy: float, rally_hits: int, court: Vector2) -> Dictionary:
	var direction := 1.0 if side == "left" else -1.0
	var paddle_x := Constants.PADDLE_MARGIN + Constants.PADDLE_WIDTH * 0.5
	if side == "right":
		paddle_x = court.x - paddle_x
	var face_x := paddle_x + direction * Constants.PADDLE_WIDTH * 0.5
	var contact_x := face_x + direction * Constants.BALL_RADIUS
	var crossed := previous.x > contact_x and pos.x <= contact_x if side == "left" else previous.x < contact_x and pos.x >= contact_x
	if not crossed:
		return {}
	var span := previous.x - pos.x
	var t := 1.0
	if absf(span) > 0.0001:
		t = clampf((previous.x - contact_x) / span, 0.0, 1.0)
	var contact_y := previous.y + (pos.y - previous.y) * t
	var y_limit := Constants.HALF_HEIGHT + Constants.BALL_RADIUS + Constants.PADDLE_COLLISION_PAD
	if absf(contact_y - paddle_y) > y_limit:
		return {}
	contact_y = clampf(contact_y, paddle_y - Constants.HALF_HEIGHT, paddle_y + Constants.HALF_HEIGHT)
	var hit := clampf((contact_y - paddle_y) / Constants.HALF_HEIGHT, -1.0, 1.0)
	var angle := hit * deg_to_rad(Constants.MAX_BOUNCE_ANGLE_DEG)
	var base := vel.length() * Constants.SPEED_INCREMENT
	base *= 1.0 + float(rally_hits) * Constants.RALLY_SPEED_STEP
	base *= lerpf(1.08, 0.95, absf(hit))
	var speed := minf(base, Constants.MAX_SPEED)
	var next_vel := Vector2(
		direction * maxf(absf(cos(angle) * speed), speed * Constants.MIN_HORIZONTAL),
		sin(angle) * speed + paddle_vy * Constants.ENGLISH
	)
	next_vel = next_vel.limit_length(Constants.MAX_SPEED)
	var min_vx := next_vel.length() * Constants.MIN_HORIZONTAL
	if absf(next_vel.x) < min_vx:
		var max_vy := sqrt(maxf(next_vel.length_squared() - min_vx * min_vx, 0.0))
		next_vel.x = direction * min_vx
		next_vel.y = signf(next_vel.y) * max_vy
	var next_pos := Vector2(
		contact_x + direction,
		clampf(contact_y, Constants.HUD_HEIGHT + Constants.BALL_RADIUS, court.y - 10.0 - Constants.BALL_RADIUS)
	)
	return {"pos": next_pos, "vel": next_vel}
