extends RefCounted
## Polygon Pong for 2-10 players. Each player defends one wall of a regular
## polygon. Miss the ball once and you are out: your wall disappears and the
## court shrinks to the next polygon; with two players left it collapses to a
## line for a timing-based 1D Pong finale. The last player left wins.
##
## The server runs the real match with this file (server/arena_simulation.gd is
## an identical copy, checked by a test). The game uses it too, to predict
## the ball between server updates.

const MIN_PLAYERS := 2
const MAX_PLAYERS := 10

# Polygon court, in local units around the court centre.
const RADIUS := 270.0
const BALL_RADIUS := 10.0
const PADDLE_THICKNESS := 14.0
const PADDLE_INSET := 18.0
const CORNER_RADIUS := 20.0
const PADDLE_SPEED := 470.0
const TARGET_CATCH_UP := 1.35
const START_SPEED := 360.0
const MAX_SPEED := 780.0
const SPEED_INCREMENT := 1.045
const MAX_BOUNCE_ANGLE_DEG := 55.0
const MIN_NORMAL := 0.45
const ENGLISH := 0.3
const SERVE_SPREAD_DEG := 22.0

# Line finale.
const LINE_LENGTH := 880.0
const ZONE_START := 150.0
const LINE_START_SPEED := 420.0
const LINE_MAX_SPEED := 1150.0
const LINE_SPEED_STEP := 1.03
const DEPTH_BONUS := 0.22
const WHIFF_LOCK := 0.4
const HIT_HISTORY_SECONDS := 0.5

const START_DELAY := 1.6
const SHRINK_DELAY := 1.8
const INPUT_TIMEOUT := 0.3
const STEP_DISTANCE := 4.0
const MAX_SUBSTEPS := 64
const SIM_RATE := 120.0

const STATE_COUNTDOWN := "countdown"
const STATE_PLAY := "play"
const STATE_OVER := "over"

var seat_count := 0
var state := STATE_COUNTDOWN
var timer := START_DELAY
## Seats still playing, in order around the court; wall j belongs to order[j].
var order: Array[int] = []
var paddle_pos: Array[float] = []
var paddle_prev: Array[float] = []
var paddle_vel: Array[float] = []
var zone: Array[float] = []
var ball_pos := Vector2.ZERO
var ball_vel := Vector2.ZERO
var hits := 0
var winner := -1
var last_loser := -1
var serve_seat := 0
var tick_number := 0
var rng := RandomNumberGenerator.new()
## Things that happened during the last ticks, for sound and effects.
var events: Array[Dictionary] = []
var _axis: Array[float] = []
var _target: Array[float] = []
var _input_age: Array[float] = []
var _hit_lock: Array[float] = []
var _line_history: Array[Vector3] = []
var _last_goal_tick := -1


func _init() -> void:
	rng.randomize()


## Starts a new match for this many players, everyone in.
func reset_match(players: int) -> void:
	seat_count = clampi(players, MIN_PLAYERS, MAX_PLAYERS)
	order.clear()
	paddle_pos.clear()
	paddle_prev.clear()
	paddle_vel.clear()
	zone.clear()
	_axis.clear()
	_target.clear()
	_input_age.clear()
	_hit_lock.clear()
	for seat in seat_count:
		order.append(seat)
		paddle_pos.append(0.0)
		paddle_prev.append(0.0)
		paddle_vel.append(0.0)
		zone.append(ZONE_START)
		_axis.append(0.0)
		_target.append(-1.0)
		_input_age.append(0.0)
		_hit_lock.append(0.0)
	_center_paddles()
	ball_pos = Vector2.ZERO
	ball_vel = Vector2.ZERO
	hits = 0
	winner = -1
	last_loser = -1
	tick_number = 0
	_last_goal_tick = -1
	_line_history.clear()
	state = STATE_COUNTDOWN
	timer = START_DELAY
	serve_seat = order[rng.randi_range(0, order.size() - 1)]
	events.clear()


