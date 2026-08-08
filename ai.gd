extends Node
# Simple AI opponent for the right paddle. Only active in "vs AI" mode.

@export var paddle_path: NodePath
@export var ball_path: NodePath

@onready var paddle: Area2D = get_node(paddle_path)
@onready var ball: Area2D = get_node(ball_path)

var speed := 480.0
var center_y := 0.0


func _ready() -> void:
	center_y = get_viewport().get_visible_rect().size.y * 0.5


func _physics_process(delta: float) -> void:
	if GameState.mode != GameState.MODE_AI:
		return
	if GameState.serving or GameState.is_game_over:
		return
	var target_y := ball.position.y if ball.velocity.x > 0.0 else center_y
	var move := clampf(target_y - paddle.position.y, -speed * delta, speed * delta)
	paddle.position.y += move
