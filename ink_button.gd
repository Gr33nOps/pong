extends Panel
## Paper button with a slightly uneven ink outline.

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
	var ink := Color(0.08, 0.08, 0.075, 0.95 if selected else 0.58)
	var faint := Color(0.08, 0.08, 0.075, 0.32)
	var border_width := 2.1 if selected else 1.4
	var p := PackedVector2Array([
		Vector2(2, 3), Vector2(size.x * 0.28, 1), Vector2(size.x * 0.66, 2.5),
		Vector2(size.x - 2, 1.5), Vector2(size.x - 1, size.y - 3),
		Vector2(size.x * 0.68, size.y - 1), Vector2(size.x * 0.28, size.y - 2.5), Vector2(1, size.y - 1), Vector2(2, 3)
	])
	draw_polyline(p, ink, border_width, true)
	draw_line(Vector2(8, size.y - 7), Vector2(size.x - 10, size.y - 8), faint, 1.0, true)
	draw_line(Vector2(14, size.y - 5), Vector2(size.x * 0.45, size.y - 6), faint, 0.7, true)
