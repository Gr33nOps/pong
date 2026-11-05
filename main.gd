extends Node2D

@onready var ball = $ball
@onready var left_label = $leftScore
@onready var right_label = $rightScore
@onready var paddle_left = $paddleLeft
@onready var paddle_right = $paddleRight
@onready var divider = $Divider
@onready var center_line_ink: Sprite2D = $CenterLineInk
@onready var trail = $Trail
@onready var playfield_clip = $PlayfieldClip
@onready var hud = $HUD
@onready var score_flash = $ScoreFlash
@onready var court_bg = $Court/Background
@onready var left_wash = $Court/LeftWash
@onready var right_wash = $Court/RightWash
@onready var top_rail = $Court/TopRail
@onready var bottom_rail = $Court/BottomRail
@onready var ink_rails = $InkRails

const OnlinePrediction = preload("res://online_prediction.gd")

var playfield_size := Vector2.ZERO
var _pointer_paddles: Dictionary = {}
var _pointer_offsets: Dictionary = {}
var _last_landscape := true
var _orientation_paused := false
var _online_predictor = OnlinePrediction.new()
var _online_snapshot_ready := false
var _online_snapshot_time := 0.0
var _snap_ball_pos := Vector2.ZERO
var _snap_ball_vel := Vector2.ZERO
var _snap_rally_hits := 0
var _snap_paddle_y := {"left": 360.0, "right": 360.0}
var _snap_paddle_vy := {"left": 0.0, "right": 0.0}
var _ball_error := Vector2.ZERO
var _remote_error := 0.0
var _predicted_velocity := Vector2.ZERO
var _local_idle_time := 0.0
var _history_t := PackedFloat64Array()
var _history_y := PackedFloat32Array()
var _history_vy := PackedFloat32Array()
var _last_hit_fx_time := -1.0
var _last_wall_fx_time := -1.0

# Online view runs ahead of the latest snapshot by its age plus one round trip,
# which is when this client's paddle input actually lands on the server.
const ONLINE_MAX_SNAPSHOT_AGE := 0.25
const ONLINE_MAX_LEAD_RTT := 0.3
const ONLINE_REMOTE_EXTRAPOLATION := 0.15
const ONLINE_ERROR_DECAY := 12.0
const ONLINE_SNAP_DISTANCE := 160.0
const ONLINE_LOCAL_IDLE_RESYNC := 0.5
const ONLINE_LOCAL_RESYNC_RATE := 10.0
const ONLINE_HISTORY_SECONDS := 1.0
const ONLINE_FX_COOLDOWN := 0.12
# Touching near your paddle grabs it where it is instead of jumping it under the finger.
const TOUCH_GRAB_SLACK := 70.0


func _ready() -> void:
	ScreenShake.reset()
	_last_landscape = _window_is_landscape()
	_update_playfield_size()
	GameState.score_changed.connect(_on_score_changed)
	GameState.serving_changed.connect(_on_serving_changed)
	GameState.game_over.connect(_on_game_over)
	GameState.colorblind_changed.connect(_on_colorblind_changed)
	GameState.mode_changed.connect(_on_mode_changed)
	GameState.point_scored.connect(_on_point_scored)
	GameState.rematch_started.connect(_on_rematch_started)
	GameState.paused_changed.connect(_on_paused_changed)
	NetworkManager.snapshot_received.connect(_on_online_snapshot)
	NetworkManager.rematch_started.connect(_on_online_rematch_started)
	GameState.online_match_cancelled.connect(_on_online_match_cancelled)
	ball.rally_changed.connect(_on_rally_changed)
	hud.bind_ball(ball)
	GameState.reset_game()
	get_tree().root.connect("size_changed", _update_playfield_size)
	left_label.visible = false
	right_label.visible = false
	score_flash.modulate.a = 0.0
	score_flash.visible = false
	# The trail was deliberately removed from the presentation; do not keep its
	# script in the frame loop on lower-powered browsers and phones.
	trail.set_process(false)
	_set_match_visible(false)


