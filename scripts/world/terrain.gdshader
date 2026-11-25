shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// The ground and its cliffs. Colour is per-vertex, baked by ChunkMesher; this textures it.
// Everything is procedural -- there are no texture images -- and tinted by the vertex colours,
// so every biome and season keeps its own palette.
//
//  - Ground: two scales of mottling and a fine speckle across the top.
//  - Wall: rock strata -- noise-warped ledges with cracks -- darkening towards the foot.
//  - Edges: the ground's colour hangs a ragged lip over the top of every wall, a strip of
//    the plateau along the lip wears to dirt, rubble gathers at the foot.
//
// What the mesher hands over per vertex (see ChunkMesher.build):
//  COLOR    own colour; alpha marks snow (1) for the winter tracks.
//  CUSTOM0  the other side's colour: on a wall the ground above it, on the ground the rock.
//  UV       wall: metres along it, height above its foot. Ground: on a lip (x), at a foot (y).
//  UV2      wall: depth below its lip, y = 1. Ground: x = 1 on a ramp.
//
// In winter the tracks left in the snow are drawn too: a texture covering the whole map,
// painted on the CPU by SnowTrails (0 untouched snow, 1 trodden down to the ground). Trodden
// snow is darker and bluer, and its edges tilt the surface normal so a track reads as a groove.

uniform bool snow = false;
uniform sampler2D trails : filter_linear, repeat_disable, hint_default_black;
// World x, z of the texture's corner, then its width and depth in metres.
uniform vec4 trail_rect = vec4(0.0, 0.0, 512.0, 512.0);
// Close to neutral: the scene's colour grade turns any blue in it into a strong blue.
uniform vec3 trodden_color : source_color = vec3(0.66, 0.66, 0.68);
uniform float groove = 2.2;
// What shows where fire has melted the snow away: wet, dark ground.
uniform vec3 melted_color : source_color = vec3(0.28, 0.26, 0.2);

// How strongly each texture shows through its tint.
uniform float ground_detail : hint_range(0.0, 1.0) = 0.13;
uniform float wall_detail : hint_range(0.0, 1.0) = 0.5;
// Metres of ground colour hanging over the top of a wall, on average.
uniform float lip_depth = 0.32;
// How far in from a lip the dirt rim reaches, as a share of a quadrant (1 m).
uniform float rim_width : hint_range(0.0, 1.0) = 0.6;
uniform float rim_strength : hint_range(0.0, 1.0) = 0.6;
// Height of the rubble band at a wall's foot, in metres.
uniform float foot_height = 0.45;
// Metres between rock ledges.
uniform float ledge_spacing = 0.6;

// The worn paths over the whole map (PathNetwork): 1 down the middle of one.
uniform sampler2D paths : filter_linear, repeat_disable, hint_default_black;
uniform float paths_span = 512.0;
uniform vec3 path_color : source_color = vec3(0.5, 0.41, 0.31);

varying vec3 world_position;
varying vec4 other_color;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	other_color = CUSTOM0;
}

float hash(vec2 p) {
	// Wrapped, or the finest detail runs out of float digits across the map and turns to blocks.
	p = mod(p, 289.0);
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float total = 0.0;
	float weight = 0.5;
	for (int i = 0; i < 3; i++) {
		total += weight * noise(p);
		p = p * 2.03 + vec2(17.1, 9.4);
		weight *= 0.5;
	}
	return total / 0.875;
}

// How much of a detail `frequency` to the metre still shows: gone before it is finer than the
// pixels, which would make it shimmer.
float visible(vec2 at, float frequency) {
	vec2 w = fwidth(at);
	return 1.0 - smoothstep(0.2, 0.55, max(w.x, w.y) * frequency);
}

// Distance to the nearest of the points scattered one to a cell (x), the next nearest (y), and a
// random number for the cell (z).
vec3 cells(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float near = 8.0;
	float next = 8.0;
	float id = 0.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 o = vec2(float(x), float(y));
			float h = hash(i + o);
			float d = length(o + vec2(h, hash(i + o + vec2(31.7, 11.3))) * 0.8 + 0.1 - f);
			if (d < near) {
				next = near;
				near = d;
				id = h;
			} else if (d < next) {
				next = d;
			}
		}
	}
	return vec3(near, next, id);
}

