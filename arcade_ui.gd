extends Node
# Loads the handwritten ink font and applies it as the default UI theme.

const ARCADE_FONT: FontFile = preload("res://fonts/PatrickHand-Regular.ttf")

var font: FontFile
var theme: Theme


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	font = ARCADE_FONT
	theme = Theme.new()
	theme.default_font = font
	theme.default_font_size = 22
	theme.set_color("font_color", "Label", Color(0.12, 0.12, 0.11, 1.0))
	theme.set_color("font_outline_color", "Label", Color(0.12, 0.12, 0.11, 1.0))
	theme.set_constant("outline_size", "Label", 1)
	var fallback := SystemFont.new()
	fallback.font_names = PackedStringArray(["Segoe UI Symbol", "Segoe UI", "Arial"])
	font.fallbacks = [fallback]
	get_tree().root.theme = theme
