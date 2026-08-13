extends Line2D
# Motion line that follows the ball.

@export var ball_path: NodePath

@onready var ball: Area2D = get_node(ball_path)

var _last_color := Color(-1, -1, -1, -1)


func _ready() -> void:
	z_index = 1
	width = Constants.TRAIL_WIDTH
	begin_cap_mode = Line2D.LINE_CAP_ROUND
	end_cap_mode = Line2D.LINE_CAP_ROUND
	joint_mode = Line2D.LINE_JOINT_ROUND
	antialiased = true
	var taper := Curve.new()
	taper.add_point(Vector2(0.0, 0.2))
	taper.add_point(Vector2(1.0, 1.0))
	width_curve = taper
	gradient = Gradient.new()
	_apply_ball_color()


func _process(_delta: float) -> void:
	if not visible or not GameState.mode_selected or GameState.serving or GameState.is_game_over:
		if get_point_count() > 0:
			clear_points()
		return
	if not is_instance_valid(ball):
		return
	if ball.ball_color != _last_color:
		_apply_ball_color()
	width = Constants.TRAIL_WIDTH * (1.0 + ball.speed_ratio() * 0.3)
	var pos := ball.position
	pos.x = clampf(pos.x, 8.0, get_viewport_rect().size.x - 8.0)
	pos.y = clampf(pos.y, Constants.HUD_HEIGHT + 8.0, get_viewport_rect().size.y - 8.0)
	add_point(pos)
	while get_point_count() > Constants.MAX_TRAIL_POINTS:
		remove_point(0)


func _apply_ball_color() -> void:
	_last_color = ball.ball_color
	default_color = Color(_last_color, 0.7)
	gradient.offsets = PackedFloat32Array([0.0, 1.0])
	gradient.colors = PackedColorArray([
		Color(_last_color, 0.0),
		Color(_last_color, 0.75),
	])
