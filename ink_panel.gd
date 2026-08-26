extends Panel
## Small imperfect ink border drawn over UI cards and option boxes.

const InkGeometry = preload("res://ink_geometry.gd")

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var paper := StyleBoxFlat.new()
	paper.bg_color = Color(1.0, 1.0, 1.0, 1.0)
	paper.border_width_left = 0
	paper.border_width_top = 0
	paper.border_width_right = 0
	paper.border_width_bottom = 0
	paper.corner_radius_top_left = 0
	paper.corner_radius_top_right = 0
	paper.corner_radius_bottom_left = 0
	paper.corner_radius_bottom_right = 0
	add_theme_stylebox_override("panel", paper)
	queue_redraw()

func _draw() -> void:
	if size.x < 8.0 or size.y < 8.0:
		return
	var ink := Color(0.08, 0.08, 0.075, 0.86)
	var faint := Color(0.08, 0.08, 0.075, 0.24)
	var wobble := 3.4 if minf(size.x, size.y) > 160.0 else 2.4
	draw_polyline(InkGeometry.rough_rect(size, 4.0, wobble, 0), ink, 1.65, true)
	draw_polyline(InkGeometry.rough_rect(size, 6.0, wobble * 0.62, 1), faint, 0.85, true)
	draw_polyline(InkGeometry.top_scratch(size, 7.0, wobble * 0.8, 1), faint, 0.75, true)
