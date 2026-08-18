extends Panel
## Transparent paper control with a rough hand-drawn navigation underline.

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
	if size.x < 24.0 or size.y < 12.0:
		return
	var ink := Color(0.08, 0.08, 0.075, 0.92 if selected else 0.34)
	var faint := Color(0.08, 0.08, 0.075, 0.18 if selected else 0.10)
	var y := size.y - (9.0 if selected else 8.0)
	var left := 30.0
	var right := size.x - 30.0
	var underline := PackedVector2Array([
		Vector2(left, y + 1.0),
		Vector2(size.x * 0.24, y - 0.4),
		Vector2(size.x * 0.48, y + 0.8),
		Vector2(size.x * 0.73, y - 0.8),
		Vector2(right, y)
	])
	draw_polyline(underline, ink, 2.2 if selected else 1.05, true)
	if selected:
		var second := PackedVector2Array([
			Vector2(left + 10.0, y + 4.0),
			Vector2(size.x * 0.35, y + 3.0),
			Vector2(size.x * 0.66, y + 3.8),
			Vector2(right - 8.0, y + 3.1)
		])
		draw_polyline(second, faint, 0.85, true)
