extends Panel
## Transparent layout surface for paper-and-ink overlays.
## The overlay dimmer supplies the opaque paper field; this surface adds no card box.

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var paper := StyleBoxFlat.new()
	paper.bg_color = Color(1.0, 1.0, 1.0, 0.0)
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
	# Deliberately empty. Cards are represented by spacing, typography, and ink rules.
	pass