## Copies another match's current state into this one, ready to play forward
## (online prediction uses this on a scratch copy of the server's match).
func copy_from(other) -> void:
	seat_count = other.seat_count
	order = other.order.duplicate()
	zone = other.zone.duplicate()
	paddle_pos = other.paddle_pos.duplicate()
	paddle_prev = other.paddle_pos.duplicate()
	paddle_vel = other.paddle_vel.duplicate()
	_hit_lock.clear()
	for _seat in seat_count:
		_hit_lock.append(0.0)
	state = STATE_PLAY
	ball_pos = other.ball_pos
	ball_vel = other.ball_vel
	hits = other.hits


## Lets a seat swing again right away (clears the early-swing lockout).
func allow_swing(seat: int) -> void:
	if seat >= 0 and seat < _hit_lock.size():
		_hit_lock[seat] = 0.0


# --- geometry -----------------------------------------------------------------

func wall_count() -> int:
	return order.size()


func is_line() -> bool:
	return order.size() == 2


func wall_of(seat: int) -> int:
	return order.find(seat)


func is_alive(seat: int) -> bool:
	return order.has(seat)


static func vertex(index: int, walls: int) -> Vector2:
	var angle := PI * 0.5 - PI / walls + TAU * index / walls
	return Vector2(cos(angle), sin(angle)) * RADIUS


static func side_length(walls: int) -> float:
	return 2.0 * RADIUS * sin(PI / walls)


static func paddle_length(walls: int) -> float:
	return clampf(side_length(walls) * 0.3, 70.0, 130.0)


static func paddle_min(walls: int) -> float:
	return CORNER_RADIUS + 4.0 + paddle_length(walls) * 0.5


static func paddle_max(walls: int) -> float:
	return side_length(walls) - paddle_min(walls)


## Start corner, unit tangent and inward unit normal of wall j.
static func wall_frame(wall: int, walls: int) -> Array[Vector2]:
	var start := vertex(wall, walls)
	var finish := vertex(wall + 1, walls)
	var tangent := (finish - start).normalized()
	var normal := -((start + finish) * 0.5).normalized()
	return [start, tangent, normal]


static func contact_plane() -> float:
	return PADDLE_INSET + PADDLE_THICKNESS * 0.5 + BALL_RADIUS


## Where each line player's end sits: order[0] at the left, order[1] at the right.
func line_end(seat: int) -> float:
	return -LINE_LENGTH * 0.5 if wall_of(seat) == 0 else LINE_LENGTH * 0.5


# --- input --------------------------------------------------------------------

func set_axis(seat: int, axis: float) -> void:
	if seat < 0 or seat >= seat_count:
		return
	_axis[seat] = clampf(axis, -1.0, 1.0)
	_target[seat] = -1.0
	_input_age[seat] = 0.0


func set_target(seat: int, target: float) -> void:
	if seat < 0 or seat >= seat_count:
		return
	var walls := maxi(wall_count(), 3)
	_target[seat] = clampf(target, paddle_min(walls), paddle_max(walls)) if target >= 0.0 else -1.0
	_input_age[seat] = 0.0