// The ground's texture, as a brightness around 1.
// `grass`: how much it is grass, which grows in tufts, rather than rock, sand or snow.
float ground_pattern(vec2 at, float grass) {
	float patches = fbm(at * 0.16) - 0.5;
	float mottle = fbm(at * 1.9) - 0.5;
	float total = patches * 1.1 + mottle * 0.9;
	float near = visible(at, 9.0);
	if (near > 0.0) {
		// Small tufts and scuffs, and a grain finer still.
		float bend = noise(at * 0.8) * 2.5;
		float blades = noise(vec2(at.x * 11.0 + bend, at.y * 4.5)) - 0.5;
		float fleck = smoothstep(0.66, 0.74, noise(at * 6.5 + vec2(bend, 0.0)));
		total += (blades * 0.8 * grass - fleck * mix(0.16, 0.3, grass)) * near;
		total += (noise(at * 23.0) - 0.5) * 0.55 * visible(at, 23.0);
	}
	return 1.0 + total * ground_detail * 2.0;
}

// Trodden dirt: packed earth, grit and small stones, each with its own shade and a dark edge.
float dirt_pattern(vec2 at) {
	float value = 0.95 + (fbm(at * 1.1) - 0.5) * 0.35;
	float near = visible(at, 5.0);
	if (near > 0.0) {
		vec3 stone = cells(at * 3.6);
		float size = 0.16 + 0.22 * fract(stone.z * 7.0);
		float here = step(0.45, fract(stone.z * 13.0));
		float body = (1.0 - smoothstep(size - 0.05, size, stone.x)) * here;
		float ring = (1.0 - smoothstep(size, size + 0.1, stone.x)) * here - body;
		value += (body * (0.1 + 0.16 * fract(stone.z * 29.0)) - ring * 0.2) * near;
		value += (noise(at * 9.0) - 0.5) * 0.16 * visible(at, 9.0);
		float grit = smoothstep(0.68, 0.76, noise(at * 19.0));
		value -= grit * 0.15 * visible(at, 19.0);
	}
	return value;
}

// Rock strata on a wall, from how far along it a point is and its height.
float wall_pattern(float along, float y) {
	float warp = (fbm(vec2(along * 0.3, y * 0.5)) - 0.5) * 0.7;
	float row = (y + warp) / ledge_spacing;
	float layer = fract(row);
	float id = floor(row);
	// Each ledge a slightly different shade, with a dark seam under it.
	float shade = (hash(vec2(id, 3.7)) - 0.5) * 0.35;
	float seam = 1.0 - smoothstep(0.0, 0.12, layer);
	float grain = noise(vec2(along * 1.6, y * 6.0)) - 0.5;
	vec2 face = vec2(along, y);
	grain += (noise(vec2(along * 5.0, y * 17.0)) - 0.5) * 0.7 * visible(face, 17.0);
	grain += (noise(face * 26.0) - 0.5) * 0.4 * visible(face, 26.0);
	// Vertical cracks broken up by the ledges.
	float crack_line = abs(noise(vec2(along * 0.9 + id * 7.3, id)) - 0.5);
	float crack = (1.0 - smoothstep(0.0, 0.035, crack_line)) * step(0.45, hash(vec2(id, floor(along * 0.7))));
	return 1.0 + (shade + grain * 0.3 - seam * 0.45 - crack * 0.4) * wall_detail;
}

