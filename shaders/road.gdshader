// Tarmac with kerbs and a dashed centre line.
// UV.x runs across the road (0 to 1), UV.y along it in metres.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform bool use_texture = false;
uniform sampler2D tarmac_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 tarmac_colour : source_color = vec3(0.17, 0.17, 0.18);
uniform vec3 kerb_colour : source_color = vec3(0.62, 0.61, 0.58);

varying vec3 world_pos;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 colour = tarmac_colour;
	if (use_texture) {
		colour = texture(tarmac_tex, world_pos.xz / 4.0).rgb * 0.8;
	} else {
		colour *= 0.9 + 0.2 * hash(floor(world_pos.xz * 4.0));
	}
	float across = UV.x;
	// Pavements along both edges.
	float kerb = clamp(step(across, 0.14) + step(0.86, across), 0.0, 1.0);
	colour = mix(colour, kerb_colour, kerb);
	// Dashed white centre line on straight sections (UV2.x = 1).
	float dash = step(0.5, fract(UV.y / 6.25)) * step(abs(across - 0.5), 0.012) * UV2.x;   // 4 dashes per half tile
	colour = mix(colour, vec3(0.9), dash);
	ALBEDO = colour;
	ROUGHNESS = mix(0.88, 0.7, kerb);
}
