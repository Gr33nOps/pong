extends ColorRect
## Active pause-row mark: ink underline and a hand-drawn pointer instead of a gray fill bar.

func _ready() -> void:
	color = Color(1, 1, 1, 0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()

func _draw() -> void:
	var ink := Color(0.08, 0.08, 0.075, 0.82)
	var faint := Color(0.08, 0.08, 0.075, 0.28)
	var p := PackedVector2Array([
		Vector2(3, 2), Vector2(size.x * 0.32, 1), Vector2(size.x * 0.7, 2.5),
		Vector2(size.x - 3, 1.5), Vector2(size.x - 2, size.y - 3),
		Vector2(size.x * 0.7, size.y - 1), Vector2(size.x * 0.32, size.y - 2), Vector2(3, size.y - 1), Vector2(3, 2)
	])
	draw_polyline(p, ink, 1.8, true)
	draw_line(Vector2(12, size.y - 6), Vector2(size.x - 12, size.y - 7), faint, 0.8, true)
