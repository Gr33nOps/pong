extends RefCounted
## Four-player square Pong: one paddle per wall, corner blocks, lives and CPU
## seats. The same file runs on the client (local play and online prediction)
## and on the server as server/quad_simulation.gd; a test keeps them identical.

const SEATS := 4
const LEFT := 0
const RIGHT := 1
const TOP := 2
const BOTTOM := 3
const SEAT_NAMES: Array[String] = ["LEFT", "RIGHT", "TOP", "BOTTOM"]

const SIZE := 540.0
const BALL_RADIUS := 12.0
const PADDLE_LENGTH := 104.0
const PADDLE_THICKNESS := 16.0
const PADDLE_INSET := 22.0
const CORNER := 46.0
const PADDLE_SPEED := 520.0
const TARGET_CATCH_UP := 1.35
const START_SPEED := 400.0
const MAX_SPEED := 820.0
const SPEED_INCREMENT := 1.04
const MAX_BOUNCE_ANGLE_DEG := 58.0
const SERVE_SPREAD_DEG := 24.0
const MIN_NORMAL := 0.42
const MIN_AXIS := 0.22
const ENGLISH := 0.35
const STARTING_LIVES := 5
const START_DELAY := 1.6
const POINT_DELAY := 1.1
const INPUT_TIMEOUT := 0.3
const STEP_DISTANCE := 4.0
const MAX_SUBSTEPS := 64
const SKILL_EASY := 0.55
const SKILL_NORMAL := 0.82
const SKILL_HARD := 1.0

const STATE_COUNTDOWN := "countdown"
const STATE_PLAY := "play"
const STATE_OVER := "over"

var state := STATE_COUNTDOWN
var timer := START_DELAY
var lives: Array[int] = []
var cpu: Array[bool] = []
var paddle_pos: Array[float] = []
var paddle_prev: Array[float] = []
var paddle_vel: Array[float] = []
var ball_pos := Vector2(SIZE * 0.5, SIZE * 0.5)
var ball_vel := Vector2.ZERO
var hits := 0
var winner := -1
var last_loser := -1
var serve_seat := 0
var tick_number := 0
var cpu_skill := SKILL_NORMAL
var rng := RandomNumberGenerator.new()
## Things that happened during the last ticks, for sound and effects.
var events: Array[Dictionary] = []
var _axis: Array[float] = []
var _target: Array[float] = []
var _input_age: Array[float] = []
var _ai_incoming: Array[bool] = []
var _ai_reaction: Array[float] = []
var _ai_offset: Array[float] = []


func _init() -> void:
	rng.randomize()
	for _seat in SEATS:
		lives.append(STARTING_LIVES)
		cpu.append(false)
		paddle_pos.append(SIZE * 0.5)
		paddle_prev.append(SIZE * 0.5)
		paddle_vel.append(0.0)
		_axis.append(0.0)
		_target.append(-1.0)
		_input_age.append(0.0)
		_ai_incoming.append(false)
		_ai_reaction.append(0.0)
		_ai_offset.append(0.0)


func reset_match(cpu_seats: Array) -> void:
	for seat in SEATS:
		lives[seat] = STARTING_LIVES
		cpu[seat] = bool(cpu_seats[seat]) if seat < cpu_seats.size() else true
		paddle_pos[seat] = SIZE * 0.5
		paddle_prev[seat] = SIZE * 0.5
		paddle_vel[seat] = 0.0
		_axis[seat] = 0.0
		_target[seat] = -1.0
		_input_age[seat] = 0.0
		_ai_incoming[seat] = false
		_ai_reaction[seat] = 0.0
		_ai_offset[seat] = 0.0
	ball_pos = Vector2(SIZE * 0.5, SIZE * 0.5)
	ball_vel = Vector2.ZERO
	hits = 0
	winner = -1
	last_loser = -1
	tick_number = 0
	state = STATE_COUNTDOWN
	timer = START_DELAY
	serve_seat = _pick_serve_seat(-1)
	events.clear()


static func normal_axis(seat: int) -> int:
	return 0 if seat == LEFT or seat == RIGHT else 1


static func normal_sign(seat: int) -> float:
	return 1.0 if seat == LEFT or seat == TOP else -1.0


## Ball-centre coordinate along the seat's normal where it meets the paddle face.
static func contact_plane(seat: int) -> float:
	var near := PADDLE_INSET + PADDLE_THICKNESS * 0.5 + BALL_RADIUS
	return near if normal_sign(seat) > 0.0 else SIZE - near


static func paddle_min() -> float:
	return CORNER + PADDLE_LENGTH * 0.5


