extends Node
# Brief ink stamps. CPU particles were intentionally removed so Web and
# mobile builds do not spend frames simulating effects during a rally.

const INK_PADDLE_HIT: Texture2D = preload("res://art/impact-paddle-ink.svg")
const INK_WALL_HIT: Texture2D = preload("res://art/impact-wall-ink.svg")
const INK_SCORE: Texture2D = preload("res://art/impact-score-ink.svg")


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ink_burst(world_position: Vector2, texture: Texture2D, size: float, lifetime: float = 0.28) -> void:
	if not GameState.mode_selected:
		return
	var scene := get_tree().current_scene
	if scene == null:
		return
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	sprite.modulate = Color(0.12, 0.12, 0.11, 0.82)
	sprite.scale = Vector2(size * 0.72, size * 0.72)
	sprite.z_index = 5
	world_position.x = clampf(world_position.x, 28.0, get_viewport().get_visible_rect().size.x - 28.0)
	world_position.y = clampf(world_position.y, Constants.HUD_HEIGHT + 22.0, get_viewport().get_visible_rect().size.y - 22.0)
	sprite.global_position = world_position
	scene.add_child(sprite)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(sprite, "scale", Vector2(size, size), lifetime * 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(sprite, "modulate:a", 0.0, lifetime).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(sprite.queue_free)


func spawn_paddle_hit(world_position: Vector2, _color: Color) -> void:
	_ink_burst(world_position, INK_PADDLE_HIT, 0.42, 0.24)


func spawn_wall_bounce(world_position: Vector2) -> void:
	_ink_burst(world_position, INK_WALL_HIT, 0.32, 0.20)


func spawn_score(world_position: Vector2, _color: Color = Color(1, 1, 1, 1)) -> void:
	_ink_burst(world_position, INK_SCORE, 0.58, 0.36)
