extends CanvasLayer

@onready var root = $Root
@onready var cursor_bar = $Root/Card/Cursor
@onready var resume_label = $Root/Card/resumeHint
@onready var restart_label = $Root/Card/restartHint
@onready var quit_label = $Root/Card/quitHint
@onready var volume_label = $Root/Card/volumeHint
@onready var master_label = $Root/Card/masterHint
@onready var difficulty_label = $Root/Card/difficultyHint
@onready var sfx_fill = $Root/Card/SfxFill
@onready var master_fill = $Root/Card/MasterFill
@onready var sfx_knob = $Root/Card/SfxKnob
@onready var master_knob = $Root/Card/MasterKnob
@onready var master_pct = $Root/Card/masterPct
@onready var sfx_pct = $Root/Card/sfxPct
@onready var pause_hint = $Root/Card/pauseHint

var _cursor := 0
var _fade_tween: Tween = null
var _held_repeat_elapsed := 0.0
var _dragging_id := ""
var _drag_pointer := -1
var menu_label: Label
const BAR_X := 188.0
const BAR_W := 204.0
const KNOB_W := 8.0


func _ready() -> void:
	visible = false
	layer = 30
	Constants.configure_touch_root(root)
	root.modulate = Color(1, 1, 1, 0)
	_ensure_menu_label()
	master_label.visible = false
	master_pct.visible = false
	master_fill.visible = false
	master_knob.visible = false
	$Root/Card/MasterTrack.visible = false
	GameState.paused_changed.connect(_on_paused_changed)
	GameState.game_over.connect(_on_game_over)
	_update_hints()


func _ensure_menu_label() -> void:
	menu_label = Label.new()
	menu_label.name = "menuHint"
	menu_label.position = Vector2(40, 162)
	menu_label.size = Vector2(444, 26)
	menu_label.add_theme_font_size_override("font_size", 20)
	menu_label.text = "MAIN MENU"
	$Root/Card.add_child(menu_label)
	quit_label.visible = false


func _ids() -> Array[String]:
	var ids: Array[String] = ["resume"]
	if GameState.mode != Constants.MODE_ONLINE:
		ids.append("rematch")
	ids.append("menu")
	ids.append("sfx")
	if GameState.mode == Constants.MODE_AI:
		ids.append("difficulty")
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
		SFX.play("nav")
		_update_hints()

	if Input.is_action_just_pressed("stop") or Input.is_action_just_pressed("ui_accept") or Players.is_confirm_just_pressed():
		_select_option()

	var id: String = ids[_cursor]
	if id == "sfx":
		var held := _held_dir()
		if held != 0:
			_held_repeat_elapsed += _delta
			if _held_repeat_elapsed >= 0.06:
				_adjust_option(held, _delta)
				_held_repeat_elapsed = 0.0
		else:
			_held_repeat_elapsed = 0.0
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
		GameState.note_input("mouse")
		_drag_pointer = -1
		_on_pause_click($Root/Card.get_local_mouse_position())
		_dragging_id = _row_at($Root/Card.get_local_mouse_position())
		_set_drag_value($Root/Card.get_local_mouse_position())
	elif event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging_id = ""
		_drag_pointer = -1
	elif event is InputEventMouseMotion and _drag_pointer == -1 and _dragging_id != "":
		_set_drag_value($Root/Card.get_local_mouse_position())
	elif event is InputEventScreenTouch and event.pressed:
		GameState.note_input("touch")
		var canvas: Transform2D = $Root/Card.get_global_transform_with_canvas()
		var local: Vector2 = canvas.affine_inverse() * event.position
		_drag_pointer = event.index
		_on_pause_click(local)
		_dragging_id = _row_at(local)
		_set_drag_value(local)
	elif event is InputEventScreenTouch and not event.pressed:
		if _drag_pointer == event.index:
			_dragging_id = ""
			_drag_pointer = -1
	elif event is InputEventScreenDrag and _drag_pointer == event.index:
		var canvas: Transform2D = $Root/Card.get_global_transform_with_canvas()
		_set_drag_value(canvas.affine_inverse() * event.position)


func _on_pause_click(local: Vector2) -> void:
	var ids := _ids()
	var id := _row_at(local)
	if id == "":
		return
	_cursor = ids.find(id)
	_update_hints()
	if id in ["resume", "rematch", "menu"]:
		_select_option()
	elif id == "sfx":
		_set_volume(id, local.x)
	elif id == "difficulty":
		GameState.advance_difficulty()
		SFX.play("nav")
		_update_hints()


func _row_at(local: Vector2) -> String:
	var card: Control = $Root/Card
	var best_id := ""
	var best_distance := INF
	var hit_height := 72.0 if GameState.is_touch_ui() else 48.0
	for id in _ids():
		var lab := _label_for(id)
		var center_y := lab.position.y + lab.size.y * 0.5
		var distance := absf(local.y - center_y)
		if local.x >= 20.0 and local.x <= card.size.x - 20.0 and distance <= hit_height * 0.5 and distance < best_distance:
			best_distance = distance
			best_id = id
	return best_id


