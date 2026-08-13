extends Node2D
# Start screen with mode select (Player vs AI / Player vs Player) and the
# between-points "serve" prompt.

@onready var title_label = $title
@onready var option1_label = $option1
@onready var option2_label = $option2
@onready var hint_label = $hint
@onready var devices_label = $devices
@onready var panel = $PanelContainer

var cursor := 0
var _fade_tween: Tween = null
var _ai_serve_timer := 0.0


func _ready() -> void:
	visible = false
	panel.visible = false
	modulate = Color(1, 1, 1, 0)
	panel.modulate = Color(1, 1, 1, 0)
	GameState.serving_changed.connect(_on_serving_changed)
	GameState.game_over.connect(_on_game_over)
	GameState.mode_changed.connect(_on_mode_changed)
	Players.player_assigned.connect(_on_player_assigned)
	Players.player_released.connect(_on_player_released)
	_update_devices_label()


func _process(delta: float) -> void:
	if not GameState.serving or GameState.is_game_over:
		return
	if GameState.mode_selected:
		_handle_serve_input(delta)
		return
	_handle_menu_input()


func _handle_menu_input() -> void:
	if Input.is_action_just_pressed("mode_1"):
		GameState.select_mode(Constants.MODE_AI)
		return
	if Input.is_action_just_pressed("mode_2"):
		GameState.select_mode(Constants.MODE_2P)
		return
	if Input.is_action_just_pressed("colorblind"):
		GameState.toggle_colorblind()
		SFX.play("paddle")
		return
	var nav := 0
	if Input.is_action_just_pressed("up") or Input.is_action_just_pressed("ui_up"):
		nav = -1
	elif Input.is_action_just_pressed("down") or Input.is_action_just_pressed("ui_down"):
		nav = 1
	elif Players.is_nav_up_just_pressed():
		nav = -1
	elif Players.is_nav_down_just_pressed():
		nav = 1
	if nav != 0:
		cursor = (cursor + nav + 2) % 2
		_update_menu_highlight()
	if Input.is_action_just_pressed("stop") or Players.is_confirm_just_pressed():
		GameState.select_mode(Constants.MODE_AI if cursor == 0 else Constants.MODE_2P)


func _handle_serve_input(delta: float) -> void:
	var ai_serving: bool = GameState.mode == Constants.MODE_AI and not GameState.serve_toward_right
	if ai_serving:
		_ai_serve_timer += delta
		if _ai_serve_timer >= 0.85:
			GameState.set_serving(false)
		return
	if Input.is_action_just_pressed("stop") or Players.is_confirm_just_pressed():
		GameState.set_serving(false)


func _on_serving_changed(serving: bool) -> void:
	_ai_serve_timer = 0.0
	if serving:
		visible = true
		_refresh()
		_fade_in()
	else:
		_fade_out()


func _fade_in() -> void:
	if _fade_tween:
		_fade_tween.kill()
	_fade_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).set_parallel(true)
	_fade_tween.tween_property(self, "modulate:a", 1.0, Constants.MENU_FADE_IN).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_fade_tween.tween_property(panel, "modulate:a", 1.0, Constants.MENU_FADE_IN).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _fade_out() -> void:
	if _fade_tween:
		_fade_tween.kill()
	_fade_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).set_parallel(true)
	_fade_tween.tween_property(self, "modulate:a", 0.0, Constants.MENU_FADE_IN).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_fade_tween.tween_property(panel, "modulate:a", 0.0, Constants.MENU_FADE_IN).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_fade_tween.finished.connect(_on_fade_out_done)


func _on_fade_out_done() -> void:
	visible = false
	panel.visible = false


func _on_mode_changed(_mode: int) -> void:
	_refresh()


func _on_game_over(_winner: String) -> void:
	visible = false
	panel.visible = false


func _on_player_assigned(_player: int, _device: int) -> void:
	_update_devices_label()


func _on_player_released(_player: int) -> void:
	_update_devices_label()


func _refresh() -> void:
	var in_menu := not GameState.mode_selected
	title_label.visible = in_menu
	option1_label.visible = in_menu
	option2_label.visible = in_menu
	panel.visible = in_menu
	if in_menu:
		cursor = 0
		hint_label.text = "W/S or Arrows to pick  -  Space/A to confirm\n1/2 for a mode  -  C colorblind  -  ESC pauses in play"
		_update_menu_highlight()
		devices_label.visible = true
	else:
		devices_label.visible = false
		if GameState.mode == Constants.MODE_AI and not GameState.serve_toward_right:
			hint_label.text = "AI serving..."
		elif GameState.serve_toward_right:
			hint_label.text = "P1 serve  -  Aim with W/S  -  Space to launch"
		else:
			hint_label.text = "P2 serve  -  Aim with Arrows  -  Space to launch"
	hint_label.visible = true


func _update_menu_highlight() -> void:
	var selected_color := Color(1, 1, 1, 1)
	var dim_color := Color(0.55, 0.55, 0.55, 1)
	option1_label.text = "> Player vs AI" if cursor == 0 else "  Player vs AI"
	option2_label.text = "> Player vs Player" if cursor == 1 else "  Player vs Player"
	option1_label.add_theme_color_override("font_color", selected_color if cursor == 0 else dim_color)
	option2_label.add_theme_color_override("font_color", selected_color if cursor == 1 else dim_color)


func _update_devices_label() -> void:
	var p1 := _device_text(Players.PLAYER_1)
	var p2 := _device_text(Players.PLAYER_2)
	devices_label.text = "P1: %s          P2: %s" % [p1, p2]


func _device_text(player: int) -> String:
	var device := Players.get_device(player)
	return "Pad %d" % (device + 1) if device >= 0 else "Keyboard"
