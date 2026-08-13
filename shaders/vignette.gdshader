shader_type canvas_item;

void fragment() {
	float d = distance(UV, vec2(0.5));
	float a = smoothstep(0.52, 1.08, d) * 0.48;
	COLOR = vec4(0.0, 0.02, 0.05, a);
}
