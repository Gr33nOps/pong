extends Node2D

@onready var panel = $PanelContainer
@onready var resume_label = $resumeHint
@onready var restart_label = $restartHint
@onready var quit_label = $quitHint
@onready var volume_label = $volumeHint
@onready var master_label = $masterHint
@onready var difficulty_label = $difficultyHint
@onready var colorblind_label = $colorblindHint

var _cursor := 0
var _fade_tween: Tween = null
const OPTIONS := ["Resume", "Restart", "Quit", "SFX", "Master", "Difficulty", "Colorblind"]


func _ready() -> void:
	visible = false
	panel.visible = false
	modulate = Color(1, 1, 1, 0)
	panel.modulate = Color(1, 1, 1, 0)
	GameState.paused_changed.connect(_on_paused_changed)
	_update_hints()


func _process(_delta: float) -> void:
	if GameState.serving or GameState.is_game_over:
		return
	if Input.is_action_just_pressed("ui_cancel") or Players.is_pause_just_pressed():
		GameState.toggle_pause()
		return
	if not GameState.paused:
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
		_cursor = (_cursor + nav + OPTIONS.size()) % OPTIONS.size()
		_update_hints()

	if Input.is_action_just_pressed("stop") or Players.is_confirm_just_pressed():
		_select_option()

	if _cursor == 3 or _cursor == 4:
		var held := 0
		if Input.is_action_pressed("ui_right"):
			held = 1
		elif Input.is_action_pressed("ui_left"):
			held = -1
		if held != 0:
			_adjust_option(held)
	else:
		var tapped := 0
		if Input.is_action_just_pressed("ui_right"):
			tapped = 1
		elif Input.is_action_just_pressed("ui_left"):
			tapped = -1
		if tapped != 0:
			_adjust_option(tapped)


func _on_paused_changed(paused: bool) -> void:
	if paused:
		visible = true
		panel.visible = true
		_cursor = 0
		_update_hints()
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


func _select_option() -> void:
	match _cursor:
		0:
			GameState.toggle_pause()
		1:
			get_tree().reload_current_scene()
		2:
			get_tree().quit()
		6:
			GameState.toggle_colorblind()
			_update_hints()


func _adjust_option(direction: int) -> void:
	match _cursor:
		3:
			SFX.set_sfx_volume(SFX.sfx_volume + 0.02 * direction)
			_update_hints()
		4:
			SFX.set_master_volume(SFX.master_volume + 0.02 * direction)
			_update_hints()
		5:
			var steps := [Constants.DIFFICULTY_EASY, Constants.DIFFICULTY_NORMAL, Constants.DIFFICULTY_HARD]
			var index := _difficulty_index() + direction
			index = clampi(index, 0, steps.size() - 1)
			GameState.set_ai_difficulty(steps[index])
			_update_hints()
		6:
			if direction != 0:
				GameState.toggle_colorblind()
				_update_hints()


func _difficulty_index() -> int:
	if GameState.ai_difficulty <= 0.75:
		return 0
	if GameState.ai_difficulty >= 1.25:
		return 2
	return 1


func _update_hints() -> void:
	var dim := Color(0.55, 0.55, 0.55, 1)
	var lit := Color(1, 1, 1, 1)
	var labels := [
		resume_label, restart_label, quit_label, volume_label,
		master_label, difficulty_label, colorblind_label
	]
	var texts := [
		"Resume",
		"Restart",
		"Quit to Desktop",
		"SFX Volume: %d%%" % int(SFX.sfx_volume * 100),
		"Master Volume: %d%%" % int(SFX.master_volume * 100),
		"AI Difficulty: %s" % GameState.difficulty_label(),
		"Colorblind: %s" % ("On" if GameState.colorblind_mode else "Off"),
	]
	for i in labels.size():
		var prefix := "> " if _cursor == i else "  "
		labels[i].text = prefix + texts[i]
		labels[i].add_theme_color_override("font_color", lit if _cursor == i else dim)
