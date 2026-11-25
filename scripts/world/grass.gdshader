shader_type spatial;
render_mode cull_disabled, world_vertex_coords, diffuse_lambert, specular_disabled;

// Long summer grass, after Toadile's "Grass with Screen-Space Displacement" (godotshaders.com,
// MIT): each instance is a tuft -- two crossed quads, twice as wide as they are tall, with the
// blades cut out of them -- that sways with gusts of wind blowing across the field, varies in
// height and colour, splays open when something pushes through it, and shrinks away in the
// distance instead of popping out.
//
// What is different from the original:
//   - its blades come from a grass texture; these are drawn here, a handful of tapering strokes
//     per quad, each tuft's own (seeded from where it grows);
//   - its bending is screen-space: it reads the depth buffer to see what stands in front of the
//     grass. Godot 4 only hands the depth buffer to see-through materials, and this is cut-out
//     grass drawn in the opaque pass, so instead the bodies to bend away from are handed over
//     every frame by GrassField as (position, radius), up to 16 of them, as they were before. A
//     push bends the tuft over (in the vertex shader) and splays its blades apart and down (in
//     the fragment shader, where the original shifted its texture);
//   - wind comes from a seamless noise texture scrolled across the world, as the original's does.
//
// A tuft that has been cut is the same tuft scaled down to stubble, so it barely moves.
// UV.x runs across a quad, UV.y from 0 at the root to 1 at the tip. INSTANCE_CUSTOM carries each
// tuft's tint.

uniform vec4 pushers[16];
uniform int pusher_count = 0;
uniform vec3 root_color : source_color = vec3(0.3, 0.42, 0.16);
uniform vec3 tip_color : source_color = vec3(0.66, 0.72, 0.36);
// How far a tuft at full height is pushed over by a body standing right on it, in metres.
uniform float push = 1.1;

uniform sampler2D wind_noise : filter_linear, repeat_enable;
uniform vec2 wind_direction = vec2(0.8, 0.6);
// Metres across one gust.
uniform float wind_scale = 24.0;
uniform float wind_speed = 0.05;
uniform float wind_strength = 0.35;

uniform float blades = 7.0;
// Tufts past fade_start shrink, and are gone by fade_end.
uniform float fade_start = 55.0;
uniform float fade_end = 80.0;

varying float height;
varying vec3 tint;
varying float pressed;
varying float seed;

// Cheap and good enough for blade placement (no sin: this runs 21 times a pixel).
float hash(float n) {
	n = fract(n * 0.1031);
	n *= n + 33.33;
	n *= n + n;
	return fract(n);
}

void vertex() {
	height = UV.y;
	tint = INSTANCE_CUSTOM.rgb;
	vec3 root = MODEL_MATRIX[3].xyz;
	seed = fract(root.x * 0.137 + root.z * 0.711) * 97.0;
	// How tall this tuft stands: 1 for full grass, small once it has been cut.
	float tall = length(MODEL_MATRIX[1].xyz);
	float bend = height * height;

	// Gusts: the noise scrolls across the world along the wind, so a wave of bending runs over
	// a field, and each tuft also flutters on its own.
	vec2 gust_at = root.xz / wind_scale - wind_direction * TIME * wind_speed;
	float gust = texture(wind_noise, gust_at).r;
	float flutter = sin(TIME * 2.7 + seed * 6.3) * 0.06;
	vec2 blown = wind_direction * (gust * gust * 1.6 + 0.15) * wind_strength
			+ vec2(flutter, flutter * 0.6);
	vec3 offset = vec3(blown.x, 0.0, blown.y);

	pressed = 0.0;
	for (int i = 0; i < pusher_count; i++) {
		vec3 away = root - pushers[i].xyz;
		float above = abs(away.y);
		away.y = 0.0;
		float dist = length(away);
		float radius = pushers[i].w;
		if (dist < radius && above < 2.5) {
			float strength = 1.0 - dist / radius;
			vec3 direction = dist > 0.001 ? away / dist : vec3(1.0, 0.0, 0.0);
			offset += direction * strength * push;
			offset.y -= strength * push * 0.55;
			pressed = max(pressed, strength);
		}
	}

	// Shrinking into the distance, from the camera.
	float distance_away = length(root - CAMERA_POSITION_WORLD);
	float shown = 1.0 - smoothstep(fade_start, fade_end, distance_away);
	VERTEX = root + (VERTEX - root) * vec3(1.0, shown, 1.0);
	VERTEX += offset * bend * tall * shown;
}

void fragment() {
	// The blades on this quad: each a tapering stroke from somewhere along the bottom, curving
	// out to one side, of its own height. Pushed, they splay outwards and lie lower.
	float u = UV.x;
	float v = UV.y;
	float best = -1.0;
	float tip = 0.0;
	for (float i = 0.0; i < blades; i += 1.0) {
		float r = seed + i * 13.1 + (FRONT_FACING ? 0.0 : 5.0);
		float base = 0.12 + 0.76 * (i + 0.5) / blades + (hash(r) - 0.5) * 0.12;
		float side = base < 0.5 ? -1.0 : 1.0;
		float lean = (hash(r + 1.7) - 0.5) * 0.35 + side * pressed * 0.35;
		float blade_height = mix(0.6, 1.0, hash(r + 3.1)) * (1.0 - pressed * 0.35);
		if (v > blade_height) {
			continue;
		}
		float along = v / blade_height;
		float centre = base + lean * along * along;
		float half_width = 0.09 * (1.0 - along * along * 0.4 - along * 0.6);
		float inside = half_width - abs(u - centre);
		if (inside > best) {
			best = inside;
			tip = along;
		}
	}
	// How much of this pixel the nearest blade covers, from how far inside its edge the pixel's
	// centre is against a pixel's width. Handed to MSAA as coverage (alpha to coverage), so a
	// blade's edge is smoothed like a polygon's instead of cut out in hard steps.
	float pixel = max(fwidth(u), 1e-4);
	float coverage = clamp(best / pixel + 0.5, 0.0, 1.0);
	if (coverage <= 0.0) {
		discard;
	}
	ALPHA = coverage;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ALPHA_ANTIALIASING_EDGE = 0.5;
	// Lighter towards each blade's own tip, and darker where it is pressed down.
	ALBEDO = mix(root_color, tip_color, tip) * tint * (1.0 - pressed * 0.12);
	// Lit as if it were the ground it stands on, on both sides, so a patch shades like a field
	// rather than a thousand little cards -- and a blade seen from behind is not black.
	NORMAL = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
}