func _window_is_landscape() -> bool:
	# The court is a fixed 1152x648 viewport, so orientation has to come from the
	# real window; the web shell shows its own full-screen rotate prompt.
	var window_size := DisplayServer.window_get_size()
	return window_size.x >= window_size.y


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		GameState.note_input("keyboard")
	elif event is InputEventJoypadButton or event is InputEventJoypadMotion:
		GameState.note_input("controller")
	if GameState.paused or GameState.is_game_over or not GameState.mode_selected:
		_release_all_pointers()
		return
	if GameState.serving and GameState.is_cpu_serving():
		_release_all_pointers()
		return
	if event is InputEventScreenTouch:
		GameState.note_input("touch")
		_refresh_touch_roots()
		_handle_pointer_touch(event.index, event.position, event.pressed)
	elif event is InputEventScreenDrag:
		GameState.note_input("touch")
		_refresh_touch_roots()
		_handle_pointer_motion(event.index, event.position)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		GameState.note_input("mouse")
		_handle_pointer_touch(-1, event.position, event.pressed)
	elif event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		GameState.note_input("mouse")
		_handle_pointer_motion(-1, event.position)


func _refresh_touch_roots() -> void:
	# Re-apply the existing touch scale after browser/tablet resizes and
	# orientation changes; the overlays use the same 1152x648 reference space.
	for overlay_path in ["HUD/Root", "serveOverlay/Root", "pause/Root", "gameOver/Root"]:
		var root := get_node_or_null(overlay_path) as Control
		if root:
			Constants.configure_touch_root(root)


func _paddle_for_pointer(pos: Vector2) -> Area2D:
	if pos.y < Constants.HUD_HEIGHT:
		return null
	if GameState.serving:
		var server_is_left := GameState.server_is_left()
		if GameState.mode == Constants.MODE_ONLINE and not GameState.is_local_player_serving():
			return null
		if GameState.mode == Constants.MODE_AI and server_is_left != GameState.player_is_left:
			return null
		if GameState.mode == Constants.MODE_2P and ((pos.x < playfield_size.x * 0.5) != server_is_left):
			return null
		return paddle_left if server_is_left else paddle_right
	if GameState.mode == Constants.MODE_AI:
		return paddle_left if GameState.player_is_left else paddle_right
	if GameState.mode == Constants.MODE_ONLINE:
		return paddle_left if GameState.player_is_left else paddle_right
	return paddle_left if pos.x < playfield_size.x * 0.5 else paddle_right


func _handle_pointer_touch(pointer_id: int, pos: Vector2, pressed: bool) -> void:
	if pressed:
		var paddle := _paddle_for_pointer(pos)
		if paddle == null:
			return
		var offset := 0.0
		if pointer_id >= 0:
			offset = clampf(paddle.position.y - pos.y, -TOUCH_GRAB_SLACK, TOUCH_GRAB_SLACK)
		if paddle.begin_pointer(pointer_id, pos.y + offset):
			_pointer_paddles[pointer_id] = paddle
			_pointer_offsets[pointer_id] = offset
	else:
		_release_pointer(pointer_id)


func _handle_pointer_motion(pointer_id: int, pos: Vector2) -> void:
	var paddle: Area2D = _pointer_paddles.get(pointer_id)
	if paddle == null or not is_instance_valid(paddle):
		return
	var offset := float(_pointer_offsets.get(pointer_id, 0.0))
	# Fold the grab offset away at the walls so the paddle can always reach them.
	if pos.y + offset < paddle.top_limit:
		offset = minf(paddle.top_limit - pos.y, 0.0) if offset < 0.0 else offset
	elif pos.y + offset > paddle.bottom_limit:
		offset = maxf(paddle.bottom_limit - pos.y, 0.0) if offset > 0.0 else offset
	_pointer_offsets[pointer_id] = offset
	paddle.set_pointer_target(pos.y + offset, pointer_id)


