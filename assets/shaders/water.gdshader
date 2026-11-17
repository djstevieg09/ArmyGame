shader_type spatial;
render_mode blend_mix, cull_back, depth_draw_opaque;

uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec4 deep : source_color = vec4(0.03, 0.11, 0.12, 1.0);
uniform vec4 shallow : source_color = vec4(0.1, 0.2, 0.17, 1.0);
uniform float speed = 0.03;

varying vec3 wpos;
varying float shore;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	shore = COLOR.a;
	VERTEX.y += sin(wpos.x * 1.7 + TIME * 1.3) * 0.01 + cos(wpos.z * 1.3 + TIME) * 0.01;
}

void fragment() {
	vec2 uv = wpos.xz * 0.18;
	vec3 n1 = texture(normal_tex, uv + vec2(TIME * speed, TIME * speed * 0.6)).rgb;
	vec3 n2 = texture(normal_tex, uv * 1.7 - vec2(TIME * speed * 0.8, -TIME * speed * 0.3)).rgb;
	NORMAL_MAP = normalize(n1 + n2 - 1.0) * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 0.6;
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	vec3 col = mix(deep.rgb, shallow.rgb, shore);
	ALBEDO = col;
	ROUGHNESS = 0.06;
	METALLIC = 0.0;
	SPECULAR = 0.35;
	float foam = smoothstep(0.55, 0.8, shore) * (1.0 - smoothstep(0.9, 1.0, shore)) * (0.6 + 0.4 * sin(TIME * 2.0 + wpos.x * 3.0 + wpos.z * 2.0));
	ALBEDO = mix(ALBEDO, vec3(0.9, 0.95, 0.95), foam * 0.55);
	ALPHA = clamp(mix(0.92, 0.6, shore) + fres * 0.1, 0.0, 1.0);
}
