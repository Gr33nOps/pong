extends Node
# Procedurally generated retro sound effects (no audio assets required).
# Each sound is a short synthesized tone baked into an AudioStreamWAV.

const SAMPLE_RATE := 22050


func _ready() -> void:
	add_sound("paddle", 660.0, 0.06, 0.7)
	add_sound("wall", 330.0, 0.05, 0.5)
	add_sound("score", 440.0, 0.25, 0.6)
	add_sound("win", 880.0, 0.45, 0.6)


func add_sound(sound_name: String, frequency: float, duration: float, volume: float) -> void:
	var player := AudioStreamPlayer.new()
	player.stream = _make_tone(frequency, duration, volume)
	player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(player)
	player.name = sound_name


func play(sound_name: String) -> void:
	var player := get_node_or_null(sound_name)
	if player:
		player.play()


func _make_tone(frequency: float, duration: float, volume: float) -> AudioStreamWAV:
	var sample_count := int(duration * SAMPLE_RATE)
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	for i in sample_count:
		var t := float(i) / SAMPLE_RATE
		var envelope := 1.0 - t / duration
		var value := sin(TAU * frequency * t) * volume * envelope
		data.encode_s16(i * 2, int(clampf(value, -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.data = data
	return stream
