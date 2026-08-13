extends Node
# Global screen shake manager

signal shake_started(magnitude: float)
signal shake_stopped

var _shake_time: float = 0.0
var _shake_magnitude: float = 0.0
var _original_offset: Vector2 = Vector2.ZERO
var _active: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	if not _active:
		return
	_shake_time -= delta
	if _shake_time <= 0.0:
		_stop_shake()
		return
	
	var viewport = get_viewport()
	var offset = Vector2(
		randf_range(-1, 1) * _shake_magnitude,
		randf_range(-1, 1) * _shake_magnitude
	) * (_shake_time / Constants.SHAKE_DURATION)
	viewport.canvas_transform.origin = _original_offset + offset


func shake(magnitude: float) -> void:
	if get_tree().paused:
		return
	if _active:
		if magnitude > _shake_magnitude:
			_shake_magnitude = magnitude
			_shake_time = Constants.SHAKE_DURATION
		return
	_active = true
	_shake_time = Constants.SHAKE_DURATION
	_shake_magnitude = magnitude
	_original_offset = Vector2.ZERO
	shake_started.emit(magnitude)


func reset() -> void:
	_stop_shake()


func _stop_shake() -> void:
	_active = false
	_shake_time = 0.0
	_shake_magnitude = 0.0
	if is_inside_tree():
		get_viewport().canvas_transform.origin = Vector2.ZERO
	shake_stopped.emit()