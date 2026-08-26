extends Panel
## Paper button with a slightly uneven ink outline.

const InkGeometry = preload("res://ink_geometry.gd")

@export var selected := false:
	set(next):
		selected = next
		queue_redraw()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	var paper := StyleBoxFlat.new()
	paper.bg_color = Color(1, 1, 1, 0.96)
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
	if size.x < 12.0 or size.y < 12.0:
		return
	var ink := Color(0.08, 0.08, 0.075, 0.96 if selected else 0.48)
	var faint := Color(0.08, 0.08, 0.075, 0.3 if selected else 0.19)
	var border_width := 2.2 if selected else 1.35
	draw_polyline(InkGeometry.rough_rect(size, 3.0, 2.8, 0), ink, border_width, true)
	draw_polyline(InkGeometry.rough_rect(size, 5.0, 1.7, 1), faint, 0.8, true)
	draw_polyline(InkGeometry.top_scratch(size, 7.0, 1.8, 1), faint, 0.7, true)
