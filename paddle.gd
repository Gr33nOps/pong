extends Area2D

const PADDLE_HEIGHT := 214.0
const HALF_HEIGHT := PADDLE_HEIGHT / 2.0

const COLOR_P1 := Color(0, 1, 1, 1)
const COLOR_P2 := Color(1, 0, 0, 1)

@export var is_left := true

var speed := 500.0
var top_limit := 0.0
var bottom_limit := 0.0


func _ready() -> void:
	$ColorRect.color = COLOR_P1 if is_left else COLOR_P2
	var screen_height := get_viewport_rect().size.y
	top_limit = HALF_HEIGHT
	bottom_limit = screen_height - HALF_HEIGHT


func _physics_process(delta: float) -> void:
	if is_left or GameState.mode == GameState.MODE_2P:
		position.y += _move_input() * speed * delta
	position.y = clampf(position.y, top_limit, bottom_limit)


func _move_input() -> float:
	var player := Players.PLAYER_1 if is_left else Players.PLAYER_2
	var keyboard := Input.get_axis("up", "down") if is_left else Input.get_axis("up2", "down2")
	return clampf(keyboard + Players.get_axis(player), -1.0, 1.0)
