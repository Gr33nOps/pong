extends Node
# Procedurally generated retro sound effects (no audio assets required).

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
	add_sound("paddle", 660.0, 0.06, 0.7)
	add_sound("wall", 330.0, 0.05, 0.5)
	add_sound("score", 520.0, 0.16, 0.55)
	add_sound("score_low", 280.0, 0.22, 0.5)
	add_sound("win", 880.0, 0.28, 0.55)
	add_sound("win_low", 440.0, 0.4, 0.5)
	add_sound("ui", 740.0, 0.035, 0.35)
	add_sound("confirm", 880.0, 0.07, 0.45)


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
			child.volume_db = db


func add_sound(sound_name: String, frequency: float, duration: float, volume: float) -> void:
	var player := AudioStreamPlayer.new()
	player.stream = _make_tone(frequency, duration, volume)
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


func _make_tone(frequency: float, duration: float, volume: float) -> AudioStreamWAV:
	var sample_count := int(duration * Constants.SAMPLE_RATE)
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	for i in sample_count:
		var t := float(i) / Constants.SAMPLE_RATE
		var envelope := 1.0 - t / duration
		var value := sin(TAU * frequency * t) * volume * envelope
		data.encode_s16(i * 2, int(clampf(value, -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = Constants.SAMPLE_RATE
	stream.data = data
	return stream
