extends Panel
## Ink-and-paper slider: rough rule, hatch marks, and a drawn knob.

var value := 1.0:
	set(next):
		value = clampf(next, 0.0, 1.0)
		queue_redraw()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()

func _draw() -> void:
	var ink := Color(0.08, 0.08, 0.075, 0.9)
	var faint := Color(0.08, 0.08, 0.075, 0.28)
	var y := size.y * 0.5
	draw_line(Vector2(0, y), Vector2(size.x, y + 1), ink, 2.0, true)
	for x in range(8, int(size.x), 18):
		draw_line(Vector2(x, y - 3), Vector2(x + 4, y + 3), faint, 1.0, true)
	var knob_x := clampf(value * size.x, 5.0, maxf(size.x - 5.0, 5.0))
	var knob := PackedVector2Array([
		Vector2(knob_x - 6, y - 8), Vector2(knob_x + 4, y - 7),
		Vector2(knob_x + 6, y + 7), Vector2(knob_x - 5, y + 8)
	])
	draw_colored_polygon(knob, ink)
	draw_line(Vector2(knob_x - 3, y - 5), Vector2(knob_x + 2, y + 5), Color(1, 1, 1, 0.55), 1.0, true)