static func paddle_max() -> float:
	return SIZE - CORNER - PADDLE_LENGTH * 0.5


func is_alive(seat: int) -> bool:
	return lives[seat] > 0


func alive_count() -> int:
	var count := 0
	for seat in SEATS:
		if is_alive(seat):
			count += 1
	return count


func set_cpu(seat: int, enabled: bool) -> void:
	cpu[seat] = enabled
	_ai_incoming[seat] = false


func set_axis(seat: int, axis: float) -> void:
	_axis[seat] = clampf(axis, -1.0, 1.0)
	_target[seat] = -1.0
	_input_age[seat] = 0.0


func set_target(seat: int, target: float) -> void:
	_target[seat] = clampf(target, paddle_min(), paddle_max()) if target >= 0.0 else -1.0
	_input_age[seat] = 0.0


func tick(delta: float) -> void:
	tick_number += 1
	for seat in SEATS:
		_update_paddle(seat, delta)
	match state:
		STATE_COUNTDOWN:
			ball_pos = Vector2(SIZE * 0.5, SIZE * 0.5)
			ball_vel = Vector2.ZERO
			timer -= delta
			if timer <= 0.0:
				_serve()
		STATE_PLAY:
			advance_ball(delta, true)


## Moves the ball through walls, corners and paddles. Returns false once it has
## left the court; only applies lives and serves when apply_goals is set.
func advance_ball(delta: float, apply_goals: bool) -> bool:
	if ball_vel == Vector2.ZERO:
		return true
	var steps := clampi(ceili(ball_vel.length() * delta / STEP_DISTANCE), 1, MAX_SUBSTEPS)
	var step_delta := delta / float(steps)
	for _i in steps:
		var previous := ball_pos
		ball_pos += ball_vel * step_delta
		_bounce_dead_walls()
		_bounce_corners()
		for seat in SEATS:
			if is_alive(seat) and _hit_paddle(seat, previous):
				break
		var out_seat := _exited_seat()
		if out_seat >= 0:
			if apply_goals:
				_lose_life(out_seat)
			return false
	return true


func snapshot() -> Dictionary:
	var paddles := []
	var velocities := []
	for seat in SEATS:
		paddles.append(snappedf(paddle_pos[seat], 0.01))
		velocities.append(snappedf(paddle_vel[seat], 0.1))
	return {
		"type": "quad_snapshot",
		"tick": tick_number,
		"state": state,
		"timer": snappedf(timer, 0.01),
		"ball": [snappedf(ball_pos.x, 0.01), snappedf(ball_pos.y, 0.01), snappedf(ball_vel.x, 0.01), snappedf(ball_vel.y, 0.01)],
		"paddles": paddles,
		"pvel": velocities,
		"lives": lives.duplicate(),
		"cpu": cpu.duplicate(),
		"winner": winner,
		"loser": last_loser,
		"serve": serve_seat,
		"hits": hits,
	}


func apply_snapshot(data: Dictionary) -> void:
	state = str(data.get("state", state))
	timer = float(data.get("timer", timer))
	var ball = data.get("ball", [])
	if ball is Array and ball.size() == 4:
		ball_pos = Vector2(float(ball[0]), float(ball[1]))
		ball_vel = Vector2(float(ball[2]), float(ball[3]))
	_read_seat_floats(data.get("paddles", []), paddle_pos)
	_read_seat_floats(data.get("pvel", []), paddle_vel)
	var remote_lives = data.get("lives", [])
	var remote_cpu = data.get("cpu", [])
	for seat in SEATS:
		if remote_lives is Array and seat < remote_lives.size():
			lives[seat] = int(remote_lives[seat])
		if remote_cpu is Array and seat < remote_cpu.size():
			cpu[seat] = bool(remote_cpu[seat])
		paddle_prev[seat] = paddle_pos[seat]
	winner = int(data.get("winner", winner))
	last_loser = int(data.get("loser", last_loser))
	serve_seat = int(data.get("serve", serve_seat))
	hits = int(data.get("hits", hits))
	tick_number = int(data.get("tick", tick_number))


func _read_seat_floats(source, target: Array[float]) -> void:
	if not source is Array:
		return
	for seat in mini(source.size(), SEATS):
		target[seat] = float(source[seat])


