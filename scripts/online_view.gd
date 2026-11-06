extends RefCounted
## Makes online play feel instant even though the server is far away.
##
## The server runs the real match and sends a snapshot 40 times a second.
## Every snapshot is a little out of date by the time it arrives, so instead
## of drawing it as-is we predict forward:
##
## * We draw the ball one round trip ahead of the latest snapshot. That is the
##   moment our own paddle input reaches the server, so what you see is what
##   the server will decide.
## * Our own paddle moves instantly on our screen; the server follows it.
## * Other paddles are pushed forward a little using their speed.
## * When a new snapshot disagrees with what we drew, the difference fades out
##   over a few frames instead of the ball jumping.

const ArenaSimulation = preload("res://scripts/arena_simulation.gd")

const MAX_SNAPSHOT_AGE := 0.25
const MAX_ROUND_TRIP := 0.3
const OTHER_PADDLE_LOOKAHEAD := 0.15
const CORRECTION_FADE := 12.0
const MAX_CORRECTION_SPEED := 1300.0
const SNAP_DISTANCE := 360.0
const PREDICT_STEP := 1.0 / 120.0
const HISTORY_SECONDS := 1.0
const IDLE_RESYNC_AFTER := 0.5
const RESYNC_RATE := 10.0

## The latest state from the server.
var sim := ArenaSimulation.new()
var my_seat := -1
var have_snapshot := false

var _predictor := ArenaSimulation.new()
var _snapshot_time := 0.0
var _my_paddle := 0.0
var _my_paddle_speed := 0.0
var _idle_time := 0.0
var _history_time := PackedFloat64Array()
var _history_position := PackedFloat32Array()
var _history_speed := PackedFloat32Array()
var _my_swings: Array[int] = []
var _ball_correction := Vector2.ZERO
var _paddle_correction: Array[float] = []


func start(seat: int) -> void:
	my_seat = seat
	have_snapshot = false
	_ball_correction = Vector2.ZERO
	_paddle_correction.clear()
	for _seat in ArenaSimulation.MAX_PLAYERS:
		_paddle_correction.append(0.0)
	_history_time.clear()
	_history_position.clear()
	_history_speed.clear()
	_my_swings.clear()


## Takes in a new snapshot. Returns what changed so the game can react:
## {"first": bool, "lives_before": Array, "order_before": Array}
func take_snapshot(data: Dictionary) -> Dictionary:
	var now := _now()
	var was_playing := sim.state == ArenaSimulation.STATE_PLAY
	var was_line := sim.is_line()
	var walls_before := sim.wall_count()
	# Remember what is on screen right now, so we can fade from it.
	var shown_ball := Vector2.ZERO
	var shown_paddles: Array[float] = []
	if have_snapshot:
		if was_playing:
			shown_ball = predict_ball(now, 0.0)["position"]
		for seat in sim.seat_count:
			shown_paddles.append(_other_paddle(seat, now) + _paddle_correction[seat])
	var change := {"first": not have_snapshot, "lives_before": sim.lives.duplicate(), "order_before": sim.order.duplicate()}

	sim.apply_snapshot(data)
	_snapshot_time = now
	var still_waiting: Array[int] = []
	for swing_tick in _my_swings:
		if swing_tick > sim.tick_number:
			still_waiting.append(swing_tick)
	_my_swings = still_waiting

	var shape_changed := sim.wall_count() != walls_before
	if not have_snapshot or shape_changed:
		have_snapshot = true
		if sim.wall_of(my_seat) >= 0:
			_my_paddle = sim.paddle_pos[my_seat]
		if change["first"]:
			return change

	_ball_correction = Vector2.ZERO
	if sim.state == ArenaSimulation.STATE_PLAY and was_line == sim.is_line():
		# A fresh serve starts from the centre spot the ball was waiting on.
		var from := shown_ball if was_playing else Vector2.ZERO
		_ball_correction = from - _predict_raw(now, 0.0)["position"]
		if _ball_correction.length() > SNAP_DISTANCE:
			_ball_correction = Vector2.ZERO
	for seat in shown_paddles.size():
		_paddle_correction[seat] = 0.0 if shape_changed else shown_paddles[seat] - _other_paddle(seat, now)
		if absf(_paddle_correction[seat]) > SNAP_DISTANCE:
			_paddle_correction[seat] = 0.0
	return change


## Moves our own paddle from the keyboard and tells the server where it is.
func move_my_paddle(axis: float, delta: float) -> void:
	if sim.wall_of(my_seat) < 0 or sim.is_line():
		return
	var now := _now()
	var walls := sim.wall_count()
	var before := _my_paddle
	_my_paddle = clampf(_my_paddle + axis * ArenaSimulation.PADDLE_SPEED * delta, ArenaSimulation.paddle_min(walls), ArenaSimulation.paddle_max(walls))
	if absf(_my_paddle - before) > 0.001:
		_idle_time = 0.0
	else:
		_idle_time += delta
		# Standing still for a while: gently agree with the server's position.
		if _idle_time > IDLE_RESYNC_AFTER + _round_trip():
			var server_position := sim.paddle_pos[my_seat]
			if absf(server_position - _my_paddle) > 0.5:
				_my_paddle = lerpf(_my_paddle, server_position, 1.0 - exp(-RESYNC_RATE * delta))
	_my_paddle_speed = (_my_paddle - before) / delta if delta > 0.0 else 0.0
	_remember_my_paddle(now)
	Network.send_paddle(axis, _my_paddle)