func _release_pointer(pointer_id: int) -> void:
	var paddle: Area2D = _pointer_paddles.get(pointer_id)
	if paddle != null and is_instance_valid(paddle):
		paddle.release_pointer(pointer_id)
	_pointer_paddles.erase(pointer_id)
	_pointer_offsets.erase(pointer_id)


func _release_all_pointers() -> void:
	for pointer_id in _pointer_paddles.keys():
		_release_pointer(pointer_id)


func _on_paused_changed(paused: bool) -> void:
	if paused:
		_release_all_pointers()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_release_all_pointers()


func _on_mode_changed(_mode: int) -> void:
	if _mode == Constants.MODE_ONLINE:
		_reset_online_prediction()
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
	divider.visible = false
	center_line_ink.visible = on and not GameState.serving
	left_wash.visible = false
	right_wash.visible = false
	top_rail.visible = false
	bottom_rail.visible = false
	ink_rails.visible = on
	ball.visible = on
	paddle_left.visible = on
	paddle_right.visible = on
	var online := GameState.mode == Constants.MODE_ONLINE
	ball.set_physics_process(on and not online)
	paddle_left.set_physics_process(on and not online)
	paddle_right.set_physics_process(on and not online)
	# The ball stays clean and still; the old motion trail is intentionally disabled.
	trail.visible = false
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
	if GameState.mode == Constants.MODE_ONLINE:
		_smooth_online_state(_delta)
		_send_online_input()
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
	ParticleEffects.spawn_score(impact, color)
	GameState.add_point(side)


func _on_point_scored(_side: String) -> void:
	if GameState.mode == Constants.MODE_ONLINE:
		return
	ball.visible = false
	trail.visible = false
	trail.clear_points()
	await get_tree().create_timer(Constants.SCORE_HOLD).timeout
	if not is_instance_valid(self) or GameState.is_game_over or not GameState.mode_selected:
		return
	GameState.set_serving(true)
	ball.visible = true
	trail.visible = false


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
	var paddle_input: float = server.last_vy / maxf(server.speed, 1.0) if server.has_pointer_target() else server.get_move_input()
	return clampf(paddle_input * 0.85 + center_offset * 0.4, -1.0, 1.0)


func _update_playfield_size() -> void:
	playfield_size = get_viewport_rect().size
	var landscape := _window_is_landscape()
	if landscape != _last_landscape and GameState.mode_selected and not GameState.is_game_over:
		_release_all_pointers()
		if not landscape:
			_orientation_paused = not GameState.paused
			if _orientation_paused:
				GameState.toggle_pause()
		elif _orientation_paused and GameState.paused:
			_orientation_paused = false
			GameState.toggle_pause()
	_last_landscape = landscape
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
	if center_line_ink:
		center_line_ink.position = Vector2(playfield_size.x * 0.5, (Constants.HUD_HEIGHT + playfield_size.y) * 0.5)
		center_line_ink.scale = Vector2(1.0, maxf((playfield_size.y - Constants.HUD_HEIGHT - 24.0) / 560.0, 0.1))
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
	_refresh_touch_roots()


func _on_score_changed(left_score: int, right_score: int) -> void:
	if left_score == 0 and right_score == 0:
		return
	SFX.play_score()


func _on_colorblind_changed(_enabled: bool) -> void:
	left_wash.visible = false
	right_wash.visible = false


func _on_serving_changed(serving: bool) -> void:
	if GameState.mode == Constants.MODE_ONLINE:
		return
	if serving:
		ball.velocity = Vector2.ZERO
		ball.rally_hits = 0
		paddle_left.reset_size()
		paddle_right.reset_size()
		_on_rally_changed(0)
		divider.visible = false
		center_line_ink.visible = false
		ball.visible = GameState.mode_selected
	else:
		divider.visible = false
		center_line_ink.visible = GameState.mode_selected
		ball.launch(GameState.serve_toward_right, _serve_aim())


