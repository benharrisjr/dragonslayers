shader_type spatial;
render_mode depth_draw_never, cull_disabled;

// Water for the river, the sea and the lake. After binbun's "Water with Caustics"
// (godotshaders.com, CC0): the bed seen through it, bent by the waves and lit by caustics, deeper
// water darker, foam on the waves and where the water meets anything.
//
// Changed from the original to suit this game:
//   - the Compatibility renderer, whose depth runs the other way;
//   - the river's waves are carried downstream along the flow (COLOR.rg, packed into 0..1) by a
//     two-phase flow map, and it boils to foam where a waterfall lands (COLOR.a);
//   - normals are taken from the waves in world space, as the river's mesh has no tangents;
//   - the sea's surface heaves; the river's and the lake's stay flat, level with their falls;
//   - still water too deep to stand in is shaded darker, with a pale line along the drop.

uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;
uniform sampler2D screen_texture : hint_screen_texture, filter_linear;

uniform vec3 surface_color : source_color = vec3(0.16, 0.5, 0.6);
uniform vec3 depth_color : source_color = vec3(0.04, 0.2, 0.42);
uniform vec3 foam_color : source_color = vec3(0.95, 0.99, 1.0);
// Metres of water by which it is as dark as it gets.
uniform float depth_size = 7.0;
uniform float surface_roughness : hint_range(0.0, 1.0) = 0.12;
uniform float foam_roughness : hint_range(0.0, 1.0) = 0.6;

uniform sampler2D caustics_texture : repeat_enable, filter_linear_mipmap;
uniform float caustics_strength = 1.15;
uniform vec2 caustics_scale = vec2(0.5);

uniform sampler2D wave_texture : repeat_enable, filter_linear_mipmap;
uniform sampler2D wave_normal_texture : repeat_enable, filter_linear_mipmap;
uniform float wave_softness : hint_range(0.0, 10.0) = 1.0;
uniform vec2 wave_scale = vec2(0.06);
uniform vec2 wave_layer_scale = vec2(1.5);
uniform float wave_highlight : hint_range(0.0, 1.0) = 0.35;
uniform float wave_normal : hint_range(0.0, 1.0) = 0.35;
uniform vec2 wave_velocity = vec2(0.02);

uniform sampler2D foam_texture : repeat_enable, filter_linear_mipmap;
uniform float edge_foam_depth_size = 0.45;
uniform float wave_foam_amount : hint_range(0.0, 1.0) = 0.5;
uniform float foam_start : hint_range(0.0, 1.0) = 0.3;
uniform float foam_end : hint_range(0.0, 1.0) = 0.7;
uniform float foam_exponent = 2.0;

uniform float refraction_amount = 0.8;
uniform float refraction_exponent = 0.5;
uniform float displacement_amount = 0.0;

uniform bool use_vertex_flow = false;
// How fast the river carries its waves, in m/s.
uniform float flow_speed = 1.6;

// How deep still water is, one texel per tile across the chunk (0 where it can be stood in).
uniform bool use_depth_map = false;
uniform sampler2D depth_map : filter_linear, repeat_disable;
uniform vec2 depth_origin = vec2(0.0);
uniform float depth_map_size = 128.0;

varying vec3 world_pos;
varying vec2 flow;
varying float fall_foam;

vec4 sample_wave(sampler2D tex, vec2 at, vec2 velocity, float lod) {
	vec2 base_uv = at * wave_scale;
	float wave1 = textureLod(tex, base_uv * wave_layer_scale - TIME * velocity, lod).r;
	return textureLod(tex, base_uv + TIME * velocity - wave1 * 0.1, lod);
}

// The waves at a point, carried along the flow: two copies half a cycle apart, each fading out as
// it starts over.
vec4 flowing_wave(sampler2D tex, vec2 at, vec2 current) {
	if (!use_vertex_flow) {
		return sample_wave(tex, at, wave_velocity, wave_softness);
	}
	float cycle = 1.8;
	float a = fract(TIME / cycle);
	float b = fract(TIME / cycle + 0.5);
	vec4 first = sample_wave(tex, at - current * a * cycle * flow_speed, wave_velocity, wave_softness);
	vec4 second = sample_wave(tex, at - current * b * cycle * flow_speed + 7.3, wave_velocity, wave_softness);
	return mix(second, first, 1.0 - abs(a * 2.0 - 1.0));
}

