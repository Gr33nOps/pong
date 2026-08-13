extends Area2D

@export var is_left := true

var speed := Constants.PADDLE_SPEED
var top_limit := 0.0
var bottom_limit := 0.0
var last_vy := 0.0
var _playfield_h := 648.0
var _pulse_tween: Tween = null
var _size_tween: Tween = null


func _ready() -> void:
	monitoring = false
	monitorable = false
	_playfield_h = get_viewport_rect().size.y
	_refresh_limits()
	_apply_color()
	GameState.colorblind_changed.connect(_on_colorblind_changed)


func half_height() -> float:
	return Constants.HALF_HEIGHT * scale.y


func _uses_p1_controls() -> bool:
	return is_left == GameState.player_is_left


func is_human() -> bool:
	if GameState.mode == Constants.MODE_2P:
		return true
	return _uses_p1_controls()


func get_move_input() -> float:
	if not is_human():
		return 0.0
	if GameState.mode == Constants.MODE_AI:
		var keyboard := Input.get_axis("up", "down") + Input.get_axis("up2", "down2")
		var pad := Players.get_axis(Players.PLAYER_1) + Players.get_axis(Players.PLAYER_2)
		return clampf(keyboard + pad, -1.0, 1.0)
	var use_p1 := _uses_p1_controls()
	var player := Players.PLAYER_1 if use_p1 else Players.PLAYER_2
	var keyboard := Input.get_axis("up", "down") if use_p1 else Input.get_axis("up2", "down2")
	return clampf(keyboard + Players.get_axis(player), -1.0, 1.0)


func apply_rally_size(hits: int) -> void:
	var extra := maxi(hits - Constants.PADDLE_SHRINK_START, 0)
	var target := maxf(Constants.PADDLE_MIN_SCALE, 1.0 - extra * 0.05)
	if is_equal_approx(scale.y, target):
		return
	if _size_tween:
		_size_tween.kill()
	_size_tween = create_tween()
	_size_tween.tween_property(self, "scale:y", target, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_size_tween.tween_callback(_refresh_limits)
	_size_tween.tween_callback(func() -> void:
		position.y = clampf(position.y, top_limit, bottom_limit)
	)


func reset_size() -> void:
	if _size_tween:
		_size_tween.kill()
	if _pulse_tween:
		_pulse_tween.kill()
	scale = Vector2.ONE
	_refresh_limits()


func set_playfield_height(height: float) -> void:
	_playfield_h = height
	_refresh_limits()


func pulse() -> void:
	if _pulse_tween:
		_pulse_tween.kill()
	var keep_y := scale.y
	scale.x = 1.35
	_pulse_tween = create_tween()
	_pulse_tween.tween_property(self, "scale:x", 1.0, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	scale.y = keep_y


func _refresh_limits() -> void:
	top_limit = Constants.HUD_HEIGHT + half_height()
	bottom_limit = _playfield_h - 12.0 - half_height()


func _physics_process(delta: float) -> void:
	if GameState.serving and not GameState.mode_selected:
		last_vy = 0.0
		return
	if not is_human():
		return
	var before := position.y
	position.y += get_move_input() * speed * delta
	position.y = clampf(position.y, top_limit, bottom_limit)
	last_vy = (position.y - before) / delta if delta > 0.0 else 0.0


func _apply_color() -> void:
	$ColorRect.color = GameState.get_p1_color() if is_left else GameState.get_p2_color()


func _on_colorblind_changed(_enabled: bool) -> void:
	_apply_color()