func _on_rally_changed(hits: int) -> void:
	paddle_left.apply_rally_size(hits)
	paddle_right.apply_rally_size(hits)


func _on_game_over(_winner: String) -> void:
	ScreenShake.reset()
	trail.clear_points()
	ball.velocity = Vector2.ZERO


func _send_online_input() -> void:
	if not NetworkManager.connection_is_open() or NetworkManager.state != NetworkManager.STATE_PLAYING:
		return
	var paddle := _local_paddle()
	# The client owns its paddle position; the server follows it under a speed cap.
	NetworkManager.send_input(float(paddle.get_move_input()), paddle.position.y)


func _local_side() -> String:
	return "left" if GameState.player_is_left else "right"


func _local_paddle() -> Area2D:
	return paddle_left if GameState.player_is_left else paddle_right


func _remote_paddle() -> Area2D:
	return paddle_right if GameState.player_is_left else paddle_left


func _online_now() -> float:
	return Time.get_ticks_usec() / 1000000.0


func _online_lead_rtt() -> float:
	return clampf(NetworkManager.rtt_seconds, 0.0, ONLINE_MAX_LEAD_RTT)


func _online_lead(now: float) -> float:
	return clampf(now - _online_snapshot_time, 0.0, ONLINE_MAX_SNAPSHOT_AGE) + _online_lead_rtt()


func _online_ball_in_play() -> bool:
	return not GameState.serving and not GameState.between_points and not GameState.is_game_over


func _reset_online_prediction() -> void:
	_online_snapshot_ready = false
	_ball_error = Vector2.ZERO
	_remote_error = 0.0
	_predicted_velocity = Vector2.ZERO
	_local_idle_time = 0.0
	_history_t.clear()
	_history_y.clear()
	_history_vy.clear()


func _on_online_snapshot(snapshot: Dictionary) -> void:
	if GameState.mode != Constants.MODE_ONLINE:
		return
	var now := _online_now()
	var had_snapshot := _online_snapshot_ready
	var was_in_play := _online_ball_in_play()
	var old_ball := Vector2.ZERO
	var old_remote := 0.0
	if had_snapshot:
		old_ball = _online_ball_position(now) + (_ball_error if was_in_play else Vector2.ZERO)
		old_remote = _remote_predicted_y(now) + _remote_error
	var previous_snapshot_time := _online_snapshot_time
	var previous_left := float(_snap_paddle_y["left"])
	var previous_right := float(_snap_paddle_y["right"])
	GameState.apply_online_snapshot(snapshot)
	var paddles = snapshot.get("paddles", {})
	if paddles is Dictionary:
		for side in ["left", "right"]:
			if paddles.has(side):
				_snap_paddle_y[side] = float(paddles.get(side))
	var paddle_velocities = snapshot.get("paddle_velocities", {})
	if paddle_velocities is Dictionary and paddle_velocities.has("left") and paddle_velocities.has("right"):
		_snap_paddle_vy["left"] = float(paddle_velocities.get("left"))
		_snap_paddle_vy["right"] = float(paddle_velocities.get("right"))
	elif had_snapshot:
		# Older hosted servers omit velocities; infer them from consecutive snapshots.
		var interval := maxf(now - previous_snapshot_time, 1.0 / 60.0)
		_snap_paddle_vy["left"] = (float(_snap_paddle_y["left"]) - previous_left) / interval
		_snap_paddle_vy["right"] = (float(_snap_paddle_y["right"]) - previous_right) / interval
	var ball_data = snapshot.get("ball", {})
	if ball_data is Dictionary:
		_snap_ball_pos = Vector2(float(ball_data.get("x", _snap_ball_pos.x)), float(ball_data.get("y", _snap_ball_pos.y)))
		_snap_ball_vel = Vector2(float(ball_data.get("vx", _snap_ball_vel.x)), float(ball_data.get("vy", _snap_ball_vel.y)))
	_snap_rally_hits = int(snapshot.get("rally_hits", _snap_rally_hits))
	_online_snapshot_time = now
	if not had_snapshot:
		paddle_left.position.y = float(_snap_paddle_y["left"])
		paddle_right.position.y = float(_snap_paddle_y["right"])
		_ball_error = Vector2.ZERO
		_remote_error = 0.0
		_online_snapshot_ready = true
	else:
		# Keep what is on screen continuous and fade the correction out instead.
		_ball_error = Vector2.ZERO
		if was_in_play and _online_ball_in_play():
			_ball_error = old_ball - _online_ball_position(now)
			if _ball_error.length() > ONLINE_SNAP_DISTANCE:
				_ball_error = Vector2.ZERO
		_remote_error = old_remote - _remote_predicted_y(now)
		if absf(_remote_error) > ONLINE_SNAP_DISTANCE:
			_remote_error = 0.0
	ball.visible = GameState.mode_selected and not GameState.is_game_over and not GameState.between_points
	paddle_left.visible = GameState.mode_selected and not GameState.is_game_over
	paddle_right.visible = GameState.mode_selected and not GameState.is_game_over
	center_line_ink.visible = _online_ball_in_play()


