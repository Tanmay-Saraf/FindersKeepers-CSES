shader_type spatial;
render_mode unshaded, cull_disabled;

uniform sampler2D card_texture : source_color, filter_nearest;
uniform float exposure = 1.28;
uniform float shadow_lift = 0.045;

void fragment() {
	vec4 card = texture(card_texture, UV);
	ALBEDO = clamp(pow(card.rgb, vec3(0.82)) * exposure + vec3(shadow_lift), vec3(0.0), vec3(1.0));
	ALPHA = card.a;
}
