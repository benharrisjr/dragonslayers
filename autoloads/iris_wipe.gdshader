shader_type canvas_item;

// Circle wipe: opaque black everywhere farther than `radius` from `center`.
// Both are in canvas pixels (the project design space), as is `size`, the
// rect's own size. Positions come from UV * size rather than FRAGCOORD, which
// is in physical window pixels and so drifts off-centre the moment the window
// is larger than the design resolution. Tween radius from the corner distance
// down to 0 to iris the screen shut, or the reverse to open it. See
// ScreenTransitions.
uniform float radius = 0.0;
uniform vec2 center = vec2(0.0);
uniform vec2 size = vec2(1.0);

void fragment() {
	float d = distance(UV * size, center);
	COLOR = vec4(0.0, 0.0, 0.0, step(radius, d));
}
