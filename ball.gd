extends Area2D

const BALL_RADIUS := 21.0
const START_SPEED := 400.0
const MAX_SPEED := 1200.0
const SPEED_INCREMENT := 1.05
const MAX_BOUNCE_ANGLE_DEG := 60.0
const PADDLE_HALF_HEIGHT := 107.0
const COLOR_P1 := Color(0, 1, 1, 1)
const COLOR_P2 := Color(1, 0, 0, 1)

var velocity := Vector2.ZERO
var ball_color := COLOR_P1

var _playfield_size := Vector2.ZERO


func _ready() -> void:
	_playfield_size = get_viewport_rect().size


func launch() -> void:
	var direction := -1.0 if randf() < 0.5 else 1.0
	velocity = Vector2(START_SPEED * direction, 0.0)


func reset_color() -> void:
	ball_color = COLOR_P1


func _physics_process(delta: float) -> void:
	position += velocity * delta

	if position.y - BALL_RADIUS < 0.0:
		position.y = BALL_RADIUS
		velocity.y = absf(velocity.y)
		SFX.play("wall")
	elif position.y + BALL_RADIUS > _playfield_size.y:
		position.y = _playfield_size.y - BALL_RADIUS
		velocity.y = -absf(velocity.y)
		SFX.play("wall")


func _on_area_entered(area: Area2D) -> void:
	if not area.is_in_group("paddles"):
		return
	var current_speed := velocity.length()
	velocity.x = -velocity.x

	var hit_offset := (position.y - area.position.y) / PADDLE_HALF_HEIGHT
	hit_offset = clampf(hit_offset, -1.0, 1.0)
	velocity.y = current_speed * tan(deg_to_rad(MAX_BOUNCE_ANGLE_DEG)) * hit_offset

	velocity = velocity.normalized() * current_speed * SPEED_INCREMENT
	velocity = velocity.limit_length(MAX_SPEED)
	ball_color = COLOR_P1 if area.is_left else COLOR_P2
	SFX.play("paddle")
