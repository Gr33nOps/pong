extends CanvasLayer
## The paper menus: a title, a status line, up to four ink buttons, a room
## code (or a box to type one) and a hint at the bottom.
##
## It doesn't decide anything itself. When a button is used it emits
## `chosen(id, direction)`: direction is 1 for select / right and -1 for left
## (used by buttons that hold a value, like "PLAYERS < 4 >").

signal chosen(id: String, direction: int)
signal code_clicked
signal code_entered

const INK_BUTTON_SCRIPT = preload("res://scripts/ui/ink_button.gd")
const INK_PANEL_SCRIPT = preload("res://scripts/ui/ink_panel.gd")
const INK_THEME = preload("res://assets/ink_theme.tres")
const INK := Color(0.12, 0.12, 0.11, 1.0)
const MAX_BUTTONS := 4
const BUTTON_LEFT := 336.0
const BUTTON_SIZE := Vector2(480.0, 58.0)
const BUTTON_GAP := 70.0

## Ids of the buttons currently shown, top to bottom.
var options: Array[String] = []
## Which button is highlighted.
var cursor := 0

var title: Label
var subtitle: Label
var status: Label
var code: Label
var code_box: LineEdit
var hint: Label
var button_labels: Array[Label] = []

var _root: Control
var _dimmer: ColorRect
var _code_frame: Panel
var _buttons: Array[Panel] = []


func _ready() -> void:
	layer = 20
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = INK_THEME
	add_child(_root)

	_dimmer = ColorRect.new()
	_dimmer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dimmer.color = Color(1.0, 1.0, 1.0, 0.94)
	_dimmer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_dimmer)

	title = _add_label(40)
	subtitle = _add_label(18)
	subtitle.position = Vector2(176.0, 218.0)
	subtitle.size = Vector2(800.0, 30.0)
	status = _add_label(18)
	# Wrapping labels size themselves from their width, so set it before any text.
	status.size = Vector2(700.0, 52.0)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	code = _add_label(40)
	code.position = Vector2(376.0, 210.0)
	code.size = Vector2(400.0, 56.0)
	code.mouse_filter = Control.MOUSE_FILTER_STOP
	code.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	code.tooltip_text = "COPY ROOM CODE"
	code.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			code_clicked.emit()
	)

	_code_frame = Panel.new()
	_code_frame.set_script(INK_PANEL_SCRIPT)
	_code_frame.position = Vector2(396.0, 214.0)
	_code_frame.size = Vector2(360.0, 56.0)
	_root.add_child(_code_frame)
	code_box = LineEdit.new()
	code_box.position = Vector2(396.0, 216.0)
	code_box.size = Vector2(360.0, 52.0)
	code_box.max_length = 6
	code_box.placeholder_text = "6-CHARACTER CODE"
	code_box.alignment = HORIZONTAL_ALIGNMENT_CENTER
	code_box.add_theme_font_size_override("font_size", 24)
	code_box.add_theme_color_override("font_color", INK)
	code_box.add_theme_color_override("font_placeholder_color", Color(0.35, 0.35, 0.34, 1.0))
	code_box.add_theme_color_override("caret_color", INK)
	code_box.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	code_box.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	code_box.text_submitted.connect(func(_text: String) -> void: code_entered.emit())
	_root.add_child(code_box)

	for index in MAX_BUTTONS:
		var button := Panel.new()
		button.set_script(INK_BUTTON_SCRIPT)
		button.position = Vector2(BUTTON_LEFT, 0.0)
		button.size = BUTTON_SIZE
		button.gui_input.connect(_on_button_input.bind(index))
		_root.add_child(button)
		_buttons.append(button)
		var label := _add_label(21)
		label.size = Vector2(BUTTON_SIZE.x, 34.0)
		button_labels.append(label)

	hint = _add_label(16)
	hint.position = Vector2(76.0, 572.0)
	hint.size = Vector2(1000.0, 28.0)


func _add_label(font_size: int) -> Label:
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", INK)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(label)
	return label


## Shows a menu. buttons is a list of [id, text] pairs.
func open(heading: String, status_text: String, buttons: Array, hint_text: String = "", buttons_top: float = 300.0) -> void:
	_root.visible = true
	_dimmer.visible = true
	title.text = heading
	title.add_theme_font_size_override("font_size", 40)
	title.position = Vector2(176.0, 96.0)
	title.size = Vector2(800.0, 56.0)
	subtitle.visible = false
	status.position = Vector2(226.0, 156.0)
	status.size = Vector2(700.0, 52.0)
	status.text = status_text
	hint.text = hint_text
	code.visible = false
	_code_frame.visible = false
	code_box.visible = false
	options.clear()
	for index in MAX_BUTTONS:
		var shown := index < buttons.size()
		_buttons[index].visible = shown
		button_labels[index].visible = shown
		if not shown:
			continue
		options.append(str(buttons[index][0]))
		button_labels[index].text = str(buttons[index][1])
		_buttons[index].position.y = buttons_top + index * BUTTON_GAP
		button_labels[index].position = Vector2(BUTTON_LEFT, buttons_top + index * BUTTON_GAP + 12.0)
	cursor = clampi(cursor, 0, maxi(options.size() - 1, 0))
	_highlight_cursor()


## The big title on the first screen.
func show_big_title(text: String, subtitle_text: String) -> void:
	title.text = text
	title.add_theme_font_size_override("font_size", 80)
	title.position = Vector2(176.0, 118.0)
	title.size = Vector2(800.0, 92.0)
	subtitle.visible = true
	subtitle.text = subtitle_text


func show_code(room_code: String) -> void:
	code.visible = true
	code.text = room_code


func show_code_box() -> void:
	_code_frame.visible = true
	code_box.visible = true
	code_box.text = ""
	code_box.grab_focus()


func close() -> void:
	_root.visible = false
	code_box.release_focus()


func move_cursor(step: int) -> void:
	if options.is_empty():
		return
	cursor = posmod(cursor + step, options.size())
	Sound.play("nav")
	_highlight_cursor()


## Uses the highlighted button (Space / Enter / controller A).
func press(direction: int = 1) -> void:
	if not options.is_empty():
		chosen.emit(options[cursor], direction)


func selected() -> String:
	return options[cursor] if not options.is_empty() else ""


func _highlight_cursor() -> void:
	for index in _buttons.size():
		_buttons[index].set("selected", index == cursor and index < options.size())


func _on_button_input(event: InputEvent, index: int) -> void:
	if index >= options.size():
		return
	if event is InputEventMouseMotion and cursor != index:
		cursor = index
		_highlight_cursor()
	elif event is InputEventMouseButton and event.pressed:
		cursor = index
		_highlight_cursor()
		if event.button_index == MOUSE_BUTTON_LEFT:
			chosen.emit(options[index], 1)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			chosen.emit(options[index], -1)
