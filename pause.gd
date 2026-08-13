extends CanvasLayer

@onready var root = $Root
@onready var cursor_bar = $Root/Card/Cursor
@onready var resume_label = $Root/Card/resumeHint
@onready var restart_label = $Root/Card/restartHint
@onready var quit_label = $Root/Card/quitHint
@onready var volume_label = $Root/Card/volumeHint
@onready var master_label = $Root/Card/masterHint
@onready var difficulty_label = $Root/Card/difficultyHint
@onready var colorblind_label = $Root/Card/colorblindHint
@onready var sfx_fill = $Root/Card/SfxFill
@onready var master_fill = $Root/Card/MasterFill
@onready var sfx_knob = $Root/Card/SfxKnob
@onready var master_knob = $Root/Card/MasterKnob
@onready var master_pct = $Root/Card/masterPct
@onready var sfx_pct = $Root/Card/sfxPct
@onready var audio_header = $Root/Card/audioHeader
@onready var game_header = $Root/Card/gameHeader
@onready var pause_hint = $Root/Card/pauseHint

var _cursor := 0
var _fade_tween: Tween = null
var menu_label: Label
const BAR_X := 188.0
const BAR_W := 204.0
const KNOB_W := 8.0


func _ready() -> void:
	visible = false
	layer = 30
	root.modulate = Color(1, 1, 1, 0)
	_ensure_menu_label()
	GameState.paused_changed.connect(_on_paused_changed)
	_update_hints()


func _ensure_menu_label() -> void:
	menu_label = Label.new()
	menu_label.name = "menuHint"
	menu_label.position = Vector2(40, 162)
	menu_label.size = Vector2(444, 26)
	menu_label.add_theme_font_size_override("font_size", 16)
	menu_label.text = "MAIN MENU"
	$Root/Card.add_child(menu_label)
	quit_label.visible = false


func _ids() -> Array[String]:
	var ids: Array[String] = ["resume", "rematch", "menu", "master", "sfx"]
	if GameState.mode == Constants.MODE_AI:
		ids.append("difficulty")
	ids.append("colorblind")
	return ids


func _label_for(id: String) -> Label:
	match id:
		"resume":
			return resume_label
		"rematch":
			return restart_label
		"menu":
			return menu_label
		"quit":
			return quit_label
		"master":
			return master_label
		"sfx":
			return volume_label
		"difficulty":
			return difficulty_label
		"colorblind":
			return colorblind_label
	return resume_label


func _process(_delta: float) -> void:
	if GameState.is_game_over:
		return
	if GameState.serving and not GameState.mode_selected:
		return
	if Input.is_action_just_pressed("ui_cancel") or Players.is_pause_just_pressed():
		GameState.toggle_pause()
		return
	if not GameState.paused:
		return

	var ids := _ids()
	_cursor = clampi(_cursor, 0, ids.size() - 1)
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
		_cursor = (_cursor + nav + ids.size()) % ids.size()
		SFX.play("ui")
		_update_hints()

	if Input.is_action_just_pressed("stop") or Input.is_action_just_pressed("ui_accept") or Players.is_confirm_just_pressed():
		_select_option()

	var id: String = ids[_cursor]
	if id == "master" or id == "sfx":
		var held := _held_dir()
		if held != 0:
			_adjust_option(held)
	else:
		var tapped := 0
		if Input.is_action_just_pressed("ui_left"):
			tapped = -1
		elif Input.is_action_just_pressed("ui_right"):
			tapped = 1
		if tapped != 0:
			_adjust_option(tapped)


func _held_dir() -> int:
	if Input.is_action_pressed("ui_left") or Input.is_physical_key_pressed(KEY_A):
		return -1
	if Input.is_action_pressed("ui_right") or Input.is_physical_key_pressed(KEY_D):
		return 1
	return 0


func _input(event: InputEvent) -> void:
	if not GameState.paused or GameState.is_game_over:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_Q:
		if not OS.has_feature("web"):
			get_tree().quit()
			return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_on_pause_click($Root/Card.get_local_mouse_position())
	elif event is InputEventScreenTouch and event.pressed:
		var canvas: Transform2D = $Root/Card.get_global_transform_with_canvas()
		_on_pause_click(canvas.affine_inverse() * event.position)


func _on_pause_click(local: Vector2) -> void:
	var card: Control = $Root/Card
	var ids := _ids()
	for i in ids.size():
		var lab := _label_for(ids[i])
		var rect := Rect2(lab.position, Vector2(card.size.x - 40.0, 40.0))
		if rect.has_point(local):
			_cursor = i
			_update_hints()
			if ids[i] in ["resume", "rematch", "menu", "colorblind"]:
				_select_option()
			elif ids[i] == "master" or ids[i] == "sfx":
				var t := clampf((local.x - BAR_X) / BAR_W, 0.0, 1.0)
				if ids[i] == "master":
					SFX.set_master_volume(t)
				else:
					SFX.set_sfx_volume(t)
				_update_hints()
			break


