// The Firth of Clyde: moving waves, colour that deepens offshore, foam at the shore.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_back, depth_draw_always;

uniform sampler2D depth_texture : hint_depth_texture, filter_linear_mipmap;
uniform vec3 shallow_colour : source_color = vec3(0.16, 0.42, 0.45);
uniform vec3 deep_colour : source_color = vec3(0.03, 0.13, 0.22);
uniform float clarity_metres = 6.0;     // how deep you can see into the water
uniform float wave_strength = 0.35;

varying vec3 world_pos;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float waves(vec2 p, float t) {
	float w = 0.0;
	w += value_noise(p / 9.0 + vec2(t * 0.15, t * 0.08)) * 0.5;
	w += value_noise(p / 4.0 - vec2(t * 0.22, -t * 0.1)) * 0.3;
	w += value_noise(p / 1.7 + vec2(-t * 0.35, t * 0.3)) * 0.2;
	return w;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Wave normals from the slope of the moving noise.
	vec2 p = world_pos.xz;
	float t = TIME;
	float e = 0.5;
	float hc = waves(p, t);
	float hx = waves(p + vec2(e, 0.0), t);
	float hz = waves(p + vec2(0.0, e), t);
	vec3 n_world = normalize(vec3((hc - hx) * wave_strength * 4.0, 1.0, (hc - hz) * wave_strength * 4.0));
	NORMAL = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);

	// How much water lies between the surface and the ground behind it.
	float depth = texture(depth_texture, SCREEN_UV).r;
	vec4 behind = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	behind.xyz /= behind.w;
	float thickness = max(0.0, VERTEX.z - behind.z);

	float deepness = clamp(thickness / clarity_metres, 0.0, 1.0);
	vec3 colour = mix(shallow_colour, deep_colour, deepness);

	// Foam where the water is very shallow, broken up by the waves.
	float foam = (1.0 - smoothstep(0.0, 1.6, thickness)) * smoothstep(0.35, 0.65, hc + 0.2 * sin(t * 1.5 + p.x * 0.05));
	colour = mix(colour, vec3(0.92, 0.95, 0.95), foam * 0.8);

	ALBEDO = colour;
	ALPHA = mix(0.55, 0.96, deepness);
	ROUGHNESS = mix(0.06, 0.4, foam);
	METALLIC = 0.0;
	SPECULAR = 0.65;
}