void fragment() {
	vec3 color = COLOR.rgb;
	float rough = 0.95;
	bool wall = UV2.y > 0.5;
	if (wall) {
		float along = UV.x;
		float above_foot = UV.y;
		float below_lip = UV2.x;
		vec3 rock = color * wall_pattern(along, world_position.y);
		// Darker towards the foot, where less light reaches.
		rock *= mix(0.72, 1.0, smoothstep(0.0, 1.2, above_foot));
		// Rubble at the foot: dirt blending up the wall a little.
		float rubble = 1.0 - smoothstep(0.0, foot_height, above_foot + (noise(vec2(along * 3.0, 1.0)) - 0.5) * 0.3);
		rock = mix(rock, color * 0.8 * dirt_pattern(vec2(along, world_position.y)), rubble * 0.5);
		// The lip: the ground above hangs over the top of the wall in a ragged fringe, with a
		// dark band of shadow under it.
		float reach = lip_depth * (0.35 + 1.3 * fbm(vec2(along * 2.2, 0.0)));
		float lip = 1.0 - smoothstep(reach - 0.03, reach + 0.03, below_lip);
		float shadow = smoothstep(reach, reach + 0.05, below_lip) * (1.0 - smoothstep(reach + 0.05, reach + 0.35, below_lip));
		rock *= 1.0 - shadow * 0.3;
		vec3 hanging = other_color.rgb * ground_pattern(vec2(along, world_position.y * 3.0), 1.0) * 0.88;
		color = mix(rock, hanging, lip);
	} else {
		vec2 at = world_position.xz;
		color *= ground_pattern(at, smoothstep(0.02, 0.16, COLOR.g - max(COLOR.r * 0.9, COLOR.b)));
		float worn_path = texture(paths, at / paths_span).r;
		// Worked out only where any of it shows: most of the ground is neither edge nor path.
		float pebbly = worn_path > 0.01 || UV.x > 0.01 || UV.y > 0.01 ? dirt_pattern(at) : 1.0;
		vec3 dirt = mix(COLOR.rgb, other_color.rgb, 0.6) * pebbly;
		float ragged = (fbm(at * 1.4) - 0.5) * 0.6;
		// The strip along a cliff's top, worn down to dirt.
		float rim = smoothstep(1.0 - rim_width, 1.0 - rim_width + 0.25, UV.x + ragged);
		color = mix(color, dirt, rim * rim_strength);
		// Rubble scattered at a cliff's foot.
		float foot = smoothstep(0.55, 0.85, UV.y + ragged);
		color = mix(color, dirt * 0.85, foot * 0.6);
		// A worn path: trodden earth, its edge ragged, a little of the ground showing through.
		if (worn_path > 0.01) {
			// Ragged at every scale: wandering, then bites out of it, then crumbs.
			float edge = worn_path + (fbm(at * 0.9) - 0.5) * 0.5 + (fbm(at * 4.5) - 0.5) * 0.28;
			edge += (noise(at * 15.0) - 0.5) * 0.14 * visible(at, 15.0);
			float tread = smoothstep(0.42, 0.5, edge);
			float wear = smoothstep(0.42, 0.95, edge);
			vec3 earth = mix(path_color, COLOR.rgb * 0.8, 0.3) * pebbly;
			earth *= 0.8 + 0.2 * smoothstep(0.42, 0.62, edge);
			earth *= 1.0 + 0.06 * wear;
			// A dark line where it is trodden below the ground beside it.
			color *= 1.0 - 0.22 * smoothstep(0.3, 0.42, edge) * (1.0 - tread);
			color = mix(color, earth, tread * 0.95);
		}
	}
	if (snow && COLOR.a > 0.5 && !wall) {
		vec2 uv = (world_position.xz - trail_rect.xy) / trail_rect.zw;
		vec2 texel = 1.0 / vec2(textureSize(trails, 0));
		vec2 marks = texture(trails, uv).rg;
		float trodden = marks.r;
		float dx = texture(trails, uv + vec2(texel.x, 0.0)).r - texture(trails, uv - vec2(texel.x, 0.0)).r;
		float dz = texture(trails, uv + vec2(0.0, texel.y)).r - texture(trails, uv - vec2(0.0, texel.y)).r;
		color = mix(color, color * trodden_color, trodden * 0.6);
		color = mix(color, melted_color, smoothstep(0.1, 0.8, marks.g));
		// The track is a dip: its walls face inwards, towards where the snow was pressed down.
		vec3 tilt = vec3(dx, 0.0, dz) * groove;
		NORMAL = normalize(NORMAL + (VIEW_MATRIX * vec4(tilt, 0.0)).xyz);
	}
	ALBEDO = color;
	ROUGHNESS = rough;
}
