shader_type spatial;
render_mode cull_back, specular_disabled;

// An ordinary material drawn in comic tones (comic.gdshaderinc). ComicLook fills it in from the
// StandardMaterial3D it stands in for.

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable, hint_default_white;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform bool use_vertex_color = false;
uniform vec3 emission_color : source_color = vec3(0.0);
uniform vec2 uv_scale = vec2(1.0);
uniform vec2 uv_offset = vec2(0.0);

void fragment() {
	vec3 colour = texture(albedo_texture, UV * uv_scale + uv_offset).rgb * albedo_color.rgb;
	ALBEDO = use_vertex_color ? colour * COLOR.rgb : colour;
	EMISSION = emission_color;
	ROUGHNESS = 1.0;
}

#include "res://scripts/visual/comic.gdshaderinc"
