extends Panel
## Transparent paper control with a short, rough hand-drawn navigation underline.

@export var selected := false:
	set(next):
		selected = next
		queue_redraw()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	var paper := StyleBoxFlat.new()
	paper.bg_color = Color(1, 1, 1, 0.0)
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
	if not selected or size.x < 24.0 or size.y < 12.0:
		return
	var ink := Color(0.08, 0.08, 0.075, 0.94)
	var faint := Color(0.08, 0.08, 0.075, 0.22)
	var y := size.y - 9.0
	var line_width := clampf(size.x * 0.42, 110.0, 190.0)
	var left := (size.x - line_width) * 0.5
	var right := left + line_width
	var underline := PackedVector2Array([
		Vector2(left, y + 1.0),
		Vector2(left + line_width * 0.24, y - 0.5),
		Vector2(left + line_width * 0.52, y + 0.8),
		Vector2(left + line_width * 0.76, y - 0.8),
		Vector2(right, y)
	])
	draw_polyline(underline, ink, 2.8, true)
	var second := PackedVector2Array([
		Vector2(left + 8.0, y + 4.0),
		Vector2(left + line_width * 0.34, y + 3.0),
		Vector2(left + line_width * 0.67, y + 3.8),
		Vector2(right - 8.0, y + 3.1)
	])
	draw_polyline(second, faint, 1.0, true)
