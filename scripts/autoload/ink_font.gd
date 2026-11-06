extends Node
## Makes the handwritten Patrick Hand font the default for every label.

const FONT: FontFile = preload("res://assets/fonts/PatrickHand-Regular.ttf")


func _ready() -> void:
	var font := FONT
	var theme := Theme.new()
	theme.default_font = font
	theme.default_font_size = 22
	theme.set_color("font_color", "Label", Color(0.12, 0.12, 0.11, 1.0))
	theme.set_color("font_outline_color", "Label", Color(0.12, 0.12, 0.11, 1.0))
	theme.set_constant("outline_size", "Label", 1)
	# Symbols the handwritten font lacks fall back to system fonts.
	var fallback := SystemFont.new()
	fallback.font_names = PackedStringArray(["Segoe UI Symbol", "Segoe UI", "Arial"])
	font.fallbacks = [fallback]
	get_tree().root.theme = theme
