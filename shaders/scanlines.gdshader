shader_type canvas_item;

void fragment() {
	float line = step(0.78, fract(UV.y * 220.0)) * 0.022;
	COLOR = vec4(0.0, 0.0, 0.0, line);
}
