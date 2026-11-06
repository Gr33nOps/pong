extends Node2D
## Draws the match: paper background, court lines, paddles, ball, player names
## and the one-line hint. It never changes the game; it only shows a simulation.
##
## Your own wall is always turned to the bottom of the screen. When a player
## is knocked out, the old shape folds into the new one, and the last
## triangle shrinks away to reveal the line finale.

const ArenaSimulation = preload("res://scripts/arena_simulation.gd")
const CourtLines = preload("res://scripts/court_lines.gd")
const INK_THEME = preload("res://assets/ink_theme.tres")
const PAPER_TEXTURE = preload("res://assets/art/paper-court.png")
const PADDLE_TEXTURE = preload("res://assets/art/paddle-ink.png")
const BALL_TEXTURE = preload("res://assets/art/ball-ink.png")
const PADDLE_REGION := Rect2(555, 266, 144, 721)
const BALL_REGION := Rect2(535, 525, 184, 184)
const INK := Color(0.12, 0.12, 0.11, 1.0)

## Middle of the court on screen.
const CENTER := Vector2(576.0, 318.0)
const FOLD_SECONDS := 0.8
const LINE_PADDLE_LENGTH := 70.0

var lines: Node2D
var paddles: Array[Sprite2D] = []
var ball: Sprite2D
var name_labels: Array[Label] = []
var hint_label: Label

## How far the court is turned so your wall sits at the bottom.
var view_rotation := 0.0
## In the line finale: 1 if you are on the left end, -1 to flip you there.
var line_flip := 1.0
## 0..1 progress of the fold animation (1 = finished).
var fold_progress := 1.0
## 0..1 progress of the line finale appearing.
var line_reveal := 0.0
## Brief highlight on your hit zone after you swing.
var swing_flash := 0.0

var _fold_from := PackedVector2Array()
var _fold_removed_wall := -1


func _ready() -> void:
	var paper := TextureRect.new()
	paper.texture = PAPER_TEXTURE
	paper.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	paper.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	paper.size = Vector2(1152.0, 648.0)
	paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	paper.z_index = -10
	add_child(paper)

	lines = CourtLines.new()
	lines.corner_radius = ArenaSimulation.CORNER_RADIUS
	add_child(lines)

	for _seat in ArenaSimulation.MAX_PLAYERS:
		var paddle := _make_sprite(PADDLE_TEXTURE, PADDLE_REGION)
		paddle.z_index = 1
		paddles.append(paddle)
	ball = _make_sprite(BALL_TEXTURE, BALL_REGION)
	ball.scale = Vector2.ONE * (ArenaSimulation.BALL_RADIUS * 2.0 / BALL_REGION.size.x)
	ball.z_index = 2

	# Labels sit on their own layer above the menus' dimmed background.
	var layer := CanvasLayer.new()
	layer.layer = 25
	add_child(layer)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = INK_THEME
	layer.add_child(root)
	for _seat in ArenaSimulation.MAX_PLAYERS:
		var player_name := _make_label(20, Vector2(140.0, 28.0))
		root.add_child(player_name)
		name_labels.append(player_name)
	hint_label = _make_label(16, Vector2(800.0, 24.0))
	hint_label.position = Vector2(176.0, 612.0)
	root.add_child(hint_label)
	hide_match()


func _make_sprite(texture: Texture2D, region: Rect2) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.region_enabled = true
	sprite.region_rect = region
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.visible = false
	add_child(sprite)
	return sprite


func _make_label(font_size: int, label_size: Vector2) -> Label:
	var label := Label.new()
	label.size = label_size
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", INK)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


# --- menus --------------------------------------------------------------------

## Shows an empty court of the given size behind the menus.
func show_preview(players: int) -> void:
	var preview := ArenaSimulation.new()
	preview.reset_match(players)
	view_rotation = 0.0
	line_flip = 1.0
	line_reveal = 1.0
	fold_progress = 1.0
	_update_lines(preview, -1)
	hide_match()


func hide_match() -> void:
	for paddle in paddles:
		paddle.visible = false
	ball.visible = false
	for label in name_labels:
		label.visible = false
	hint_label.visible = false


# --- during a match -----------------------------------------------------------

func start_match(sim: ArenaSimulation) -> void:
	fold_progress = 1.0
	line_reveal = 1.0 if sim.is_line() else 0.0


## Remembers the shape that was on screen so it can fold one wall away.
func start_fold(sim: ArenaSimulation, order_before: Array, corners_before: PackedVector2Array) -> void:
	_fold_from = corners_before
	_fold_removed_wall = -1
	for wall in order_before.size():
		if not sim.order.has(order_before[wall]):
			_fold_removed_wall = wall
	fold_progress = 0.0
	if sim.is_line():
		line_reveal = 0.0


func is_folding() -> bool:
	return fold_progress < 1.0


## Draws one frame. paddle_position(seat) says where each paddle is along its
## wall (the online view's predictions).
func draw_match(sim: ArenaSimulation, my_seat: int, player_names: Array[String], ball_position: Vector2, paddle_position: Callable, hint: String, delta: float) -> void:
	_turn_view_to(sim, my_seat)
	swing_flash = maxf(swing_flash - delta * 4.0, 0.0)
	fold_progress = minf(fold_progress + delta / FOLD_SECONDS, 1.0)
	if sim.is_line():
		line_reveal = minf(line_reveal + delta / FOLD_SECONDS, 1.0)
	_update_lines(sim, my_seat)
	if sim.is_line():
		_place_line_paddles(sim)
	else:
		_place_polygon_paddles(sim, paddle_position)
	ball.position = to_screen(sim, ball_position)
	ball.visible = sim.state != ArenaSimulation.STATE_OVER and not is_folding()
	_place_labels(sim, player_names)
	hint_label.text = hint
	hint_label.visible = not hint.is_empty()


