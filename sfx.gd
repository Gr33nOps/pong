extends Node
# Procedurally generated retro sound effects (no audio assets required).
# Each sound is a short synthesized tone baked into an AudioStreamWAV.

var master_volume: float = 1.0
var sfx_volume: float = 1.0


func _ready() -> void:
	_load_settings()
	add_sound("paddle", 660.0, 0.06, 0.7)
	add_sound("wall", 330.0, 0.05, 0.5)
	add_sound("score", 440.0, 0.25, 0.6)
	add_sound("win", 880.0, 0.45, 0.6)


func _load_settings() -> void:
	var config := Constants.read_config()
	master_volume = config.get_value("audio", Constants.KEY_MASTER_VOLUME, 1.0)
	sfx_volume = config.get_value("audio", Constants.KEY_SFX_VOLUME, 1.0)
	_set_all_volumes()


func _save_settings() -> void:
	var config := Constants.read_config()
	config.set_value("audio", Constants.KEY_MASTER_VOLUME, master_volume)
	config.set_value("audio", Constants.KEY_SFX_VOLUME, sfx_volume)
	Constants.write_config(config)


func _set_all_volumes() -> void:
	for child in get_children():
		if child is AudioStreamPlayer:
			child.volume_db = linear_to_db(master_volume * sfx_volume)


func add_sound(sound_name: String, frequency: float, duration: float, volume: float) -> void:
	var player := AudioStreamPlayer.new()
	player.stream = _make_tone(frequency, duration, volume)
	player.process_mode = Node.PROCESS_MODE_ALWAYS
	player.volume_db = linear_to_db(master_volume * sfx_volume)
	add_child(player)
	player.name = sound_name


func play(sound_name: String, pitch: float = 1.0) -> void:
	var player := get_node_or_null(sound_name)
	if player:
		player.pitch_scale = clampf(pitch, 0.7, 1.9)
		player.play()


func set_master_volume(vol: float) -> void:
	master_volume = clampf(vol, 0.0, 1.0)
	_set_all_volumes()
	_save_settings()


func set_sfx_volume(vol: float) -> void:
	sfx_volume = clampf(vol, 0.0, 1.0)
	_set_all_volumes()
	_save_settings()


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
