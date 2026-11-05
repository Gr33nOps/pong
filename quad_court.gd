extends Node2D
## Paper-and-ink square court. Live walls are faint goal lines; a knocked-out
## player's wall becomes a bold solid rule. Corner blocks are filled with ink.

const QuadSimulation = preload("res://quad_simulation.gd")
const InkGeometry = preload("res://ink_geometry.gd")
const INK := Color(0.08, 0.08, 0.075, 1.0)
const WOBBLE := [0.0, 0.7, -0.45, 0.55, -0.6, 0.35, 0.0]

var alive: Array[bool] = [true, true, true, true]


func set_alive(lives: Array) -> void:
	var changed := false
	for seat in QuadSimulation.SEATS:
		var next := int(lives[seat]) > 0
		if alive[seat] != next:
			alive[seat] = next
			changed = true
	if changed:
		queue_redraw()


func _ready() -> void:
	queue_redraw()


func _draw() -> void:
	var size := QuadSimulation.SIZE
	var corner := QuadSimulation.CORNER
	var walls := [
		[Vector2(0.0, corner), Vector2(0.0, size - corner)],
		[Vector2(size, corner), Vector2(size, size - corner)],
		[Vector2(corner, 0.0), Vector2(size - corner, 0.0)],
		[Vector2(corner, size), Vector2(size - corner, size)],
	]
	for seat in QuadSimulation.SEATS:
		var from: Vector2 = walls[seat][0]
		var to: Vector2 = walls[seat][1]
		if alive[seat]:
			draw_polyline(_rough_line(from, to, 1.6, seat), Color(INK, 0.3), 1.4, true)
		else:
			draw_polyline(_rough_line(from, to, 2.2, seat), Color(INK, 0.88), 4.0, true)
			draw_polyline(_rough_line(from, to, 1.4, seat + 2), Color(INK, 0.3), 1.2, true)
	var far := size - corner
	var block_index := 0
	for origin in [Vector2(0.0, 0.0), Vector2(far, 0.0), Vector2(0.0, far), Vector2(far, far)]:
		var outline := InkGeometry.rough_rect(Vector2(corner, corner), 1.5, 1.8, block_index)
		var shape := PackedVector2Array()
		for point in outline:
			shape.append(point + origin)
		draw_colored_polygon(shape, Color(INK, 0.82))
		draw_polyline(shape, Color(INK, 0.95), 1.6, true)
		block_index += 1
	draw_arc(Vector2(size * 0.5, size * 0.5), 7.0, 0.0, TAU, 20, Color(INK, 0.18), 1.2, true)


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