## A swing in the line finale. at_tick lets the server judge it against where
## the ball was when the player actually pressed.
func press_hit(seat: int, at_tick: int = -1) -> bool:
	if not is_line() or state != STATE_PLAY or not is_alive(seat) or _hit_lock[seat] > 0.0:
		return false
	var x := ball_pos.x
	var vx := ball_vel.x
	var ticks_back := 0
	if at_tick >= 0 and at_tick < tick_number:
		ticks_back = mini(tick_number - at_tick, int(HIT_HISTORY_SECONDS * SIM_RATE))
		if at_tick <= _last_goal_tick:
			return false
		var past := _history_at(tick_number - ticks_back)
		if past != Vector3.INF:
			x = past.x
			vx = past.y
		else:
			ticks_back = 0
	var end := line_end(seat)
	var toward := vx < 0.0 if end < 0.0 else vx > 0.0
	var depth := absf(end - x)
	var inside := toward and depth <= zone[seat] + BALL_RADIUS and (x >= end if end < 0.0 else x <= end)
	if not inside:
		_hit_lock[seat] = WHIFF_LOCK
		events.append({"type": "whiff", "seat": seat})
		return false
	var bonus := 1.0 + DEPTH_BONUS * clampf(1.0 - depth / maxf(zone[seat], 1.0), 0.0, 1.0)
	var speed := minf(absf(vx) * LINE_SPEED_STEP * bonus, LINE_MAX_SPEED)
	var away := 1.0 if end < 0.0 else -1.0
	ball_vel = Vector2(away * speed, 0.0)
	ball_pos = Vector2(x + ball_vel.x * ticks_back / SIM_RATE, 0.0)
	hits += 1
	events.append({"type": "paddle", "seat": seat, "x": ball_pos.x, "y": 0.0})
	return true


# --- simulation ---------------------------------------------------------------

func tick(delta: float) -> void:
	tick_number += 1
	for seat in seat_count:
		_hit_lock[seat] = maxf(_hit_lock[seat] - delta, 0.0)
		if not is_line():
			_update_paddle(seat, delta)
	match state:
		STATE_COUNTDOWN:
			ball_pos = Vector2.ZERO
			ball_vel = Vector2.ZERO
			timer -= delta
			if timer <= 0.0:
				_serve()
		STATE_PLAY:
			if is_line():
				_advance_line(delta)
			else:
				advance_ball(delta, true)


## Moves the polygon ball through corners and paddles. Returns false once it has
## left the court; only knocks the player out when apply_goals is set.
func advance_ball(delta: float, apply_goals: bool) -> bool:
	if ball_vel == Vector2.ZERO or is_line():
		return true
	var steps := clampi(ceili(ball_vel.length() * delta / STEP_DISTANCE), 1, MAX_SUBSTEPS)
	var step_delta := delta / float(steps)
	for _i in steps:
		var previous := ball_pos
		ball_pos += ball_vel * step_delta
		_bounce_corners()
		for wall in wall_count():
			if _hit_paddle(wall, previous):
				break
		var out_wall := _exited_wall()
		if out_wall >= 0:
			if apply_goals:
				_missed(order[out_wall])
			return false
	return true


## Moves the line ball. Returns false once it leaves.
func advance_line(delta: float, apply_goals: bool) -> bool:
	ball_pos.x += ball_vel.x * delta
	var left := order[0]
	var right := order[1]
	if ball_pos.x < -LINE_LENGTH * 0.5 - BALL_RADIUS * 2.0:
		if apply_goals:
			_missed(left)
		return false
	if ball_pos.x > LINE_LENGTH * 0.5 + BALL_RADIUS * 2.0:
		if apply_goals:
			_missed(right)
		return false
	return true


func _advance_line(delta: float) -> void:
	_line_history.append(Vector3(ball_pos.x, ball_vel.x, tick_number))
	while _line_history.size() > int(HIT_HISTORY_SECONDS * SIM_RATE) + 2:
		_line_history.pop_front()
	advance_line(delta, true)


func _history_at(at_tick: int) -> Vector3:
	for entry in _line_history:
		if int(entry.z) == at_tick:
			return entry
	return Vector3.INF


func snapshot() -> Dictionary:
	var paddles := []
	var velocities := []
	var zones := []
	for seat in seat_count:
		paddles.append(snappedf(paddle_pos[seat], 0.01))
		velocities.append(snappedf(paddle_vel[seat], 0.1))
		zones.append(snappedf(zone[seat], 0.1))
	return {
		"type": "arena_snapshot",
		"tick": tick_number,
		"state": state,
		"timer": snappedf(timer, 0.01),
		"order": order.duplicate(),
		"ball": [snappedf(ball_pos.x, 0.01), snappedf(ball_pos.y, 0.01), snappedf(ball_vel.x, 0.01), snappedf(ball_vel.y, 0.01)],
		"paddles": paddles,
		"pvel": velocities,
		"zones": zones,
		"seats": seat_count,
		"winner": winner,
		"loser": last_loser,
		"serve": serve_seat,
		"hits": hits,
	}


