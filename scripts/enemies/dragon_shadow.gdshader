shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;

// The dragon's shadow on the ground while it flies: a soft dark shape -- a long body and two
// swept-back wings -- laid flat under it. UV.x runs across the wings, UV.y from nose to tail.

uniform float strength = 0.5;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float body = 1.0 - smoothstep(0.55, 1.0, length(vec2(p.x * 5.0, p.y * 1.05)));
	// Wings: wide and thin, swept back towards the tips.
	vec2 w = vec2(p.x, p.y + 0.1 - abs(p.x) * 0.35);
	float wings = 1.0 - smoothstep(0.5, 1.0, length(vec2(w.x * 1.02, w.y * 3.4)));
	ALBEDO = vec3(0.0);
	ALPHA = max(body, wings) * strength;
}
