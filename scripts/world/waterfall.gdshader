shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_opaque, diffuse_lambert, specular_disabled;

// A waterfall: a sheet of falling water down a drop in the river. UV is in metres -- x along the
// lip, y down from the top -- so streaks are the same size on a 4.5 m terrace and a 12 m cliff,
// and they pour downwards. Drawn in the same cartoon style as the water (water.gdshader): hard
// white streaks with no soft edge, over a flat tone.

uniform vec3 water_color : source_color = vec3(0.33, 0.7, 0.88);
uniform vec3 foam_color : source_color = vec3(0.95, 0.98, 1.0);
uniform float speed = 5.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void fragment() {
	vec2 q = vec2(UV.x * 3.0, UV.y * 0.6 - TIME * speed);
	float n = noise(q);
	float aa = fwidth(n);
	float streak = smoothstep(0.62 - aa, 0.62 + aa, n);
	// A band just under each streak, a shade lighter, as the water's bands are.
	float band = smoothstep(0.45 - aa, 0.45 + aa, n);
	vec3 colour = mix(water_color, water_color * 1.18, band);
	colour = mix(colour, foam_color, streak);
	ALBEDO = colour;
	ALPHA = 0.8 + streak * 0.17;
}
