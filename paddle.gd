extends Area2D

@export var is_left := true

var speed := Constants.PADDLE_SPEED
var top_limit := 0.0
var bottom_limit := 0.0
var last_vy := 0.0
var _playfield_h := 648.0


func _ready() -> void:
	monitoring = false
	monitorable = false
	$ColorRect.color = GameState.get_p1_color() if is_left else GameState.get_p2_color()
	_playfield_h = get_viewport_rect().size.y
	_refresh_limits()
	GameState.colorblind_changed.connect(_on_colorblind_changed)


func half_height() -> float:
	return Constants.HALF_HEIGHT * scale.y


func get_move_input() -> float:
	var player := Players.PLAYER_1 if is_left else Players.PLAYER_2
	var keyboard := Input.get_axis("up", "down") if is_left else Input.get_axis("up2", "down2")
	return clampf(keyboard + Players.get_axis(player), -1.0, 1.0)


func apply_rally_size(hits: int) -> void:
	var extra := maxi(hits - Constants.PADDLE_SHRINK_START, 0)
	scale.y = maxf(Constants.PADDLE_MIN_SCALE, 1.0 - extra * 0.05)
	_refresh_limits()
	position.y = clampf(position.y, top_limit, bottom_limit)


func reset_size() -> void:
	scale.y = 1.0
	_refresh_limits()


func set_playfield_height(height: float) -> void:
	_playfield_h = height
	_refresh_limits()


func _refresh_limits() -> void:
	top_limit = half_height()
	bottom_limit = _playfield_h - half_height()


func _physics_process(delta: float) -> void:
	if GameState.serving and not GameState.mode_selected:
		last_vy = 0.0
		return
	var player_controlled := is_left or GameState.mode == Constants.MODE_2P
	if not player_controlled:
		return
	var before := position.y
	position.y += get_move_input() * speed * delta
	position.y = clampf(position.y, top_limit, bottom_limit)
	last_vy = (position.y - before) / delta if delta > 0.0 else 0.0


func _on_colorblind_changed(_enabled: bool) -> void:
	$ColorRect.color = GameState.get_p1_color() if is_left else GameState.get_p2_color()