func _on_paused_changed(paused: bool) -> void:
	if paused:
		visible = true
		_cursor = 0
		_update_hints()
		_fade_in()
	else:
		_fade_out()


func _fade_in() -> void:
	if _fade_tween:
		_fade_tween.kill()
	_fade_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_fade_tween.tween_property(root, "modulate:a", 1.0, Constants.MENU_FADE_IN).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _fade_out() -> void:
	if _fade_tween:
		_fade_tween.kill()
	_fade_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_fade_tween.tween_property(root, "modulate:a", 0.0, Constants.MENU_FADE_IN).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_fade_tween.finished.connect(_on_fade_out_done)


func _on_fade_out_done() -> void:
	visible = false


func _select_option() -> void:
	var ids := _ids()
	if _cursor < 0 or _cursor >= ids.size():
		return
	match ids[_cursor]:
		"resume":
			SFX.play("confirm")
			GameState.toggle_pause()
		"rematch":
			SFX.play("confirm")
			GameState.rematch()
		"menu":
			SFX.play("confirm")
			get_tree().reload_current_scene()
		"quit":
			get_tree().quit()
		"colorblind":
			SFX.play("ui", 1.2)
			GameState.toggle_colorblind()
			_update_hints()


func _adjust_option(direction: int) -> void:
	var ids := _ids()
	if _cursor < 0 or _cursor >= ids.size():
		return
	match ids[_cursor]:
		"master":
			SFX.set_master_volume(SFX.master_volume + 0.02 * direction)
			_update_hints()
		"sfx":
			SFX.set_sfx_volume(SFX.sfx_volume + 0.02 * direction)
			_update_hints()
		"difficulty":
			GameState.cycle_difficulty(direction)
			SFX.play("ui")
			_update_hints()
		"colorblind":
			if direction != 0:
				SFX.play("ui", 1.2)
				GameState.toggle_colorblind()
				_update_hints()


func _place_bar(fill: ColorRect, knob: ColorRect, value: float) -> void:
	value = clampf(value, 0.0, 1.0)
	fill.size.x = BAR_W * value
	knob.position.x = BAR_X + (BAR_W - KNOB_W) * value


func _update_hints() -> void:
	var idle := Color(0.82, 0.86, 0.9, 1)
	var lit := Color(1, 1, 1, 1)
	var ids := _ids()
	_cursor = clampi(_cursor, 0, ids.size() - 1)
	quit_label.visible = false
	difficulty_label.visible = GameState.mode == Constants.MODE_AI
	colorblind_label.position.y = 402.0 if difficulty_label.visible else 358.0
	resume_label.text = "RESUME"
	restart_label.text = "REMATCH"
	menu_label.text = "MAIN MENU"
	master_label.text = "MASTER"
	volume_label.text = "SFX"
	difficulty_label.text = "CPU DIFFICULTY    <  %s  >" % GameState.difficulty_label().to_upper()
	colorblind_label.text = "COLORBLIND     <  %s  >" % ("ON" if GameState.colorblind_mode else "OFF")
	if GameState.is_touch_ui():
		pause_hint.text = "TAP A ROW     DRAG VOLUME     PAUSE OR BACK RESUME"
	elif OS.has_feature("web"):
		pause_hint.text = "UP/DOWN NAVIGATE     LEFT/RIGHT ADJUST\nSPACE/ENTER SELECT     ESC RESUME     M MUTE"
	else:
		pause_hint.text = "UP/DOWN NAVIGATE     LEFT/RIGHT ADJUST\nSPACE/ENTER SELECT     ESC RESUME     M MUTE     Q QUIT"
	for id in ["resume", "rematch", "menu", "quit", "master", "sfx", "difficulty", "colorblind"]:
		var lab := _label_for(id)
		lab.add_theme_color_override("font_color", idle)
	var selected: String = ids[_cursor]
	_label_for(selected).add_theme_color_override("font_color", lit)
	cursor_bar.position.y = _label_for(selected).position.y - 6.0
	_place_bar(master_fill, master_knob, SFX.master_volume)
	_place_bar(sfx_fill, sfx_knob, SFX.sfx_volume)
	master_pct.text = "%d%%" % int(round(SFX.master_volume * 100.0))
	sfx_pct.text = "%d%%" % int(round(SFX.sfx_volume * 100.0))
	var fill_color := Color(0.92, 0.94, 0.96, 1)
	master_fill.color = fill_color
	sfx_fill.color = fill_color
	audio_header.visible = true
	game_header.visible = true
