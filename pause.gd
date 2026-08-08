extends Node2D

func _ready() -> void:
	visible = false
	$PanelContainer.visible = false
	GameState.paused_changed.connect(_on_paused_changed)


func _process(_delta: float) -> void:
	if GameState.serving or GameState.is_game_over:
		return
	if Input.is_action_just_pressed("ui_cancel") or Players.is_pause_just_pressed():
		GameState.toggle_pause()


func _on_paused_changed(paused: bool) -> void:
	visible = paused
	$PanelContainer.visible = paused