func _update_paddle(seat: int, delta: float) -> void:
	var before := paddle_pos[seat]
	paddle_prev[seat] = before
	if not is_alive(seat):
		paddle_vel[seat] = 0.0
		return
	var next := before
	if cpu[seat]:
		next = move_toward(before, _ai_target(seat, delta), PADDLE_SPEED * cpu_skill * delta)
	else:
		_input_age[seat] += delta
		if _input_age[seat] > INPUT_TIMEOUT:
			_axis[seat] = 0.0
			_target[seat] = -1.0
		if _target[seat] >= 0.0:
			next = move_toward(before, _target[seat], PADDLE_SPEED * TARGET_CATCH_UP * delta)
		else:
			next = before + _axis[seat] * PADDLE_SPEED * delta
	paddle_pos[seat] = clampf(next, paddle_min(), paddle_max())
	paddle_vel[seat] = (paddle_pos[seat] - before) / delta if delta > 0.0 else 0.0


func _ai_target(seat: int, delta: float) -> float:
	var center := SIZE * 0.5
	if state != STATE_PLAY:
		_ai_incoming[seat] = false
		return center
	var n := normal_axis(seat)
	var t := 1 - n
	var side_dir := normal_sign(seat)
	if ball_vel[n] * side_dir >= 0.0:
		_ai_incoming[seat] = false
		return lerpf(center, ball_pos[t], 0.25)
	if not _ai_incoming[seat]:
		_ai_incoming[seat] = true
		_ai_reaction[seat] = 0.0
		var error := _ai_error()
		_ai_offset[seat] = rng.randf_range(-error, error)
	else:
		_ai_reaction[seat] += delta
	if _ai_reaction[seat] < _ai_delay():
		return paddle_pos[seat]
	var time := (contact_plane(seat) - ball_pos[n]) / ball_vel[n]
	if time < 0.0:
		return ball_pos[t]
	var low := BALL_RADIUS
	var span := SIZE - BALL_RADIUS * 2.0
	var folded := fposmod(ball_pos[t] + ball_vel[t] * time - low, span * 2.0)
	if folded > span:
		folded = span * 2.0 - folded
	return low + folded + _ai_offset[seat]


func _ai_delay() -> float:
	if cpu_skill <= 0.8:
		return 0.3
	if cpu_skill >= 0.97:
		return 0.0
	return 0.1


## Aim error grows with ball speed so long rallies eventually end, even when
## only CPU paddles are left.
func _ai_error() -> float:
	var base := 46.0
	if cpu_skill <= 0.8:
		base = 70.0
	elif cpu_skill >= 0.97:
		base = 34.0
	var speed_ratio := clampf((ball_vel.length() - START_SPEED) / (MAX_SPEED - START_SPEED), 0.0, 1.0)
	return base * (1.0 + speed_ratio)


func _serve() -> void:
	serve_seat = _pick_serve_seat(serve_seat)
	var direction := Vector2.ZERO
	match serve_seat:
		LEFT:
			direction = Vector2.LEFT
		RIGHT:
			direction = Vector2.RIGHT
		TOP:
			direction = Vector2.UP
		_:
			direction = Vector2.DOWN
	var spread := deg_to_rad(SERVE_SPREAD_DEG)
	var angle := rng.randf_range(spread * 0.35, spread) * (1.0 if rng.randf() < 0.5 else -1.0)
	ball_pos = Vector2(SIZE * 0.5, SIZE * 0.5)
	ball_vel = direction.rotated(angle) * START_SPEED
	hits = 0
	state = STATE_PLAY
	events.append({"type": "serve", "seat": serve_seat})


func _pick_serve_seat(preferred: int) -> int:
	if preferred >= 0 and preferred < SEATS and is_alive(preferred):
		return preferred
	var alive: Array[int] = []
	for seat in SEATS:
		if is_alive(seat):
			alive.append(seat)
	if alive.is_empty():
		return 0
	return alive[rng.randi_range(0, alive.size() - 1)]


func _bounce_dead_walls() -> void:
	for seat in SEATS:
		if is_alive(seat):
			continue
		var n := normal_axis(seat)
		if normal_sign(seat) > 0.0:
			if ball_pos[n] < BALL_RADIUS:
				ball_pos[n] = BALL_RADIUS
				if ball_vel[n] < 0.0:
					ball_vel[n] = -ball_vel[n]
					_after_rebound()
		elif ball_pos[n] > SIZE - BALL_RADIUS:
			ball_pos[n] = SIZE - BALL_RADIUS
			if ball_vel[n] > 0.0:
				ball_vel[n] = -ball_vel[n]
				_after_rebound()