func _set_volume(id: String, x: float) -> void:
	var t := clampf((x - BAR_X) / BAR_W, 0.0, 1.0)
	SFX.set_sfx_volume(t)
	_update_hints()


func _set_drag_value(local: Vector2) -> void:
	if _dragging_id == "sfx":
		_set_volume(_dragging_id, local.x)


func _on_paused_changed(paused: bool) -> void:
	if paused:
		visible = true
		_cursor = 0
		_update_hints()
		_fade_in()
	else:
		_fade_out()


func _on_game_over(_winner: String) -> void:
	# Online play can finish remotely while the local pause overlay is open.
	# Modal overlays are exclusive: game over always replaces pause immediately.
	if _fade_tween:
		_fade_tween.kill()
	_dragging_id = ""
	_drag_pointer = -1
	root.modulate.a = 0.0
	visible = false


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
			if GameState.mode == Constants.MODE_ONLINE:
				NetworkManager.disconnect_from_server()
			get_tree().reload_current_scene()
		"quit":
			get_tree().quit()


func _adjust_option(direction: int, amount: float = 1.0) -> void:
	var ids := _ids()
	if _cursor < 0 or _cursor >= ids.size():
		return
	match ids[_cursor]:
		"sfx":
			SFX.set_sfx_volume(SFX.sfx_volume + 3.0 * amount * direction)
			_update_hints()
		"difficulty":
			GameState.cycle_difficulty(direction)
			SFX.play("nav")
			_update_hints()


func _place_bar(fill: ColorRect, knob: ColorRect, value: float) -> void:
	value = clampf(value, 0.0, 1.0)
	fill.size.x = BAR_W * value
	knob.position.x = BAR_X + (BAR_W - KNOB_W) * value
	var track_name := "MasterTrack" if fill.name == "MasterFill" else "SfxTrack"
	var track := fill.get_parent().get_node_or_null(track_name)
	if track:
		track.set("value", value)


func _update_hints() -> void:
	var idle := Color(0.12, 0.12, 0.11, 1)
	var lit := Color(0.12, 0.12, 0.11, 1)
	var ids := _ids()
	_cursor = clampi(_cursor, 0, ids.size() - 1)
	quit_label.visible = false
	restart_label.visible = GameState.mode != Constants.MODE_ONLINE
	menu_label.position.y = 124.0 if GameState.mode == Constants.MODE_ONLINE else 162.0
	volume_label.position.y = 172.0 if GameState.mode == Constants.MODE_ONLINE else 214.0
	sfx_pct.position.y = 172.0 if GameState.mode == Constants.MODE_ONLINE else 214.0
	$Root/Card/SfxTrack.position.y = 180.0 if GameState.mode == Constants.MODE_ONLINE else 222.0
	difficulty_label.visible = GameState.mode == Constants.MODE_AI
	# The game uses one monochrome ink palette by design.
	resume_label.text = "RESUME"
	restart_label.text = "REMATCH"
	menu_label.text = "LEAVE MATCH" if GameState.mode == Constants.MODE_ONLINE else "MAIN MENU"
	volume_label.text = "SFX"
	difficulty_label.text = "CPU DIFFICULTY    <  %s  >" % GameState.difficulty_label().to_upper()
	$Root/Card/pauseLabel.text = "ONLINE MENU" if GameState.mode == Constants.MODE_ONLINE else "PAUSED"
	if GameState.mode == Constants.MODE_ONLINE:
		pause_hint.text = "MATCH CONTINUES ONLINE\nSELECT RESUME OR LEAVE MATCH"
	elif GameState.is_touch_ui():
		pause_hint.text = "TAP ROW     DRAG SFX"
	elif GameState.is_controller_ui():
		pause_hint.text = "STICK MOVE     LEFT/RIGHT CHANGE\nA SELECT     B RESUME"
	elif OS.has_feature("web"):
		pause_hint.text = "UP/DOWN MOVE     LEFT/RIGHT CHANGE\nSPACE SELECT     ESC RESUME     M MUTE"
	else:
		pause_hint.text = "UP/DOWN MOVE     LEFT/RIGHT CHANGE\nSPACE SELECT     ESC RESUME     M MUTE     Q QUIT"
	for id in ["resume", "rematch", "menu", "quit", "master", "sfx", "difficulty"]:
		var lab := _label_for(id)
		lab.add_theme_color_override("font_color", idle)
	var selected: String = ids[_cursor]
	_label_for(selected).add_theme_color_override("font_color", lit)
	# Every navigable row, including both volume sliders, gets the same ink focus box.
	cursor_bar.visible = selected in ids
	cursor_bar.position.y = _label_for(selected).position.y - 6.0
	_place_bar(sfx_fill, sfx_knob, SFX.sfx_volume)
	sfx_pct.text = "%d%%" % int(round(SFX.sfx_volume * 100.0))
	sfx_fill.color = Color(0.12, 0.12, 0.11, 1)
