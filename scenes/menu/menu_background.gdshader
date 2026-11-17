shader_type canvas_item;

// Placeholder menu backdrop: a slow two-colour gradient drift.

uniform vec4 color_a : source_color = vec4(0.07, 0.08, 0.12, 1.0);
uniform vec4 color_b : source_color = vec4(0.16, 0.19, 0.30, 1.0);
uniform float speed = 0.08;

void fragment() {
	float t = TIME * speed;
	float wave = sin(UV.x * 2.4 + t * 2.0) * 0.12 + sin(UV.y * 3.1 - t * 1.3) * 0.10;
	float k = clamp(UV.y * 0.8 + UV.x * 0.2 + wave, 0.0, 1.0);
	COLOR = mix(color_a, color_b, smoothstep(0.0, 1.0, k));
}
