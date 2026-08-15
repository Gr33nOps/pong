extends Node
# Loads the arcade pixel font and applies it as the default UI theme.

const ARCADE_FONT: FontFile = preload("res://fonts/PressStart2P-Regular.ttf")

var font: FontFile
var theme: Theme


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	font = ARCADE_FONT
	theme = Theme.new()
	theme.default_font = font
	theme.default_font_size = 12
	theme.set_color("font_color", "Label", Color(0.92, 0.95, 1.0, 1.0))
	var fallback := SystemFont.new()
	fallback.font_names = PackedStringArray(["Segoe UI Symbol", "Segoe UI", "Arial"])
	font.fallbacks = [fallback]
	get_tree().root.theme = theme
