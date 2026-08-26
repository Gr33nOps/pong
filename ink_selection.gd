extends ColorRect
## Active pause-row mark: ink underline and a hand-drawn pointer instead of a gray fill bar.

const InkGeometry = preload("res://ink_geometry.gd")

func _ready() -> void:
	color = Color(1, 1, 1, 0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()

func _draw() -> void:
	var ink := Color(0.08, 0.08, 0.075, 0.82)
	var faint := Color(0.08, 0.08, 0.075, 0.28)
	draw_polyline(InkGeometry.rough_rect(size, 3.0, 2.5, 0), ink, 1.9, true)
	draw_polyline(InkGeometry.rough_rect(size, 5.0, 1.5, 1), faint, 0.75, true)
