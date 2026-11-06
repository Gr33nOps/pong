extends Node2D
## Paper-and-ink court for any number of sides, drawn in screen space. Walls
## are faint goal lines, the corners are ink bumpers, and the line finale shows
## each player's hit zone as a hatched band.

const INK := Color(0.08, 0.08, 0.075, 1.0)
const WOBBLE := [0.0, 0.7, -0.45, 0.55, -0.6, 0.35, 0.0]

## Screen-space corners of the polygon, in wall order.
var corners := PackedVector2Array()
var corner_radius := 20.0
var polygon_alpha := 1.0
## Line finale: screen-space ends and each end's hit-zone length (left, right).
var line_from := Vector2.ZERO
var line_to := Vector2.ZERO
var line_zones := Vector2.ZERO
var line_alpha := 0.0
## Briefly darkens a hit zone after a swing: x = left, y = right.
var zone_flash := Vector2.ZERO


func _draw() -> void:
	if polygon_alpha > 0.01 and corners.size() >= 3:
		_draw_polygon()
	if line_alpha > 0.01:
		_draw_line_court()


func _draw_polygon() -> void:
	var count := corners.size()
	var faint := Color(INK, 0.32 * polygon_alpha)
	for index in count:
		var from := corners[index]
		var to := corners[(index + 1) % count]
		if from.distance_to(to) < 1.0:
			continue
		draw_polyline(_rough_line(from, to, 1.6, index), faint, 1.5, true)
	var fill := Color(INK, 0.85 * polygon_alpha)
	for index in count:
		var center := corners[index]
		draw_circle(center, corner_radius, fill)
		draw_arc(center, corner_radius + 1.5, 0.0, TAU, 24, Color(INK, 0.35 * polygon_alpha), 1.0, true)
	var middle := Vector2.ZERO
	for point in corners:
		middle += point
	middle /= count
	draw_arc(middle, 7.0, 0.0, TAU, 20, Color(INK, 0.18 * polygon_alpha), 1.2, true)


func _draw_line_court() -> void:
	var ink := Color(INK, 0.75 * line_alpha)
	draw_polyline(_rough_line(line_from, line_to, 1.4, 1), ink, 2.0, true)
	var direction := (line_to - line_from).normalized()
	var normal := Vector2(-direction.y, direction.x)
	for end in 2:
		var tip := line_from if end == 0 else line_to
		var inward := direction if end == 0 else -direction
		var length := line_zones.x if end == 0 else line_zones.y
		var flash := zone_flash.x if end == 0 else zone_flash.y
		var band := PackedVector2Array([
			tip + normal * 14.0,
			tip + inward * length + normal * 14.0,
			tip + inward * length - normal * 14.0,
			tip - normal * 14.0,
		])
		draw_colored_polygon(band, Color(INK, (0.06 + 0.22 * flash) * line_alpha))
		var hatch := Color(INK, 0.28 * line_alpha)
		var step := 9.0
		var offset := 0.0
		while offset < length:
			var base := tip + inward * offset
			draw_line(base - normal * 12.0, base + inward * minf(8.0, length - offset) + normal * 12.0, hatch, 1.0, true)
			offset += step
		draw_polyline(band + PackedVector2Array([band[0]]), Color(INK, 0.55 * line_alpha), 1.2, true)
		draw_circle(tip, 6.0, Color(INK, 0.85 * line_alpha))


func _rough_line(from: Vector2, to: Vector2, wobble: float, variant: int) -> PackedVector2Array:
	var direction := to - from
	var normal := Vector2(-direction.y, direction.x).normalized()
	var points := PackedVector2Array()
	var count := WOBBLE.size()
	for i in count:
		var fraction := float(i) / float(count - 1)
		var offset: float = WOBBLE[(i + variant) % count] if i > 0 and i < count - 1 else 0.0
		points.append(from.lerp(to, fraction) + normal * offset * wobble)
	return points
