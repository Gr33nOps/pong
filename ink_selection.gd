extends ColorRect
## Active navigation mark: a short, thick hand-drawn underline.

func _ready() -> void:
	color = Color(1, 1, 1, 0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()

func _draw() -> void:
	if size.x < 24.0 or size.y < 10.0:
		return
	var ink := Color(0.08, 0.08, 0.075, 0.94)
	var faint := Color(0.08, 0.08, 0.075, 0.22)
	var y := size.y - 7.0
	var line_width := clampf(size.x * 0.42, 110.0, 190.0)
	var left := (size.x - line_width) * 0.5
	var right := left + line_width
	var line := PackedVector2Array([
		Vector2(left, y + 1.0),
		Vector2(left + line_width * 0.24, y - 0.6),
		Vector2(left + line_width * 0.52, y + 0.7),
		Vector2(left + line_width * 0.76, y - 0.7),
		Vector2(right, y)
	])
	draw_polyline(line, ink, 2.6, true)
	var echo := PackedVector2Array([
		Vector2(left + 8.0, y + 4.0),
		Vector2(left + line_width * 0.36, y + 3.0),
		Vector2(left + line_width * 0.68, y + 3.6),
		Vector2(right - 8.0, y + 3.0)
	])
	draw_polyline(echo, faint, 0.95, true)
