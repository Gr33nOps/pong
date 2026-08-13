extends Line2D
# Fading trail that follows the ball and matches its current color.

@export var ball_path: NodePath

@onready var ball: Area2D = get_node(ball_path)

var _last_color := Color(-1, -1, -1, -1)


func _ready() -> void:
	width = Constants.TRAIL_WIDTH
	begin_cap_mode = Line2D.LINE_CAP_ROUND
	end_cap_mode = Line2D.LINE_CAP_ROUND
	joint_mode = Line2D.LINE_JOINT_ROUND
	var taper := Curve.new()
	taper.add_point(Vector2(0.0, 0.25))
	taper.add_point(Vector2(1.0, 1.0))
	width_curve = taper
	gradient = Gradient.new()
	_apply_ball_color()


func _physics_process(_delta: float) -> void:
	if GameState.serving or GameState.is_game_over:
		clear_points()
		return
	if ball.ball_color != _last_color:
		_apply_ball_color()
	width = Constants.TRAIL_WIDTH * (1.0 + ball.speed_ratio() * 0.7)
	add_point(to_local(ball.global_position))
	if points.size() > Constants.MAX_TRAIL_POINTS:
		remove_point(0)


func _apply_ball_color() -> void:
	_last_color = ball.ball_color
	gradient.offsets = PackedFloat32Array([0.0, 1.0])
	gradient.colors = PackedColorArray([Color(_last_color, 0.0), Color(_last_color, 0.85)])
