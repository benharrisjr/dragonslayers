// Comic cel lighting, after the "Comic Cell" visual shader on godotshaders.com (CC0): a surface is
// one of three flat tones -- shaded, between, lit -- by how far it faces the light, with a band of
// the middle one `between_size` either side of `between_transfer`, and a hard-edged rim light on
// the side away from it.
//
// The original faces everything towards a fixed direction in view space and draws it unlit. Here
// the light is the scene's sun, so the tones hold still as the camera turns and shadows fall in
// the shaded tone; and the three tones are tints of the surface's own colour. Ambient and the
// other lights (torches, fire) add to it as usual.
//
// Included at the end of a shader, after its own fragment().

uniform vec3 tone_lit : source_color = vec3(0.76, 0.75, 0.73);
uniform vec3 tone_between : source_color = vec3(0.5, 0.42, 0.38);
uniform vec3 tone_shaded : source_color = vec3(0.06, 0.03, 0.05);
uniform float between_transfer = 0.12;
uniform float between_size : hint_range(0.0, 0.7) = 0.14;
uniform vec3 rim_color : source_color = vec3(0.0, 0.6, 0.6);
uniform float fresnel_power = 3.0;
uniform float rim_strength_comic = 1.0;

void light() {
	float facing = dot(NORMAL, LIGHT);
	if (LIGHT_IS_DIRECTIONAL) {
		// In shadow counts as facing away. Softened just enough not to shimmer at the edges.
		float value = mix(min(facing, between_transfer - between_size - 0.1), facing,
				smoothstep(0.35, 0.65, ATTENUATION));
		float soft = max(fwidth(value), 0.004);
		vec3 tone = mix(tone_shaded, tone_between,
				smoothstep(-soft, soft, value - (between_transfer - between_size)));
		tone = mix(tone, tone_lit, smoothstep(-soft, soft, value - (between_transfer + between_size)));
		DIFFUSE_LIGHT += tone * LIGHT_COLOR / PI;
		float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), fresnel_power);
		SPECULAR_LIGHT += rim_color * smoothstep(0.22, 0.335, fresnel) * clamp(-facing, 0.0, 1.0)
				* rim_strength_comic * LIGHT_COLOR / PI;
	} else {
		// Lamps: pools of light in a few soft-edged steps.
		float lamp = sqrt(clamp(ATTENUATION, 0.0, 1.0)) * smoothstep(-0.1, 0.15, facing) * 6.0;
		float stepped = (floor(lamp) + smoothstep(0.3, 0.7, fract(lamp))) / 6.0;
		DIFFUSE_LIGHT += stepped * stepped * LIGHT_COLOR / PI;
	}
}
