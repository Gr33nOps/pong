extends Node2D

@onready var red_win_label = $red
@onready var blue_win_label = $blue


func _ready() -> void:
	visible = false
	red_win_label.visible = false
	blue_win_label.visible = false
	GameState.game_over.connect(_on_game_over)


func _process(_delta: float) -> void:
	if GameState.is_game_over and (Input.is_action_just_pressed("stop") or Players.is_confirm_just_pressed()):
		get_tree().reload_current_scene()


func _on_game_over(winner: String) -> void:
	visible = true
	red_win_label.visible = winner == "red"
	blue_win_label.visible = winner == "blue"
	SFX.play("win")
