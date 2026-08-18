extends Node
# Auto-assigns connected gamepads to players: the first gamepad that presses
# a button becomes P1 (left paddle), the second becomes P2 (right paddle).
# Keyboard always works too: W/S = P1, Arrows = P2.

signal player_assigned(player: int, device: int)
signal player_released(player: int)

const PLAYER_1 := 1
const PLAYER_2 := 2
var _devices := {PLAYER_1: -1, PLAYER_2: -1}
var _stick_dir := {}

var _confirm_frame := -1
var _pause_frame := -1
var _nav_up_frame := -1
var _nav_down_frame := -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Input.joy_connection_changed.connect(_on_joy_connection_changed)


func _process(_delta: float) -> void:
	for device_value in _devices.values():
		var device := int(device_value)
		if device < 0:
			continue
		var previous: int = int(_stick_dir.get(device, 0))
		var direction := _navigation_direction(Input.get_joy_axis(device, JOY_AXIS_LEFT_Y), previous)
		if direction != previous:
			_stick_dir[device] = direction
			if direction != 0:
				_emit_navigation(direction)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventJoypadButton:
		_assign(event.device)
		if event.pressed and _is_assigned(event.device):
			# Keep confirm and pause separate. START is advertised as pause;
			# treating it as SELECT too could launch a serve and pause the match
			# in the same frame on controller play.
			if event.button_index == JOY_BUTTON_A:
				_confirm_frame = Engine.get_process_frames()
			if event.button_index == JOY_BUTTON_START or event.button_index == JOY_BUTTON_BACK:
				_pause_frame = Engine.get_process_frames()
			if event.button_index == JOY_BUTTON_DPAD_UP:
				_nav_up_frame = Engine.get_process_frames()
			elif event.button_index == JOY_BUTTON_DPAD_DOWN:
				_nav_down_frame = Engine.get_process_frames()
	elif event is InputEventJoypadMotion and event.axis == JOY_AXIS_LEFT_Y:
		_assign(event.device)


func _emit_navigation(direction: int) -> void:
	if direction < 0:
		_nav_up_frame = Engine.get_process_frames()
	else:
		_nav_down_frame = Engine.get_process_frames()


func get_device(player: int) -> int:
	return _devices.get(player, -1)


func get_axis(player: int) -> float:
	var device := get_device(player)
	if device < 0:
		return 0.0
	var dpad := 0.0
	if Input.is_joy_button_pressed(device, JOY_BUTTON_DPAD_UP):
		dpad -= 1.0
	if Input.is_joy_button_pressed(device, JOY_BUTTON_DPAD_DOWN):
		dpad += 1.0
	if dpad != 0.0:
		return dpad
	return _shape_stick(Input.get_joy_axis(device, JOY_AXIS_LEFT_Y))


func _shape_stick(value: float) -> float:
	var magnitude := absf(value)
	if magnitude <= Constants.GAMEPAD_DEADZONE:
		return 0.0
	var normalized := (magnitude - Constants.GAMEPAD_DEADZONE) / (1.0 - Constants.GAMEPAD_DEADZONE)
	return signf(value) * pow(normalized, Constants.GAMEPAD_RESPONSE_EXPONENT)


func _navigation_direction(value: float, previous: int) -> int:
	var magnitude := absf(value)
	if previous != 0 and magnitude < Constants.GAMEPAD_NAV_RELEASE:
		return 0
	if magnitude < Constants.GAMEPAD_NAV_ENGAGE:
		return previous
	return -1 if value < 0.0 else 1


func is_confirm_just_pressed() -> bool:
	return _confirm_frame == Engine.get_process_frames()


func is_pause_just_pressed() -> bool:
	return _pause_frame == Engine.get_process_frames()


func is_nav_up_just_pressed() -> bool:
	return _nav_up_frame == Engine.get_process_frames()


func is_nav_down_just_pressed() -> bool:
	return _nav_down_frame == Engine.get_process_frames()


func _is_assigned(device: int) -> bool:
	return get_device(PLAYER_1) == device or get_device(PLAYER_2) == device


func _assign(device: int) -> void:
	if get_device(PLAYER_1) == device or get_device(PLAYER_2) == device:
		return
	if get_device(PLAYER_1) == -1:
		_devices[PLAYER_1] = device
		player_assigned.emit(PLAYER_1, device)
	elif get_device(PLAYER_2) == -1:
		_devices[PLAYER_2] = device
		player_assigned.emit(PLAYER_2, device)


func _on_joy_connection_changed(device: int, connected: bool) -> void:
	if connected:
		return
	for player in _devices:
		if _devices[player] == device:
			_devices[player] = -1
			player_released.emit(player)
	_stick_dir.erase(device)