// Where in the world whatever is drawn behind this pixel is.
vec3 world_behind(vec2 screen_uv, mat4 inv_projection, mat4 inv_view) {
	float depth = texture(depth_texture, screen_uv).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(screen_uv, depth) * 2.0 - 1.0;
#else
	vec3 ndc = vec3(screen_uv * 2.0 - 1.0, depth);
#endif
	vec4 view_pos = inv_projection * vec4(ndc, 1.0);
	return (inv_view * vec4(view_pos.xyz / view_pos.w, 1.0)).xyz;
}

vec3 sample_caustics(vec2 uv) {
	vec2 at = uv * caustics_scale;
	return vec3(texture(caustics_texture, at).r,
			texture(caustics_texture, at + vec2(0.02, 0.02)).r,
			texture(caustics_texture, at + vec2(0.03, 0.01)).r);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	if (displacement_amount > 0.0) {
		float lift = (sample_wave(wave_texture, world_pos.xz, wave_velocity, 3.0).r - 0.5) * displacement_amount;
		VERTEX.y += lift;
		world_pos.y += lift;
	}
	flow = use_vertex_flow ? COLOR.rg * 2.0 - 1.0 : vec2(0.0);
	fall_foam = use_vertex_flow ? COLOR.a : 0.0;
}

void fragment() {
	vec2 p = world_pos.xz;
	float wave = smoothstep(0.0, 1.0, flowing_wave(wave_texture, p, flow).r);

	// What lies under the water, its picture bent by the waves -- less near the shore, and not at
	// all where bending it would pick up something standing in front.
	vec3 behind = world_behind(SCREEN_UV, INV_PROJECTION_MATRIX, INV_VIEW_MATRIX);
	float shallow = pow(clamp((behind.y - world_pos.y + depth_size) / depth_size, 0.0, 1.0), 4.0);
	vec2 bent = SCREEN_UV + (pow(wave, refraction_exponent) * 2.0 - 0.5) * 0.01 * refraction_amount;
	bent = mix(bent, SCREEN_UV, shallow);
	vec3 bent_behind = world_behind(bent, INV_PROJECTION_MATRIX, INV_VIEW_MATRIX);
	if (bent_behind.y > world_pos.y) {
		bent = SCREEN_UV;
	} else {
		behind = bent_behind;
	}
	float depth = pow(clamp((behind.y - world_pos.y + depth_size) / depth_size, 0.0, 1.0), 4.0);

	vec2 bed = behind.xz * 0.2;
	vec3 caustics = sample_caustics(bed - TIME * wave_velocity);
	caustics = sample_caustics(bed + caustics.r * 0.05 + TIME * wave_velocity * 0.5) * (1.0 - depth * 0.5);

	float edge_foam = clamp((behind.y - world_pos.y + edge_foam_depth_size) / edge_foam_depth_size, 0.0, 1.0);
	float foam = max(max(edge_foam, wave * wave_foam_amount), fall_foam);
	float foam_shape = 1.0 - texture(foam_texture, p * 0.12 + wave * 0.05).r;
	foam = clamp((foam - foam_start) / (foam_end - foam_start), 0.0, 1.0);
	foam = clamp((foam - foam_shape) / max(1.0 - foam_shape, 0.001), 0.0, 1.0);
	foam = pow(foam, foam_exponent);

	vec3 color = texture(screen_texture, bent).rgb;
	color += pow(caustics * caustics_strength, vec3(2.0)) * 0.5;
	color = mix(mix(depth_color, surface_color, depth), color, 0.5 * depth);
	color = mix(color, surface_color, wave * wave_highlight);

	if (use_depth_map) {
		float drop = texture(depth_map, (p - depth_origin) / depth_map_size).r;
		color = mix(color, depth_color, smoothstep(0.1, 1.0, drop) * 0.45);
		float width = max(fwidth(drop), 1e-4);
		float shelf = 1.0 - smoothstep(width, width * 2.5, abs(drop - 0.2));
		color = mix(color, foam_color, shelf * 0.7);
	}
	color = mix(color, foam_color, foam);

	vec2 slope = flowing_wave(wave_normal_texture, p, flow).rg * 2.0 - 1.0;
	vec3 normal = normalize(vec3(slope.x * wave_normal, 1.0, slope.y * wave_normal));
	NORMAL = normalize((VIEW_MATRIX * vec4(normal, 0.0)).xyz);
	ROUGHNESS = mix(surface_roughness, foam_roughness, foam);
	ALBEDO = color;
}
