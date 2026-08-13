extends Node2D

@onready var red_win_label = $red
@onready var blue_win_label = $blue
@onready var panel = $PanelContainer
@onready var gameover_label = $gameover
@onready var restart_hint = $restartHint
@onready var rally_label = $rallyRecord

var _fade_tween: Tween = null


func _ready() -> void:
	visible = false
	panel.visible = false
	modulate = Color(1, 1, 1, 0)
	panel.modulate = Color(1, 1, 1, 0)
	red_win_label.visible = false
	blue_win_label.visible = false
	GameState.game_over.connect(_on_game_over)
	GameState.colorblind_changed.connect(_apply_winner_colors)
	_apply_winner_colors(GameState.colorblind_mode)


func _process(_delta: float) -> void:
	if GameState.is_game_over and (Input.is_action_just_pressed("stop") or Players.is_confirm_just_pressed()):
		get_tree().reload_current_scene()


func _on_game_over(winner: String) -> void:
	visible = true
	panel.visible = true
	red_win_label.visible = winner == "red"
	blue_win_label.visible = winner == "blue"
	_apply_winner_colors(GameState.colorblind_mode)
	rally_label.text = "Longest Rally: %d" % GameState.longest_rally
	SFX.play("win")
	_fade_in()


func _apply_winner_colors(_enabled: bool) -> void:
	blue_win_label.text = "P1 WINS!"
	red_win_label.text = "P2 WINS!"
	blue_win_label.add_theme_color_override("font_color", GameState.get_p1_color())
	red_win_label.add_theme_color_override("font_color", GameState.get_p2_color())


func _fade_in() -> void:
	if _fade_tween:
		_fade_tween.kill()
	_fade_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).set_parallel(true)
	_fade_tween.tween_property(self, "modulate:a", 1.0, Constants.GAME_OVER_FADE_IN).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_fade_tween.tween_property(panel, "modulate:a", 1.0, Constants.GAME_OVER_FADE_IN).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	var winner_label = red_win_label if red_win_label.visible else blue_win_label
	winner_label.scale = Vector2(0.5, 0.5)
	_fade_tween.tween_property(winner_label, "scale", Vector2(1.2, 1.2), 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_fade_tween.tween_property(winner_label, "scale", Vector2(1.0, 1.0), 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
