shader_type canvas_item;
// Pixel-art gauge drawn by PixelBar: outline, recessed track, three-tone bevelled
// fill, scrolling charge stripes, stopped-hatch, a pulse,
// a sweeping sheen and a white hit flash. Every size here is in screen pixels;
// `px` is the art-pixel size (bevel rows, outline) so the bar stays crisp.

uniform vec2 rect_size = vec2(100.0, 12.0);
uniform float px = 2.0;
uniform float ratio : hint_range(0.0, 1.0) = 1.0;
uniform vec4 fill_color : source_color = vec4(0.15, 0.7, 0.25, 1.0);
uniform vec4 track_color : source_color = vec4(0.09, 0.09, 0.11, 1.0);
uniform vec4 outline_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float stripe_strength = 0.0;        // diagonal charge stripes on the fill
uniform float stripe_speed = 24.0;          // px / second
uniform float hatch = 0.0;                  // 1 = stopped: grey diagonal hatch over the fill
uniform float pulse = 0.0;                  // brightness pulse amplitude on the fill
uniform float pulse_speed = 6.0;
uniform float sheen_pos = -1.0;             // 0..1 along the fill; < 0 = none (PixelBar animates it)
uniform float sheen_loop = 0.0;             // 1 = sheen sweeps on its own, repeating (ATB ready)
uniform float flash : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec2 p = floor(UV * rect_size);
	vec2 inner = rect_size - vec2(2.0 * px);
	vec2 q = p - vec2(px);
	vec4 col;
	if (q.x < 0.0 || q.y < 0.0 || q.x >= inner.x || q.y >= inner.y) {
		col = outline_color;
	} else {
		float fill_w = floor(inner.x * ratio);
		bool filled = q.x < fill_w;
		if (filled) {
			vec3 c = fill_color.rgb;
			// Bevel: a lit top row, a shaded bottom row, a bright leading edge.
			if (q.y < px) c = mix(c, vec3(1.0), 0.35);
			else if (q.y >= inner.y - px) c *= 0.6;
			if (q.x >= fill_w - px && ratio < 1.0) c = mix(c, vec3(1.0), 0.25);
			if (stripe_strength > 0.0) {
				float band = floor((q.x - q.y + TIME * stripe_speed) / (px * 3.0));
				if (mod(band, 2.0) < 1.0) c = mix(c, vec3(1.0), stripe_strength);
			}
			if (hatch > 0.0) {
				float hb = floor((q.x + q.y) / (px * 2.0));
				c = mod(hb, 2.0) < 1.0 ? vec3(0.42) : vec3(0.3);
			}
			if (pulse > 0.0) c *= 1.0 + pulse * (0.5 + 0.5 * sin(TIME * pulse_speed));
			float s = sheen_pos;
			if (sheen_loop > 0.0) s = fract(TIME * 0.7) * 1.6 - 0.3;
			if (s >= -0.5) {
				float x = q.x / max(inner.x, 1.0);
				// Slanted band, a few art pixels wide.
				float d = abs(x - s - (q.y / max(inner.x, 1.0)));
				if (d < px * 2.5 / max(inner.x, 1.0)) c = mix(c, vec3(1.0), 0.55);
			}
			col = vec4(c, fill_color.a);
		} else {
			vec3 c = track_color.rgb;
			if (q.y < px) c *= 0.55;   // recessed: the track's top row sits in shadow
			col = vec4(c, track_color.a);
		}
		col.rgb = mix(col.rgb, vec3(1.0), flash);
	}
	COLOR = col;
}
