extends Control
## Loading animation: an ink polygon that slowly turns and gains a side every
## half second (triangle up to decagon), with a ball running around it.

const INK := Color(0.12, 0.12, 0.11, 1.0)
const RADIUS := 44.0
const SECONDS_PER_SHAPE := 0.55

var _time := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	if is_visible_in_tree():
		_time += delta
		queue_redraw()


func _draw() -> void:
	var middle := size * 0.5
	var sides := 3 + int(_time / SECONDS_PER_SHAPE) % 8
	var turn := _time * 0.6
	var corners := PackedVector2Array()
	for index in sides + 1:
		corners.append(middle + Vector2.from_angle(turn + TAU * index / sides - PI * 0.5) * RADIUS)
	draw_polyline(corners, INK, 3.0, true)
	# The ball goes once around the shape while it has this many sides.
	var along := fmod(_time / SECONDS_PER_SHAPE, 1.0) * sides
	var side := int(along)
	draw_circle(corners[side].lerp(corners[side + 1], along - side), 6.0, INK)
