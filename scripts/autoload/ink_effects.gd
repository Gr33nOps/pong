extends Node
## Small ink splats for hits and points. Each one is a sprite that grows a
## little and fades out, then removes itself.

const PADDLE_SPLAT: Texture2D = preload("res://assets/art/impact-paddle-ink.svg")
const WALL_SPLAT: Texture2D = preload("res://assets/art/impact-wall-ink.svg")
const POINT_SPLAT: Texture2D = preload("res://assets/art/impact-score-ink.svg")


func paddle_hit(where: Vector2) -> void:
	_splat(where, PADDLE_SPLAT, 0.42, 0.24)


func wall_hit(where: Vector2) -> void:
	_splat(where, WALL_SPLAT, 0.32, 0.20)


func point_lost(where: Vector2) -> void:
	_splat(where, POINT_SPLAT, 0.58, 0.36)


func _splat(where: Vector2, texture: Texture2D, size: float, lifetime: float) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var screen := get_viewport().get_visible_rect().size
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	sprite.modulate = Color(0.12, 0.12, 0.11, 0.82)
	sprite.scale = Vector2.ONE * size * 0.72
	sprite.z_index = 5
	sprite.position = Vector2(clampf(where.x, 28.0, screen.x - 28.0), clampf(where.y, 22.0, screen.y - 22.0))
	scene.add_child(sprite)
	var tween := sprite.create_tween().set_parallel(true)
	tween.tween_property(sprite, "scale", Vector2.ONE * size, lifetime * 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(sprite, "modulate:a", 0.0, lifetime).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(sprite.queue_free)
