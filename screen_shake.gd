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
	if _active:
		# Extend existing shake if stronger
		if magnitude > _shake_magnitude:
			_shake_magnitude = magnitude
			_shake_time = Constants.SHAKE_DURATION
		return
	
	_active = true
	_shake_time = Constants.SHAKE_DURATION
	_shake_magnitude = magnitude
	_original_offset = get_viewport().canvas_transform.origin
	shake_started.emit(magnitude)


func _stop_shake() -> void:
	_active = false
	_shake_time = 0.0
	_shake_magnitude = 0.0
	get_viewport().canvas_transform.origin = _original_offset
	shake_stopped.emit()