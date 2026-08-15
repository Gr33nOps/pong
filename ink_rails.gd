extends Node2D
## Uneven ink rule at the bottom edge of the paper court.

func _ready() -> void:
	z_index = 0
	get_viewport().size_changed.connect(queue_redraw)
	queue_redraw()

func _draw() -> void:
	var size := get_viewport_rect().size
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var ink := Color(0.08, 0.08, 0.075, 0.62)
	var faint := Color(0.08, 0.08, 0.075, 0.24)
	var rule := PackedVector2Array([
		Vector2(18, size.y - 8), Vector2(size.x * 0.20, size.y - 8.8),
		Vector2(size.x * 0.42, size.y - 7.4), Vector2(size.x * 0.65, size.y - 8.6),
		Vector2(size.x * 0.84, size.y - 7.8), Vector2(size.x - 20, size.y - 9)
	])
	draw_polyline(rule, ink, 1.8, true)
	var wear := PackedVector2Array([
		Vector2(24, size.y - 5), Vector2(size.x * 0.30, size.y - 5.8),
		Vector2(size.x * 0.58, size.y - 4.7), Vector2(size.x * 0.82, size.y - 5.8), Vector2(size.x - 18, size.y - 6)
	])
	draw_polyline(wear, faint, 0.8, true)
