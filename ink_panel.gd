extends Panel
## Small imperfect ink border drawn over UI cards and option boxes.

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var paper := StyleBoxFlat.new()
	paper.bg_color = Color(1.0, 1.0, 1.0, 0.96)
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
	if size.x < 8.0 or size.y < 8.0:
		return
	var ink := Color(0.08, 0.08, 0.075, 0.9)
	var faint := Color(0.08, 0.08, 0.075, 0.28)
	var r := Rect2(Vector2(2.0, 2.0), size - Vector2(4.0, 4.0))
	var top := PackedVector2Array([Vector2(r.position.x, r.position.y + 1.0), Vector2(size.x * 0.35, r.position.y - 1.0), Vector2(size.x * 0.72, r.position.y + 1.5), Vector2(r.end.x, r.position.y - 0.5)])
	var bottom := PackedVector2Array([Vector2(r.position.x, r.end.y - 1.0), Vector2(size.x * 0.38, r.end.y + 0.5), Vector2(size.x * 0.74, r.end.y - 1.5), Vector2(r.end.x, r.end.y + 0.5)])
	draw_polyline(top, ink, 1.4, true)
	draw_polyline(bottom, ink, 1.4, true)
	draw_line(Vector2(r.position.x - 0.5, r.position.y), Vector2(r.position.x + 1.0, r.end.y), ink, 1.3, true)
	draw_line(Vector2(r.end.x + 0.5, r.position.y), Vector2(r.end.x - 1.0, r.end.y), ink, 1.3, true)
	draw_line(Vector2(r.position.x + 5.0, r.position.y + 3.0), Vector2(r.end.x - 4.0, r.position.y + 2.0), faint, 0.8, true)
