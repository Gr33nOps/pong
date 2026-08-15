extends Control
## Hand-drawn rules framing the HUD and keeping the court separate from the paper header.

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()

func _draw() -> void:
	var ink := Color(0.08, 0.08, 0.075, 0.72)
	var faint := Color(0.08, 0.08, 0.075, 0.28)
	var w := size.x
	var top := PackedVector2Array([
		Vector2(0, 2.5), Vector2(w * 0.18, 1.4), Vector2(w * 0.34, 1.8),
		Vector2(w * 0.52, 2.8), Vector2(w * 0.70, 1.6), Vector2(w * 0.86, 2.2), Vector2(w, 1.2)
	])
	draw_polyline(top, ink, 2.2, true)
	var top_wear := PackedVector2Array([
		Vector2(w * 0.08, 4.0), Vector2(w * 0.27, 3.2), Vector2(w * 0.45, 4.1),
		Vector2(w * 0.66, 3.0), Vector2(w * 0.88, 3.6)
	])
	draw_polyline(top_wear, faint, 0.8, true)
	var separator := PackedVector2Array([
		Vector2(16, 72.0), Vector2(w * 0.24, 71.4), Vector2(w * 0.48, 72.5),
		Vector2(w * 0.73, 71.3), Vector2(w - 16, 72.1)
	])
	draw_polyline(separator, ink, 1.5, true)
	var separator_wear := PackedVector2Array([
		Vector2(20, 75.0), Vector2(w * 0.32, 74.2), Vector2(w * 0.63, 75.0), Vector2(w - 22, 74.1)
	])
	draw_polyline(separator_wear, faint, 0.75, true)
