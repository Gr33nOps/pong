extends Node
# Short, dry CC0 recordings chosen to feel like ink-on-paper taps and ticks.

const PADDLE_HIT: AudioStream = preload("res://audio/paddle-hit.ogg")
const WALL_HIT: AudioStream = preload("res://audio/wall-hit.ogg")
const UI_CLICK: AudioStream = preload("res://audio/ui-click.ogg")
const UI_ROLLOVER: AudioStream = preload("res://audio/ui-rollover.ogg")
const UI_CONFIRM: AudioStream = preload("res://audio/ui-confirm.ogg")

var master_volume: float = 1.0
var sfx_volume: float = 1.0
var muted := false
var _save_timer: Timer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_save_timer = Timer.new()
	_save_timer.one_shot = true
	_save_timer.wait_time = 0.35
	_save_timer.timeout.connect(_save_settings)
	add_child(_save_timer)
	_load_settings()
	add_sound("paddle", PADDLE_HIT, 0.62)
	add_sound("wall", WALL_HIT, 0.46)
	add_sound("score", WALL_HIT, 0.42)
	add_sound("score_low", WALL_HIT, 0.34)
	add_sound("win", UI_CONFIRM, 0.48)
	add_sound("win_low", UI_CONFIRM, 0.38)
	add_sound("ui", UI_ROLLOVER, 0.28)
	add_sound("confirm", UI_CLICK, 0.38)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_M:
			toggle_mute()
			get_viewport().set_input_as_handled()


func _load_settings() -> void:
	var config := Constants.read_config()
	master_volume = config.get_value("audio", Constants.KEY_MASTER_VOLUME, 1.0)
	sfx_volume = config.get_value("audio", Constants.KEY_SFX_VOLUME, 1.0)
	muted = config.get_value("audio", Constants.KEY_MUTED, false)
	_set_all_volumes()


func _save_settings() -> void:
	var config := Constants.read_config()
	config.set_value("audio", Constants.KEY_MASTER_VOLUME, master_volume)
	config.set_value("audio", Constants.KEY_SFX_VOLUME, sfx_volume)
	config.set_value("audio", Constants.KEY_MUTED, muted)
	Constants.write_config(config)


func _queue_save() -> void:
	_save_timer.start()


func _set_all_volumes() -> void:
	var linear := 0.0 if muted else master_volume * sfx_volume
	var db := -80.0 if linear <= 0.0001 else linear_to_db(linear)
	for child in get_children():
		if child is AudioStreamPlayer:
			var base_volume: float = child.get_meta("base_volume", 1.0)
			child.volume_db = db + (linear_to_db(base_volume) if base_volume > 0.0001 else -80.0)


func add_sound(sound_name: String, stream: AudioStream, volume: float) -> void:
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.set_meta("base_volume", clampf(volume, 0.0, 1.0))
	player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(player)
	player.name = sound_name
	_set_all_volumes()


func play(sound_name: String, pitch: float = 1.0) -> void:
	if muted:
		return
	var player := get_node_or_null(sound_name)
	if player:
		player.pitch_scale = clampf(pitch, 0.7, 1.9)
		player.play()


func stop_all() -> void:
	for child in get_children():
		if child is AudioStreamPlayer:
			child.stop()


func play_score() -> void:
	play("score_low", 0.9)
	play("score", 1.05)


func play_win() -> void:
	play("win_low", 0.95)
	play("win", 1.1)


func toggle_mute() -> void:
	muted = not muted
	_set_all_volumes()
	_queue_save()
	if not muted:
		play("ui")


func set_master_volume(vol: float) -> void:
	master_volume = clampf(vol, 0.0, 1.0)
	if master_volume > 0.0:
		muted = false
	_set_all_volumes()
	_queue_save()


func set_sfx_volume(vol: float) -> void:
	sfx_volume = clampf(vol, 0.0, 1.0)
	if sfx_volume > 0.0:
		muted = false
	_set_all_volumes()
	_queue_save()
