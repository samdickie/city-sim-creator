// The Firth of Clyde: clear pale turquoise over the sand in the shallows,
// deepening through teal to blue offshore; gentle moving ripples and swell, a
// soft sheen of sky, and lines of surf sliding up the beach.
// Depth is measured from the ground behind the water (the depth texture), so
// piers, ships and the shore all get their own shallows and foam.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_back, depth_draw_always;

uniform sampler2D depth_texture : hint_depth_texture, filter_linear_mipmap;
uniform vec3 shallow_colour : source_color = vec3(0.40, 0.62, 0.56);   // over sand, a metre deep
uniform vec3 mid_colour : source_color = vec3(0.13, 0.34, 0.40);
uniform vec3 deep_colour : source_color = vec3(0.05, 0.15, 0.25);
uniform vec3 sky_colour : source_color = vec3(0.62, 0.74, 0.86);      // the sheen of sky on the water
uniform vec3 foam_colour : source_color = vec3(0.90, 0.93, 0.92);
uniform float clarity = 0.42;           // how quickly the water hides the seabed (per metre)
uniform float wave_strength = 0.5;
uniform float day = 1.0;                // 1 in daylight, 0 at night (set by world3d.gd)

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

float ripples(vec2 p, float t, float detail) {
	// Wind ripples in three sizes drifting different ways, plus a slow swell.
	float w = 0.0;
	w += value_noise(p / 11.0 + vec2(t * 0.13, t * 0.07)) * 0.45;
	w += value_noise(p / 4.3 - vec2(t * 0.21, -t * 0.12)) * 0.3 * detail;
	w += value_noise(p / 1.6 + vec2(-t * 0.37, t * 0.31)) * 0.18 * detail;
	w += sin(dot(p, vec2(0.031, 0.022)) - t * 0.9) * 0.12;
	return w;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz;
	float t = TIME;
	float dist = length(VERTEX);
	float detail = 1.0 - smoothstep(600.0, 2500.0, dist);      // calm the fine ripples far away

	// Wave normals from the slope of the moving ripples.
	float e = 0.6;
	float hc = ripples(p, t, detail);
	float hx = ripples(p + vec2(e, 0.0), t, detail);
	float hz = ripples(p + vec2(0.0, e), t, detail);
	float strength = wave_strength * mix(0.35, 1.0, detail);
	vec3 n_world = normalize(vec3((hc - hx) * strength * 3.0, 1.0, (hc - hz) * strength * 3.0));
	NORMAL = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);

	// How deep the water is here (straight down to the ground behind it).
	float raw = texture(depth_texture, SCREEN_UV).r;
	vec4 behind = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, raw, 1.0);
	behind.xyz /= behind.w;
	vec3 floor_world = (INV_VIEW_MATRIX * vec4(behind.xyz, 1.0)).xyz;
	float depth = max(world_pos.y - floor_world.y, 0.0);
	float thickness = max(VERTEX.z - behind.z, 0.0);          // along the view ray

	// Colour by depth: turquoise shallows, teal, then deep blue.
	vec3 colour = mix(shallow_colour, mid_colour, smoothstep(0.5, 3.0, depth));
	colour = mix(colour, deep_colour, smoothstep(3.0, 10.0, depth));
	colour *= 0.94 + 0.12 * hc;
	float seen = 1.0 - exp(-thickness * clarity);             // how much the water hides
	float alpha = clamp(seen, 0.12, 0.97);

	// A sheen of sky, stronger towards the horizon (Fresnel).
	vec3 view_dir = normalize(-VERTEX);
	float fresnel = pow(1.0 - clamp(dot(NORMAL, view_dir), 0.0, 1.0), 4.0);
	colour = mix(colour, sky_colour, fresnel * 0.55 * day);

	// Surf: a thin broken line at the water's edge and soft lines of foam
	// sliding up the beach.
	float breakup = value_noise(p / 6.0 + vec2(t * 0.2, 0.0)) * 0.6 + value_noise(p / 2.2 - t * 0.3) * 0.4;
	float edge = (1.0 - smoothstep(0.0, 0.22, depth)) * smoothstep(0.25, 0.55, breakup);
	float phase = depth * 2.6 - t * 0.45 + value_noise(p / 40.0) * 3.0;
	float lines = smoothstep(0.78, 0.97, sin(phase * 6.2832) * 0.5 + 0.5)
		* (1.0 - smoothstep(0.15, 1.3, depth)) * smoothstep(0.35, 0.7, breakup);
	float foam = clamp(edge * 0.8 + lines * 0.55, 0.0, 1.0) * mix(1.0, 0.4, 1.0 - detail);
	colour = mix(colour, foam_colour, foam);
	alpha = max(alpha, foam * 0.9);

	ALBEDO = colour;
	ALPHA = alpha;
	ROUGHNESS = mix(0.08, 0.5, foam);
	METALLIC = 0.0;
	SPECULAR = 0.6;
}
