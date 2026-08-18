extends ColorRect
## Active navigation mark: a hand-drawn underline instead of a selection box.

func _ready() -> void:
	color = Color(1, 1, 1, 0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()

func _draw() -> void:
	if size.x < 24.0 or size.y < 10.0:
		return
	var ink := Color(0.08, 0.08, 0.075, 0.9)
	var faint := Color(0.08, 0.08, 0.075, 0.18)
	var y := size.y - 7.0
	var line := PackedVector2Array([
		Vector2(26.0, y + 1.0),
		Vector2(size.x * 0.24, y - 0.6),
		Vector2(size.x * 0.5, y + 0.7),
		Vector2(size.x * 0.76, y - 0.7),
		Vector2(size.x - 26.0, y)
	])
	draw_polyline(line, ink, 2.0, true)
	var echo := PackedVector2Array([
		Vector2(36.0, y + 4.0),
		Vector2(size.x * 0.38, y + 3.0),
		Vector2(size.x * 0.68, y + 3.6),
		Vector2(size.x - 36.0, y + 3.0)
	])
	draw_polyline(echo, faint, 0.8, true)
