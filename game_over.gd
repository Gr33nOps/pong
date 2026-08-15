extends CanvasLayer

@onready var root = $Root
@onready var red_win_label = $Root/Card/red
@onready var blue_win_label = $Root/Card/blue
@onready var restart_hint = $Root/Card/restartHint
@onready var rally_label = $Root/Card/rallyRecord
@onready var final_score = $Root/Card/finalScore
@onready var card = $Root/Card

var _fade_tween: Tween = null
var menu_hint: Label


func _ready() -> void:
	visible = false
	layer = 40
	Constants.configure_touch_root(root)
	root.modulate = Color(1, 1, 1, 0)
	red_win_label.visible = false
	blue_win_label.visible = false
	GameState.game_over.connect(_on_game_over)
	GameState.colorblind_changed.connect(_apply_winner_colors)
	GameState.rematch_started.connect(_on_rematch_started)
	GameState.back_pressed.connect(_on_android_back)
	_make_menu_hint()
	_apply_winner_colors(GameState.colorblind_mode)
	restart_hint.mouse_filter = Control.MOUSE_FILTER_STOP
	restart_hint.gui_input.connect(_on_hint_gui.bind("rematch"))


func _make_menu_hint() -> void:
	menu_hint = Label.new()
	menu_hint.position = Vector2(20, 380)
	menu_hint.size = Vector2(540, 36)
	menu_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	menu_hint.add_theme_font_size_override("font_size", 14)
	menu_hint.add_theme_color_override("font_color", Color(0.82, 0.86, 0.9, 1))
	menu_hint.text = "TAP FOR MENU" if GameState.is_touch_ui() else "ESC MENU"
	menu_hint.mouse_filter = Control.MOUSE_FILTER_STOP
	menu_hint.gui_input.connect(_on_hint_gui.bind("menu"))
	card.add_child(menu_hint)
	restart_hint.text = "TAP TO REMATCH" if GameState.is_touch_ui() else "SPACE / ENTER REMATCH"
	restart_hint.position.y = 340.0


func _on_hint_gui(event: InputEvent, action: String) -> void:
	if not GameState.is_game_over:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if action == "rematch":
			_do_rematch()
		else:
			_do_menu()
	elif event is InputEventScreenTouch and event.pressed:
		if action == "rematch":
			_do_rematch()
		else:
			_do_menu()


func _process(_delta: float) -> void:
	if not GameState.is_game_over:
		return
	restart_hint.modulate.a = 0.55 + sin(Time.get_ticks_msec() * 0.006) * 0.45
	if Input.is_action_just_pressed("stop") or Input.is_action_just_pressed("ui_accept") or Players.is_confirm_just_pressed():
		_do_rematch()
	elif Input.is_action_just_pressed("ui_cancel"):
		_do_menu()


func _do_rematch() -> void:
	SFX.play("confirm")
	GameState.rematch()


func _do_menu() -> void:
	SFX.play("confirm")
	get_tree().reload_current_scene()


func _on_android_back() -> void:
	if GameState.is_game_over:
		_do_menu()


func _on_rematch_started() -> void:
	visible = false
	if _fade_tween:
		_fade_tween.kill()
	root.modulate.a = 0.0


func _on_game_over(winner: String) -> void:
	visible = true
	red_win_label.visible = winner == "red"
	blue_win_label.visible = winner == "blue"
	_apply_winner_colors(GameState.colorblind_mode)
	final_score.text = "%d  -  %d" % [GameState.left_score, GameState.right_score]
	rally_label.text = "RALLY %d     BEST %d" % [GameState.last_rally, GameState.longest_rally]
	SFX.play_win()
	_fade_in()


func _apply_winner_colors(_enabled: bool) -> void:
	if GameState.mode == Constants.MODE_AI:
		if GameState.player_is_left:
			blue_win_label.text = "YOU WIN"
			red_win_label.text = "CPU WINS"
		else:
			blue_win_label.text = "CPU WINS"
			red_win_label.text = "YOU WIN"
	elif GameState.player_is_left:
		blue_win_label.text = "P1 WINS"
		red_win_label.text = "P2 WINS"
	else:
		blue_win_label.text = "P2 WINS"
		red_win_label.text = "P1 WINS"
	blue_win_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	red_win_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))


func _fade_in() -> void:
	if _fade_tween:
		_fade_tween.kill()
	var winner_label = red_win_label if red_win_label.visible else blue_win_label
	winner_label.pivot_offset = Vector2(280, 40)
	winner_label.scale = Vector2(0.6, 0.6)
	_fade_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_fade_tween.set_parallel(true)
	_fade_tween.tween_property(root, "modulate:a", 1.0, Constants.GAME_OVER_FADE_IN).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_fade_tween.tween_property(winner_label, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
