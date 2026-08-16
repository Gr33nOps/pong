extends CanvasLayer

@onready var root = $Root
@onready var red_win_label = $Root/Card/red
@onready var blue_win_label = $Root/Card/blue
@onready var restart_hint = $Root/Card/restartHint
@onready var rally_label = $Root/Card/rallyRecord
@onready var final_score = $Root/Card/finalScore
@onready var card = $Root/Card
@onready var rematch_button: Panel = $Root/Card/RematchButton
@onready var menu_button: Panel = $Root/Card/MenuButton

var _fade_tween: Tween = null
var menu_hint: Label
var _cursor := 0


func _ready() -> void:
	visible = false
	layer = 40
	Constants.configure_touch_root(root)
	root.modulate = Color(1, 1, 1, 0)
	red_win_label.visible = false
	blue_win_label.visible = false
	GameState.game_over.connect(_on_game_over)
	GameState.rematch_started.connect(_on_rematch_started)
	GameState.back_pressed.connect(_on_android_back)
	_make_menu_hint()
	_set_cursor(0)
	_apply_winner_colors(false)
	restart_hint.mouse_filter = Control.MOUSE_FILTER_STOP
	restart_hint.gui_input.connect(_on_hint_gui.bind("rematch"))
	restart_hint.mouse_entered.connect(_focus_button.bind(true))
	menu_hint.mouse_entered.connect(_focus_button.bind(false))


func _focus_button(rematch: bool) -> void:
	if not GameState.is_game_over:
		return
	_set_cursor(0 if rematch else 1)


func _set_cursor(index: int) -> void:
	_cursor = clampi(index, 0, 1)
	rematch_button.set("selected", _cursor == 0)
	menu_button.set("selected", _cursor == 1)


func _activate_cursor() -> void:
	if _cursor == 0:
		_do_rematch()
	else:
		_do_menu()


func _make_menu_hint() -> void:
	menu_hint = Label.new()
	menu_hint.position = Vector2(20, 380)
	menu_hint.size = Vector2(540, 36)
	menu_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	menu_hint.add_theme_font_size_override("font_size", 18)
	menu_hint.add_theme_color_override("font_color", Color(0.12, 0.12, 0.11, 1))
	_update_control_hints()
	menu_hint.mouse_filter = Control.MOUSE_FILTER_STOP
	menu_hint.gui_input.connect(_on_hint_gui.bind("menu"))
	card.add_child(menu_hint)
	restart_hint.position.y = 308.0
	menu_hint.position.y = 354.0


func _update_control_hints() -> void:
	if GameState.is_touch_ui():
		menu_hint.text = "TAP FOR MENU"
		restart_hint.text = "TAP TO REMATCH"
	elif GameState.is_controller_ui():
		menu_hint.text = "B MENU"
		restart_hint.text = "A REMATCH"
	else:
		menu_hint.text = "ESC MENU"
		restart_hint.text = "SPACE / ENTER REMATCH"


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
	restart_hint.modulate.a = 1.0
	if Players.is_nav_up_just_pressed():
		_set_cursor(0)
	elif Players.is_nav_down_just_pressed():
		_set_cursor(1)
	elif Players.is_confirm_just_pressed():
		_activate_cursor()
	elif Players.is_pause_just_pressed():
		_do_menu()


func _input(event: InputEvent) -> void:
	if not GameState.is_game_over or not event is InputEventKey:
		return
	if not event.pressed or event.echo:
		return
	if event.physical_keycode == KEY_UP or event.physical_keycode == KEY_W:
		get_viewport().set_input_as_handled()
		_set_cursor(0)
	elif event.physical_keycode == KEY_DOWN or event.physical_keycode == KEY_S:
		get_viewport().set_input_as_handled()
		_set_cursor(1)
	elif event.physical_keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_do_menu()
	elif event.physical_keycode == KEY_SPACE or event.physical_keycode == KEY_ENTER or event.physical_keycode == KEY_KP_ENTER:
		get_viewport().set_input_as_handled()
		_activate_cursor()


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
	_update_control_hints()
	_set_cursor(0)
	red_win_label.visible = winner == "red"
	blue_win_label.visible = winner == "blue"
	_apply_winner_colors(false)
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
	blue_win_label.add_theme_color_override("font_color", Color(0.12, 0.12, 0.11, 1))
	red_win_label.add_theme_color_override("font_color", Color(0.12, 0.12, 0.11, 1))


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
