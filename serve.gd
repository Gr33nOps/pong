extends Node2D
# Start screen with mode select (Player vs AI / Player vs Player) and the
# between-points "serve" prompt.

@onready var title_label = $title
@onready var option1_label = $option1
@onready var option2_label = $option2
@onready var hint_label = $hint
@onready var devices_label = $devices

var cursor := 0


func _ready() -> void:
	visible = false
	$PanelContainer.visible = false
	GameState.serving_changed.connect(_on_serving_changed)
	GameState.game_over.connect(_on_game_over)
	GameState.mode_changed.connect(_on_mode_changed)
	Players.player_assigned.connect(_on_devices_changed)
	Players.player_released.connect(_on_devices_changed)
	_update_devices_label()


func _process(_delta: float) -> void:
	if not GameState.serving or GameState.is_game_over:
		return
	if GameState.mode_selected:
		if Input.is_action_just_pressed("stop") or Players.is_confirm_just_pressed():
			GameState.set_serving(false)
		return
	_handle_menu_input()


func _handle_menu_input() -> void:
	if Input.is_action_just_pressed("mode_1"):
		GameState.select_mode(GameState.MODE_AI)
		return
	if Input.is_action_just_pressed("mode_2"):
		GameState.select_mode(GameState.MODE_2P)
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
		GameState.select_mode(GameState.MODE_AI if cursor == 0 else GameState.MODE_2P)
		GameState.set_serving(false)


func _on_serving_changed(serving: bool) -> void:
	visible = serving
	$PanelContainer.visible = serving
	if serving:
		_refresh()


func _on_mode_changed(_mode: int) -> void:
	_refresh()


func _on_game_over(_winner: String) -> void:
	visible = false
	$PanelContainer.visible = false


func _on_devices_changed(_player: int, _device: int) -> void:
	_update_devices_label()


func _refresh() -> void:
	var in_menu := not GameState.mode_selected
	title_label.visible = in_menu
	option1_label.visible = in_menu
	option2_label.visible = in_menu
	if in_menu:
		cursor = 0
		hint_label.text = "Use W/S or Arrows to pick  -  Space/A to confirm"
		_update_menu_highlight()
	else:
		hint_label.text = "Press Space Or A To Serve"
	hint_label.visible = true
	devices_label.visible = true


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