func _bounce_corners() -> void:
	var far := SIZE - CORNER
	for corner in [Vector2(0.0, 0.0), Vector2(far, 0.0), Vector2(0.0, far), Vector2(far, far)]:
		var closest := Vector2(
			clampf(ball_pos.x, corner.x, corner.x + CORNER),
			clampf(ball_pos.y, corner.y, corner.y + CORNER)
		)
		var offset := ball_pos - closest
		var distance := offset.length()
		if distance >= BALL_RADIUS:
			continue
		var normal := offset / distance if distance > 0.0001 else (Vector2(SIZE * 0.5, SIZE * 0.5) - ball_pos).normalized()
		ball_pos = closest + normal * BALL_RADIUS
		var into := ball_vel.dot(normal)
		if into < 0.0:
			ball_vel -= normal * into * 2.0
			_after_rebound()


## Wall and corner rebounds keep some motion on both axes so the ball can't
## shuttle forever between two knocked-out walls.
func _after_rebound() -> void:
	var speed := ball_vel.length()
	if speed <= 0.0:
		return
	var minimum := speed * MIN_AXIS
	for axis in 2:
		if absf(ball_vel[axis]) < minimum:
			var direction := 1.0 if ball_vel[axis] >= 0.0 else -1.0
			ball_vel[axis] = direction * minimum
			var other := 1 - axis
			var other_direction := 1.0 if ball_vel[other] >= 0.0 else -1.0
			ball_vel[other] = other_direction * sqrt(maxf(speed * speed - minimum * minimum, 0.0))
	events.append({"type": "wall", "x": ball_pos.x, "y": ball_pos.y})


func _hit_paddle(seat: int, previous: Vector2) -> bool:
	var n := normal_axis(seat)
	var t := 1 - n
	var side_dir := normal_sign(seat)
	if ball_vel[n] * side_dir >= 0.0:
		return false
	var contact := contact_plane(seat)
	if not ((previous[n] - contact) * side_dir > 0.0 and (ball_pos[n] - contact) * side_dir <= 0.0):
		return false
	var span := previous[n] - ball_pos[n]
	var f := clampf((previous[n] - contact) / span, 0.0, 1.0) if absf(span) > 0.0001 else 1.0
	var contact_t := lerpf(previous[t], ball_pos[t], f)
	var center := lerpf(paddle_prev[seat], paddle_pos[seat], f)
	var half := PADDLE_LENGTH * 0.5
	if absf(contact_t - center) > half + BALL_RADIUS:
		return false
	var hit := clampf((contact_t - center) / half, -1.0, 1.0)
	var angle := hit * deg_to_rad(MAX_BOUNCE_ANGLE_DEG)
	var speed := minf(ball_vel.length() * SPEED_INCREMENT * lerpf(1.06, 0.97, absf(hit)), MAX_SPEED)
	var next := Vector2.ZERO
	next[n] = side_dir * cos(angle) * speed
	next[t] = sin(angle) * speed + paddle_vel[seat] * ENGLISH
	next = next.limit_length(MAX_SPEED)
	var total := next.length()
	var min_normal := total * MIN_NORMAL
	if absf(next[n]) < min_normal:
		next[n] = side_dir * min_normal
		next[t] = (1.0 if next[t] >= 0.0 else -1.0) * sqrt(maxf(total * total - min_normal * min_normal, 0.0))
	ball_vel = next
	ball_pos[n] = contact + side_dir
	ball_pos[t] = contact_t
	hits += 1
	events.append({"type": "paddle", "seat": seat, "x": ball_pos.x, "y": ball_pos.y})
	return true


func _exited_seat() -> int:
	if ball_pos.x < -BALL_RADIUS:
		return LEFT
	if ball_pos.x > SIZE + BALL_RADIUS:
		return RIGHT
	if ball_pos.y < -BALL_RADIUS:
		return TOP
	if ball_pos.y > SIZE + BALL_RADIUS:
		return BOTTOM
	return -1


func _lose_life(seat: int) -> void:
	lives[seat] = maxi(lives[seat] - 1, 0)
	last_loser = seat
	events.append({"type": "goal", "seat": seat, "lives": lives[seat], "x": ball_pos.x, "y": ball_pos.y})
	ball_pos = Vector2(SIZE * 0.5, SIZE * 0.5)
	ball_vel = Vector2.ZERO
	if lives[seat] == 0:
		paddle_vel[seat] = 0.0
		events.append({"type": "out", "seat": seat})
	if alive_count() <= 1:
		state = STATE_OVER
		winner = -1
		for candidate in SEATS:
			if is_alive(candidate):
				winner = candidate
		events.append({"type": "win", "seat": winner})
		return
	serve_seat = _pick_serve_seat(seat)
	state = STATE_COUNTDOWN
	timer = POINT_DELAY
