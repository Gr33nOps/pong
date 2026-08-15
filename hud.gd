extends CanvasLayer
# Single scoreboard in a dedicated HUD band. No duplicate court scores.

@onready var p1_name: Label = $Root/P1Name
@onready var p2_name: Label = $Root/P2Name
@onready var p1_score: Label = $Root/P1Score
@onready var p2_score: Label = $Root/P2Score

var _tweens: Dictionary = {}
var pause_hit: Panel
var pause_label: Label


func _ready() -> void:
	layer = 8
	Constants.configure_touch_root($Root)
	GameState.score_changed.connect(_on_score_changed)
	GameState.mode_changed.connect(_on_mode_changed)
	GameState.serving_changed.connect(_on_serving_changed)
	GameState.game_over.connect(_on_game_over)
	_apply_colors(false)
	_refresh_names()
	_on_score_changed(GameState.left_score, GameState.right_score)
	visible = false
	_make_pause_button()


func _make_pause_button() -> void:
	pause_hit = Panel.new()
	pause_hit.set_script(preload("res://ink_button.gd"))
	pause_hit.size = Vector2(68.0, 38.0)
	pause_hit.mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1.0, 1.0, 1.0, 0.94)
	pause_hit.add_theme_stylebox_override("panel", style)
	pause_label = Label.new()
	pause_label.size = Vector2(68.0, 30.0)
	pause_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pause_label.text = "PAUSE"
	pause_label.add_theme_font_size_override("font_size", 16)
	pause_label.add_theme_color_override("font_color", Color(0.08, 0.08, 0.075, 1.0))
	pause_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$Root.add_child(pause_hit)
	$Root.add_child(pause_label)
	pause_hit.gui_input.connect(_on_pause_gui)
	get_viewport().size_changed.connect(_layout_pause_button)
	get_viewport().size_changed.connect(_layout_scoreboard)
	_layout_pause_button()
	_layout_scoreboard()


func _layout_pause_button() -> void:
	if pause_hit == null or pause_label == null:
		return
	var viewport_width := get_viewport().get_visible_rect().size.x
	var x := maxf(16.0, viewport_width * 0.5 - 34.0)
	pause_hit.position = Vector2(x, 17.0)
	pause_label.position = Vector2(x, 21.0)


func _layout_scoreboard() -> void:
	var viewport_width := get_viewport().get_visible_rect().size.x
	# Keep equal 48px paper margins on both sides at every viewport width.
	p1_score.position = Vector2(48.0, 10.0)
	p2_score.position = Vector2(maxf(48.0, viewport_width - 48.0 - p2_score.size.x), 10.0)


func _on_pause_gui(event: InputEvent) -> void:
	if not visible or GameState.is_game_over or not GameState.mode_selected:
		return
	if _is_tap(event):
		SFX.play("ui")
		GameState.toggle_pause()


func _is_tap(event: InputEvent) -> bool:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		return true
	if event is InputEventScreenTouch and event.pressed:
		return true
	return false


func bind_ball(_ball: Node) -> void:
	# Rally remains a gameplay mechanic, but its counter is intentionally not shown in the HUD.
	return


func _on_score_changed(left_score: int, right_score: int) -> void:
	var left_changed := p1_score.text != str(left_score)
	var right_changed := p2_score.text != str(right_score)
	p1_score.text = str(left_score)
	p2_score.text = str(right_score)
	if left_score == 0 and right_score == 0:
		return
	if left_changed:
		_punch(p1_score, "p1")
	if right_changed:
		_punch(p2_score, "p2")


func _on_mode_changed(_mode: int) -> void:
	visible = true
	_refresh_names()
	if pause_hit:
		pause_hit.visible = true
		pause_label.visible = true


func _on_serving_changed(_serving: bool) -> void:
	if not GameState.mode_selected:
		visible = false


func _on_game_over(_winner: String) -> void:
	pass


func _refresh_names() -> void:
	if GameState.mode == Constants.MODE_AI and GameState.mode_selected:
		if GameState.player_is_left:
			p1_name.text = "YOU"
			p2_name.text = "CPU"
		else:
			p1_name.text = "CPU"
			p2_name.text = "YOU"
	else:
		if GameState.player_is_left:
			p1_name.text = "P1"
			p2_name.text = "P2"
		else:
			p1_name.text = "P2"
			p2_name.text = "P1"
	_apply_colors(false)


func _apply_colors(_enabled: bool) -> void:
	var p1 := GameState.get_p1_color()
	var p2 := GameState.get_p2_color()
	p1_name.add_theme_color_override("font_color", p1)
	p2_name.add_theme_color_override("font_color", p2)
	p1_score.add_theme_color_override("font_color", p1)
	p2_score.add_theme_color_override("font_color", p2)


func _punch(label: Control, key: String) -> void:
	if _tweens.has(key) and _tweens[key]:
		_tweens[key].kill()
	label.pivot_offset = label.size * 0.5
	label.scale = Vector2(1.16, 1.16)
	var tw := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(label, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tweens[key] = tw