## Fades out corrections a little more each frame.
func fade_corrections(delta: float) -> void:
	var keep := exp(-CORRECTION_FADE * delta)
	var step := _ball_correction * (1.0 - keep)
	_ball_correction -= step.limit_length(MAX_CORRECTION_SPEED * delta)
	for seat in _paddle_correction.size():
		_paddle_correction[seat] *= keep


## Where to draw a paddle along its wall right now.
func paddle_position(seat: int) -> float:
	if seat == my_seat:
		return _my_paddle
	var walls := maxi(sim.wall_count(), 3)
	return clampf(_other_paddle(seat, _now()) + _paddle_correction[seat], ArenaSimulation.paddle_min(walls), ArenaSimulation.paddle_max(walls))


## Records a swing in the line finale and returns the server tick to send.
func swing() -> int:
	var at_tick := sim.tick_number + int(round(_view_ahead(_now()) * ArenaSimulation.SIM_RATE))
	_my_swings.append(at_tick)
	return at_tick


## The ball as we should draw it now: {"position", "velocity", "events"}.
## frame_delta > 0 also collects hits that happen this frame, for sounds.
func predict_ball(now: float, frame_delta: float) -> Dictionary:
	var result := _predict_raw(now, frame_delta)
	result["position"] += _ball_correction
	return result


# --- prediction ---------------------------------------------------------------

func _predict_raw(now: float, frame_delta: float) -> Dictionary:
	var ahead := _view_ahead(now)
	_predictor.copy_from(sim)
	var line := sim.is_line()
	var swings := _my_swings.duplicate()
	swings.sort()
	var next_swing := 0
	var events_this_frame: Array = []
	var elapsed := 0.0
	while elapsed < ahead - 0.000001:
		var step := minf(PREDICT_STEP, ahead - elapsed)
		elapsed += step
		_predictor.events.clear()
		var still_in := true
		if line:
			var tick := sim.tick_number + int(round(elapsed * ArenaSimulation.SIM_RATE))
			while next_swing < swings.size() and swings[next_swing] <= tick:
				_predictor.allow_swing(my_seat)
				_predictor.press_hit(my_seat)
				next_swing += 1
			still_in = _predictor.advance_line(step, false)
			_wait_at_opponent_end()
		else:
			for seat in sim.seat_count:
				var paddle := _paddle_at(seat, elapsed)
				_predictor.paddle_prev[seat] = _predictor.paddle_pos[seat]
				_predictor.paddle_pos[seat] = paddle.x
				_predictor.paddle_vel[seat] = paddle.y
			still_in = _predictor.advance_ball(step, false)
		if frame_delta > 0.0 and elapsed > ahead - frame_delta:
			events_this_frame.append_array(_predictor.events)
		if not still_in:
			break
	_predictor.events.clear()
	return {"position": _predictor.ball_pos, "velocity": _predictor.ball_vel, "events": events_this_frame}


## On the line we can't know if the opponent will swing, so the ball waits at
## their end until the server tells us.
func _wait_at_opponent_end() -> void:
	for seat in _predictor.order:
		if seat == my_seat:
			continue
		var end := _predictor.line_end(seat)
		if (end > 0.0 and _predictor.ball_pos.x > end) or (end < 0.0 and _predictor.ball_pos.x < end):
			_predictor.ball_pos.x = end


## How far ahead of the latest snapshot we draw: its age plus one round trip.
func _view_ahead(now: float) -> float:
	return clampf(now - _snapshot_time, 0.0, MAX_SNAPSHOT_AGE) + _round_trip()


func _round_trip() -> float:
	return clampf(Network.rtt_seconds, 0.0, MAX_ROUND_TRIP)


## A paddle's (position, speed) `offset` seconds after the latest snapshot.
func _paddle_at(seat: int, offset: float) -> Vector2:
	if seat == my_seat:
		# The server applies our paddle one round trip after we moved it.
		return _my_paddle_at(_snapshot_time - _round_trip() + offset)
	var walls := maxi(sim.wall_count(), 3)
	var speed := sim.paddle_vel[seat]
	var position := sim.paddle_pos[seat] + speed * minf(offset, OTHER_PADDLE_LOOKAHEAD)
	position = clampf(position, ArenaSimulation.paddle_min(walls), ArenaSimulation.paddle_max(walls))
	return Vector2(position, speed if offset <= OTHER_PADDLE_LOOKAHEAD else 0.0)


func _other_paddle(seat: int, now: float) -> float:
	return _paddle_at(seat, _view_ahead(now)).x


func _remember_my_paddle(now: float) -> void:
	_history_time.append(now)
	_history_position.append(_my_paddle)
	_history_speed.append(_my_paddle_speed)
	var too_old := 0
	while too_old < _history_time.size() and _history_time[too_old] < now - HISTORY_SECONDS:
		too_old += 1
	if too_old > 0:
		_history_time = _history_time.slice(too_old)
		_history_position = _history_position.slice(too_old)
		_history_speed = _history_speed.slice(too_old)


## Where our paddle was at an earlier moment (looked up in our history).
func _my_paddle_at(time: float) -> Vector2:
	var count := _history_time.size()
	if count == 0 or time >= _history_time[count - 1]:
		return Vector2(_my_paddle, _my_paddle_speed)
	for i in range(count - 2, -1, -1):
		if _history_time[i] <= time:
			var span := _history_time[i + 1] - _history_time[i]
			var weight := (time - _history_time[i]) / span if span > 0.0 else 1.0
			return Vector2(lerpf(_history_position[i], _history_position[i + 1], weight), _history_speed[i + 1])
	return Vector2(_history_position[0], _history_speed[0])


func _now() -> float:
	return Time.get_ticks_usec() / 1000000.0