## Turns a point in court coordinates into a point on screen.
func to_screen(sim: ArenaSimulation, point: Vector2) -> Vector2:
	if sim.is_line():
		return CENTER + Vector2(point.x * line_flip, 0.0)
	return CENTER + point.rotated(view_rotation)


func corners_on_screen(walls: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	for index in walls:
		points.append(CENTER + ArenaSimulation.vertex(index, walls).rotated(view_rotation))
	return points


func flash_swing() -> void:
	swing_flash = 1.0


func _turn_view_to(sim: ArenaSimulation, my_seat: int) -> void:
	var my_wall := sim.wall_of(my_seat)
	if sim.is_line():
		line_flip = -1.0 if my_wall == 1 else 1.0
	else:
		view_rotation = -TAU * my_wall / sim.wall_count() if my_wall >= 0 else 0.0


func _update_lines(sim: ArenaSimulation, my_seat: int) -> void:
	if sim.is_line():
		_update_line_finale(sim, my_seat)
	else:
		lines.line_alpha = 0.0
		lines.polygon_alpha = 1.0
		var target := corners_on_screen(sim.wall_count())
		var can_fold := is_folding() and _fold_removed_wall >= 0 and _fold_from.size() == target.size() + 1
		lines.corners = _folded_corners(target) if can_fold else target
	lines.queue_redraw()


func _update_line_finale(sim: ArenaSimulation, my_seat: int) -> void:
	var half := ArenaSimulation.LINE_LENGTH * 0.5 * line_reveal
	lines.line_from = CENTER + Vector2(-half, 0.0)
	lines.line_to = CENTER + Vector2(half, 0.0)
	var left_seat := sim.order[0] if line_flip > 0.0 else sim.order[1]
	var right_seat := sim.order[1] if line_flip > 0.0 else sim.order[0]
	lines.line_zones = Vector2(sim.zone[left_seat], sim.zone[right_seat]) * line_reveal
	var mine_is_left := left_seat == my_seat
	lines.zone_flash = Vector2(swing_flash, 0.0) if mine_is_left else Vector2(0.0, swing_flash)
	lines.line_alpha = line_reveal
	# The last triangle shrinks into the middle while the line grows out.
	lines.polygon_alpha = 1.0 - line_reveal
	if lines.polygon_alpha > 0.01 and _fold_from.size() >= 3:
		var middle := Vector2.ZERO
		for point in _fold_from:
			middle += point
		middle /= _fold_from.size()
		var shrinking := PackedVector2Array()
		for point in _fold_from:
			shrinking.append(point.lerp(middle, line_reveal))
		lines.corners = shrinking


## Blends the old polygon into the new one: the two corners of the removed
## wall slide together until that wall disappears.
func _folded_corners(target: PackedVector2Array) -> PackedVector2Array:
	var eased := ease(fold_progress, -2.0)
	var points := PackedVector2Array()
	for index in _fold_from.size():
		var target_index := index - 1 if index > _fold_removed_wall else index
		points.append(_fold_from[index].lerp(target[posmod(target_index, target.size())], eased))
	return points


func _place_polygon_paddles(sim: ArenaSimulation, paddle_position: Callable) -> void:
	var walls := sim.wall_count()
	for wall in paddles.size():
		var paddle := paddles[wall]
		if wall >= walls or is_folding():
			paddle.visible = false
			continue
		var frame := ArenaSimulation.wall_frame(wall, walls)
		var along: float = paddle_position.call(sim.order[wall])
		var point: Vector2 = frame[0] + frame[1] * along + frame[2] * ArenaSimulation.PADDLE_INSET
		paddle.position = CENTER + point.rotated(view_rotation)
		paddle.rotation = frame[1].rotated(view_rotation).angle() - PI * 0.5
		paddle.scale = Vector2(ArenaSimulation.PADDLE_THICKNESS / PADDLE_REGION.size.x, ArenaSimulation.paddle_length(walls) / PADDLE_REGION.size.y)
		paddle.visible = true


func _place_line_paddles(sim: ArenaSimulation) -> void:
	for index in paddles.size():
		var paddle := paddles[index]
		if index >= 2:
			paddle.visible = false
			continue
		paddle.position = CENTER + Vector2(sim.line_end(sim.order[index]) * line_flip * line_reveal, 0.0)
		paddle.rotation = 0.0
		paddle.scale = Vector2(ArenaSimulation.PADDLE_THICKNESS / PADDLE_REGION.size.x, LINE_PADDLE_LENGTH / PADDLE_REGION.size.y)
		paddle.visible = line_reveal > 0.5


## Puts each player's name just outside their wall.
func _place_labels(sim: ArenaSimulation, player_names: Array[String]) -> void:
	for seat in name_labels.size():
		var player_name := name_labels[seat]
		var wall := sim.wall_of(seat) if seat < sim.seat_count else -1
		var shown := wall != -1 and not is_folding()
		player_name.visible = shown
		if not shown:
			continue
		var spot := Vector2.ZERO
		if sim.is_line():
			var side := -1.0 if sim.line_end(seat) * line_flip < 0.0 else 1.0
			spot = CENTER + Vector2(side * (ArenaSimulation.LINE_LENGTH * 0.5 + 70.0), 0.0)
		else:
			var walls := sim.wall_count()
			var wall_middle := (ArenaSimulation.vertex(wall, walls) + ArenaSimulation.vertex(wall + 1, walls)) * 0.5
			var outward := wall_middle.rotated(view_rotation)
			spot = CENTER + outward + outward.normalized() * 34.0
		player_name.text = player_names[seat] if seat < player_names.size() else ""
		player_name.position = spot - player_name.size * 0.5
