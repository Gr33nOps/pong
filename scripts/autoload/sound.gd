extends Node
## Plays the game's short paper-and-ink sound effects. Press M to mute.

const SOUNDS := {
	# name: [file, volume 0..1]
	"paddle": ["res://assets/audio/paddle-hit.ogg", 0.62],
	"wall": ["res://assets/audio/wall-hit.ogg", 0.28],
	"point": ["res://assets/audio/point-miss.ogg", 0.38],
	"win": ["res://assets/audio/ui-confirm.ogg", 0.42],
	"win_low": ["res://assets/audio/ui-confirm.ogg", 0.32],
	"ui": ["res://assets/audio/ui-click.ogg", 0.28],
	"nav": ["res://assets/audio/ui-nav.ogg", 0.22],
	"confirm": ["res://assets/audio/ui-confirm.ogg", 0.36],
}

var muted := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	muted = bool(Settings.load_config().get_value("audio", "muted", false))
	for sound_name in SOUNDS:
		var player := AudioStreamPlayer.new()
		player.name = sound_name
		player.stream = load(SOUNDS[sound_name][0])
		player.volume_db = linear_to_db(SOUNDS[sound_name][1])
		add_child(player)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_M:
		toggle_mute()
		get_viewport().set_input_as_handled()


func play(sound_name: String, pitch: float = 1.0) -> void:
	if muted:
		return
	var player := get_node_or_null(sound_name) as AudioStreamPlayer
	if player:
		player.pitch_scale = clampf(pitch, 0.7, 1.9)
		player.play()


func play_win() -> void:
	play("win_low", 0.95)
	play("win", 1.1)


func toggle_mute() -> void:
	muted = not muted
	var config := Settings.load_config()
	config.set_value("audio", "muted", muted)
	Settings.save_config(config)
	play("ui")
