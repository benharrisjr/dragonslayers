shader_type spatial;
render_mode cull_disabled, world_vertex_coords, diffuse_lambert, specular_disabled;

// Fallen leaves. Each leaf is one MultiMesh instance lying on the ground or heaped in a pile.
// Where they land and tumble is LeafField's business (on the CPU, so a scattered pile stays
// scattered); this only adds the moment-to-moment life: a leaf near a body lifts and flutters
// as it passes, and every leaf curls and stirs a little in the breeze.
//
// INSTANCE_CUSTOM.rgb is each leaf's colour.

uniform vec4 pushers[16];
uniform int pusher_count = 0;
uniform float flutter = 0.3;

varying vec3 tint;

void vertex() {
	tint = INSTANCE_CUSTOM.rgb;
	vec3 root = MODEL_MATRIX[3].xyz;
	// How far this vertex is from the leaf's middle: the edges move, the middle stays put.
	float edge = length(VERTEX - root);
	float stir = 0.0;
	vec3 shove = vec3(0.0);
	for (int i = 0; i < pusher_count; i++) {
		vec3 away = root - pushers[i].xyz;
		float above = abs(away.y);
		away.y = 0.0;
		float dist = length(away);
		float radius = pushers[i].w + 0.4;
		if (dist < radius && above < 2.0) {
			float strength = 1.0 - dist / radius;
			stir = max(stir, strength);
			shove += (dist > 0.001 ? away / dist : vec3(1.0, 0.0, 0.0)) * strength * 0.12;
		}
	}
	float phase = TIME * 13.0 + root.x * 3.1 + root.z * 2.3;
	float breeze = sin(TIME * 2.1 + root.x * 0.8 + root.z * 0.6) * 0.015;
	VERTEX.y += edge * (sin(phase) * stir * flutter + breeze) + stir * 0.08;
	VERTEX += shove;
}

void fragment() {
	ALBEDO = tint;
	// Lit like the ground under them on both sides, so a leaf seen edge-on or from below is not
	// a black sliver.
	NORMAL = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
}