func _on_online_rematch_started() -> void:
	_reset_online_prediction()
	GameState.online_rematch_started()


func _smooth_online_state(delta: float) -> void:
	if not _online_snapshot_ready:
		return
	var now := _online_now()
	_update_local_online_paddle(delta, now)
	var decay := exp(-ONLINE_ERROR_DECAY * delta)
	_ball_error *= decay
	_remote_error *= decay
	var remote := _remote_paddle()
	remote.position.y = clampf(_remote_predicted_y(now) + _remote_error, remote.top_limit, remote.bottom_limit)
	if not _online_ball_in_play():
		ball.position = _online_ball_position(now)
		ball.velocity = Vector2.ZERO
		_predicted_velocity = Vector2.ZERO
		return
	var predicted := _predict_online_ball(now)
	ball.position = predicted["pos"] + _ball_error
	ball.velocity = predicted["vel"]
	ball.rally_hits = int(predicted["rally_hits"])
	_play_online_ball_feedback(ball.velocity, now)


func _update_local_online_paddle(delta: float, now: float) -> void:
	var paddle := _local_paddle()
	var before: float = paddle.position.y
	var y := before
	if paddle.has_pointer_target():
		y = move_toward(y, paddle._pointer_target_y, Constants.PADDLE_POINTER_SNAP_SPEED * delta)
	else:
		y += float(paddle.get_move_input()) * paddle.speed * delta
	y = clampf(y, paddle.top_limit, paddle.bottom_limit)
	if absf(y - before) > 0.001:
		_local_idle_time = 0.0
	else:
		_local_idle_time += delta
		# Only reconcile once the server has had time to see us standing still.
		if _local_idle_time > ONLINE_LOCAL_IDLE_RESYNC + _online_lead_rtt():
			var server_y := float(_snap_paddle_y[_local_side()])
			if absf(server_y - y) > 0.5:
				y = lerpf(y, server_y, 1.0 - exp(-ONLINE_LOCAL_RESYNC_RATE * delta))
	paddle.position.y = y
	paddle.previous_y = before
	paddle.last_vy = (y - before) / delta if delta > 0.0 else 0.0
	_history_t.append(now)
	_history_y.append(y)
	_history_vy.append(paddle.last_vy)
	var stale := 0
	while stale < _history_t.size() and _history_t[stale] < now - ONLINE_HISTORY_SECONDS:
		stale += 1
	if stale > 0:
		_history_t = _history_t.slice(stale)
		_history_y = _history_y.slice(stale)
		_history_vy = _history_vy.slice(stale)


func _predict_online_ball(now: float) -> Dictionary:
	return _online_predictor.advance(_snap_ball_pos, _snap_ball_vel, _snap_rally_hits, _online_lead(now), playfield_size, _sample_online_paddle)


