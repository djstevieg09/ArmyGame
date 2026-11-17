shader_type spatial;
// Two photo-scanned ground surfaces blended by vertex colour (R = second
// surface, G = wetness), with a second, larger sample to hide tiling.
render_mode cull_back;

uniform sampler2D a_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D a_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D a_rough : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D b_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D b_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D b_rough : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D macro_noise : hint_default_white, filter_linear, repeat_enable;
uniform vec4 tint_a : source_color = vec4(1.0);
uniform vec4 tint_b : source_color = vec4(1.0);
uniform float scale_a = 0.3;
uniform float scale_b = 0.3;

varying vec3 wpos;
varying vec4 vcol;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vcol = COLOR;
}

// mix a normal and a rotated, larger sample to break up repetition
#define UV2(uv) (mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * (uv) * 0.37 + vec2(0.31, 0.17))
#define tri(t, uv) mix(texture(t, uv), texture(t, UV2(uv)), 0.35)

void fragment() {
	vec2 uv = wpos.xz;
	float macro = texture(macro_noise, uv * 0.025).r;
	float macro2 = texture(macro_noise, uv * 0.11 + 0.5).r;
	float w = smoothstep(0.35, 0.65, vcol.r + (macro2 - 0.5) * 0.55);
	vec3 ca = tri(a_albedo, uv * scale_a).rgb * tint_a.rgb;
	vec3 cb = tri(b_albedo, uv * scale_b).rgb * tint_b.rgb;
	vec3 col = mix(ca, cb, w);
	col *= mix(0.86, 1.1, macro);
	col *= 1.0 - vcol.g * 0.38;
	ALBEDO = col;
	vec3 na = tri(a_normal, uv * scale_a).rgb;
	vec3 nb = tri(b_normal, uv * scale_b).rgb;
	NORMAL_MAP = mix(na, nb, w);
	NORMAL_MAP_DEPTH = 1.2;
	float ra = tri(a_rough, uv * scale_a).r;
	float rb = tri(b_rough, uv * scale_b).r;
	ROUGHNESS = mix(mix(ra, rb, w), 0.25, vcol.g * 0.7);
	SPECULAR = 0.35;
}
