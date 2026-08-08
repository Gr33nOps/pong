extends Line2D
# Fading trail that follows the ball and matches its current color.

const MAX_POINTS := 28

@export var ball_path: NodePath

@onready var ball: Area2D = get_node(ball_path)

var _last_color := Color(-1, -1, -1, -1)


func _ready() -> void:
	width = 6.0
	begin_cap_mode = Line2D.LINE_CAP_ROUND
	end_cap_mode = Line2D.LINE_CAP_ROUND
	joint_mode = Line2D.LINE_JOINT_ROUND
	gradient = Gradient.new()
	_apply_ball_color()


func _physics_process(_delta: float) -> void:
	if GameState.serving or GameState.is_game_over:
		clear_points()
		return
	if ball.ball_color != _last_color:
		_apply_ball_color()
	add_point(ball.global_position)
	if points.size() > MAX_POINTS:
		remove_point(0)


func _apply_ball_color() -> void:
	_last_color = ball.ball_color
	gradient.offsets = PackedFloat32Array([0.0, 1.0])
	gradient.colors = PackedColorArray([Color(_last_color, 0.0), Color(_last_color, 0.7)])