func _online_ball_position(now: float) -> Vector2:
	if GameState.serving and not GameState.between_points and not GameState.is_game_over:
		# Keep the waiting ball glued to the serving paddle as it is drawn locally.
		var server_paddle: Area2D = paddle_left if GameState.serve_toward_right else paddle_right
		var direction := 1.0 if GameState.serve_toward_right else -1.0
		var server_y: float = server_paddle.position.y
		if server_paddle != _local_paddle():
			server_y = _remote_predicted_y(now) + _remote_error
		return Vector2(
			server_paddle.position.x + direction * (Constants.PADDLE_WIDTH * 0.5 + Constants.BALL_RADIUS + 6.0),
			server_y
		)
	if not _online_ball_in_play():
		return _snap_ball_pos
	return _predict_online_ball(now)["pos"]


func _sample_online_paddle(side: String, offset: float) -> Vector2:
	if side == _local_side():
		# The server applies our paddle one RTT after we drew it.
		return _local_paddle_at(_online_snapshot_time - _online_lead_rtt() + offset)
	var paddle: Area2D = paddle_left if side == "left" else paddle_right
	var vy := float(_snap_paddle_vy[side])
	var t := minf(offset, ONLINE_REMOTE_EXTRAPOLATION)
	var y := clampf(float(_snap_paddle_y[side]) + vy * t, paddle.top_limit, paddle.bottom_limit)
	return Vector2(y, vy if offset <= ONLINE_REMOTE_EXTRAPOLATION else 0.0)


func _remote_predicted_y(now: float) -> float:
	return _sample_online_paddle("right" if GameState.player_is_left else "left", _online_lead(now)).x


func _local_paddle_at(time: float) -> Vector2:
	var paddle := _local_paddle()
	var count := _history_t.size()
	if count == 0 or time >= _history_t[count - 1]:
		return Vector2(paddle.position.y, paddle.last_vy)
	for i in range(count - 2, -1, -1):
		if _history_t[i] <= time:
			var span := _history_t[i + 1] - _history_t[i]
			var weight := (time - _history_t[i]) / span if span > 0.0 else 1.0
			return Vector2(lerpf(_history_y[i], _history_y[i + 1], weight), _history_vy[i + 1])
	return Vector2(_history_y[0], _history_vy[0])


func _play_online_ball_feedback(velocity: Vector2, now: float) -> void:
	var previous := _predicted_velocity
	_predicted_velocity = velocity
	if previous == Vector2.ZERO or velocity == Vector2.ZERO:
		return
	var ratio := clampf((velocity.length() - Constants.START_SPEED) / (Constants.MAX_SPEED - Constants.START_SPEED), 0.0, 1.0)
	if signf(previous.x) != signf(velocity.x):
		var paddle: Area2D = paddle_left if velocity.x > 0.0 else paddle_right
		if absf(ball.position.x - paddle.position.x) > 120.0 or now - _last_hit_fx_time < ONLINE_FX_COOLDOWN:
			return
		_last_hit_fx_time = now
		SFX.play("paddle", 0.95 + ratio * 0.85)
		ParticleEffects.spawn_paddle_hit(ball.global_position, ball.ball_color)
		paddle.pulse()
	elif signf(previous.y) != signf(velocity.y) and absf(velocity.y) > 1.0:
		var near_top: bool = ball.position.y < Constants.HUD_HEIGHT + Constants.BALL_RADIUS + 40.0
		var near_bottom: bool = ball.position.y > playfield_size.y - 10.0 - Constants.BALL_RADIUS - 40.0
		if not (near_top or near_bottom) or now - _last_wall_fx_time < ONLINE_FX_COOLDOWN:
			return
		_last_wall_fx_time = now
		SFX.play("wall", 0.9 + ratio * 0.35)
		ParticleEffects.spawn_wall_bounce(ball.global_position)


func _on_online_match_cancelled() -> void:
	_reset_online_prediction()
	_set_match_visible(false)