func apply_snapshot(data: Dictionary) -> void:
	var players := int(data.get("seats", seat_count))
	if players != seat_count:
		reset_match(players)
	state = str(data.get("state", state))
	timer = float(data.get("timer", timer))
	var remote_order = data.get("order", [])
	if remote_order is Array:
		order.clear()
		for seat in remote_order:
			order.append(int(seat))
	var ball = data.get("ball", [])
	if ball is Array and ball.size() == 4:
		ball_pos = Vector2(float(ball[0]), float(ball[1]))
		ball_vel = Vector2(float(ball[2]), float(ball[3]))
	_read_floats(data.get("paddles", []), paddle_pos)
	_read_floats(data.get("pvel", []), paddle_vel)
	_read_floats(data.get("zones", []), zone)
	for seat in seat_count:
		paddle_prev[seat] = paddle_pos[seat]
	winner = int(data.get("winner", winner))
	last_loser = int(data.get("loser", last_loser))
	serve_seat = int(data.get("serve", serve_seat))
	hits = int(data.get("hits", hits))
	tick_number = int(data.get("tick", tick_number))


func _read_floats(source, target: Array[float]) -> void:
	if not source is Array:
		return
	for seat in mini(source.size(), target.size()):
		target[seat] = float(source[seat])


func _center_paddles() -> void:
	var walls := maxi(wall_count(), 3)
	for seat in seat_count:
		paddle_pos[seat] = side_length(walls) * 0.5
		paddle_prev[seat] = paddle_pos[seat]
		paddle_vel[seat] = 0.0
		_target[seat] = -1.0


func _update_paddle(seat: int, delta: float) -> void:
	var before := paddle_pos[seat]
	paddle_prev[seat] = before
	var wall := wall_of(seat)
	if wall == -1:
		paddle_vel[seat] = 0.0
		return
	var walls := wall_count()
	var next := before
	# No word from this player for a moment: the paddle stops.
	_input_age[seat] += delta
	if _input_age[seat] > INPUT_TIMEOUT:
		_axis[seat] = 0.0
		_target[seat] = -1.0
	if _target[seat] >= 0.0:
		next = move_toward(before, _target[seat], PADDLE_SPEED * TARGET_CATCH_UP * delta)
	else:
		next = before + _axis[seat] * PADDLE_SPEED * delta
	paddle_pos[seat] = clampf(next, paddle_min(walls), paddle_max(walls))
	paddle_vel[seat] = (paddle_pos[seat] - before) / delta if delta > 0.0 else 0.0


func _serve() -> void:
	if not is_alive(serve_seat):
		serve_seat = order[rng.randi_range(0, order.size() - 1)]
	hits = 0
	state = STATE_PLAY
	ball_pos = Vector2.ZERO
	if is_line():
		var direction := -1.0 if line_end(serve_seat) < 0.0 else 1.0
		ball_vel = Vector2(direction * LINE_START_SPEED, 0.0)
	else:
		var frame := wall_frame(wall_of(serve_seat), wall_count())
		var spread := deg_to_rad(SERVE_SPREAD_DEG)
		var angle := rng.randf_range(spread * 0.35, spread) * (1.0 if rng.randf() < 0.5 else -1.0)
		ball_vel = (-frame[2]).rotated(angle) * START_SPEED
	events.append({"type": "serve", "seat": serve_seat})


