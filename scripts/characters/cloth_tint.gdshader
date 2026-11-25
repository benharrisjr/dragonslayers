shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// A hero's own texture, with their clothes dyed to show their armour level.
//
// The KayKit adventurers are painted from a palette atlas of flat swatches, and what is cloth
// differs from hero to hero -- the knight's cape is red, the mage's robe purple, the rogue's
// hood green. What they share is how the swatches read: cloth is strongly coloured; skin, hair,
// leather and wood all sit in one orange-brown band of hue; metal and white linen are grey.
// So: strongly coloured texels outside the brown band are dyed the armour's colour outright,
// grey and white ones are washed with it more lightly (so a red cloak dyed red still shows the
// upgrade), and everything brown -- faces, hands, belts, boots, hair -- is left alone.

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform float roughness = 1.0;
uniform float metallic = 0.0;
// The hue to dye to, 0..1 (0.6 blue, 0.0 red).
uniform float dye_hue = 0.6;
uniform float cloth_strength = 1.0;
uniform float plain_strength = 0.4;

vec3 rgb_to_hsv(vec3 c) {
	vec4 k = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, k.wz), vec4(c.gb, k.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsv_to_rgb(vec3 c) {
	vec4 k = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
	vec3 p = abs(fract(c.xxx + k.xyz) * 6.0 - k.www);
	return c.z * mix(k.xxx, clamp(p - k.xxx, 0.0, 1.0), c.y);
}

void fragment() {
	vec3 linear_colour = texture(albedo_texture, UV).rgb * albedo_color.rgb;
	// Judged in the colours as painted, not as lit.
	vec3 painted = pow(max(linear_colour, vec3(0.0)), vec3(1.0 / 2.2));
	vec3 hsv = rgb_to_hsv(painted);
	// Skin, hair, leather and wood: the orange-brown band.
	float earthy = smoothstep(0.0, 0.03, hsv.x) * (1.0 - smoothstep(0.13, 0.16, hsv.x));
	float cloth = smoothstep(0.2, 0.35, hsv.y) * (1.0 - earthy);
	// Grey and white -- metal, linen -- but not the near-black of eyes and shadowed hair.
	float plain = (1.0 - smoothstep(0.12, 0.25, hsv.y)) * smoothstep(0.15, 0.35, hsv.z);
	vec3 dyed = hsv_to_rgb(vec3(dye_hue, max(hsv.y, 0.65), hsv.z));
	vec3 washed = painted * hsv_to_rgb(vec3(dye_hue, 0.45, 1.0));
	vec3 result = mix(painted, dyed, cloth * cloth_strength);
	result = mix(result, washed, plain * plain_strength * (1.0 - cloth));
	ALBEDO = pow(result, vec3(2.2));
	ROUGHNESS = roughness;
	METALLIC = metallic;
}