func _bounce_corners() -> void:
	var walls := wall_count()
	for index in walls:
		var corner := vertex(index, walls)
		var offset := ball_pos - corner
		var distance := offset.length()
		var reach := CORNER_RADIUS + BALL_RADIUS
		if distance >= reach:
			continue
		var normal := offset / distance if distance > 0.0001 else -corner.normalized()
		ball_pos = corner + normal * reach
		var into := ball_vel.dot(normal)
		if into < 0.0:
			ball_vel -= normal * into * 2.0
			events.append({"type": "wall", "x": ball_pos.x, "y": ball_pos.y})


func _hit_paddle(wall: int, previous: Vector2) -> bool:
	var walls := wall_count()
	var seat := order[wall]
	var frame := wall_frame(wall, walls)
	var tangent := frame[1]
	var normal := frame[2]
	var vn := ball_vel.dot(normal)
	if vn >= 0.0:
		return false
	var plane := contact_plane()
	var v0 := (previous - frame[0]).dot(normal)
	var v1 := (ball_pos - frame[0]).dot(normal)
	if not (v0 > plane and v1 <= plane):
		return false
	var f := clampf((v0 - plane) / (v0 - v1), 0.0, 1.0) if absf(v0 - v1) > 0.0001 else 1.0
	var u0 := (previous - frame[0]).dot(tangent)
	var u1 := (ball_pos - frame[0]).dot(tangent)
	var contact_u := lerpf(u0, u1, f)
	var center := lerpf(paddle_prev[seat], paddle_pos[seat], f)
	var half := paddle_length(walls) * 0.5
	if absf(contact_u - center) > half + BALL_RADIUS:
		return false
	var hit := clampf((contact_u - center) / half, -1.0, 1.0)
	var angle := hit * deg_to_rad(MAX_BOUNCE_ANGLE_DEG)
	var speed := minf(ball_vel.length() * SPEED_INCREMENT * lerpf(1.05, 0.97, absf(hit)), MAX_SPEED)
	var out_normal := cos(angle) * speed
	var out_tangent := sin(angle) * speed + paddle_vel[seat] * ENGLISH
	var total := Vector2(out_tangent, out_normal).length()
	if total > MAX_SPEED:
		out_normal *= MAX_SPEED / total
		out_tangent *= MAX_SPEED / total
		total = MAX_SPEED
	var min_normal := total * MIN_NORMAL
	if out_normal < min_normal:
		out_normal = min_normal
		out_tangent = (1.0 if out_tangent >= 0.0 else -1.0) * sqrt(maxf(total * total - min_normal * min_normal, 0.0))
	ball_vel = tangent * out_tangent + normal * out_normal
	ball_pos = frame[0] + tangent * contact_u + normal * (plane + 1.0)
	hits += 1
	events.append({"type": "paddle", "seat": seat, "x": ball_pos.x, "y": ball_pos.y})
	return true


func _exited_wall() -> int:
	var walls := wall_count()
	var worst := -BALL_RADIUS
	var result := -1
	for wall in walls:
		var frame := wall_frame(wall, walls)
		var v := (ball_pos - frame[0]).dot(frame[2])
		if v < worst:
			worst = v
			result = wall
	return result


## The ball got past this player.
func _missed(seat: int) -> void:
	events.append({"type": "goal", "seat": seat, "x": ball_pos.x, "y": ball_pos.y})
	knock_out(seat)


## Takes a player out of the match (they missed, or left the room). Their wall
## disappears and the court shrinks; the last player left wins.
func knock_out(seat: int) -> void:
	if not is_alive(seat) or state == STATE_OVER:
		return
	last_loser = seat
	_last_goal_tick = tick_number
	ball_pos = Vector2.ZERO
	ball_vel = Vector2.ZERO
	_line_history.clear()
	events.append({"type": "out", "seat": seat, "wall": wall_of(seat)})
	order.erase(seat)
	if order.size() <= 1:
		state = STATE_OVER
		winner = order[0] if order.size() == 1 else -1
		events.append({"type": "win", "seat": winner})
		return
	_center_paddles()
	state = STATE_COUNTDOWN
	timer = SHRINK_DELAY
	serve_seat = order[rng.randi_range(0, order.size() - 1)]
