// Ground of the whole map: grass, beach sand and rock blended by height and slope,
// plus the zone colours and warnings painted on top.
// Uses photo textures when they're provided, otherwise natural-looking noise.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec2 map_size = vec2(7000.0, 6500.0);      // playable area in metres
uniform sampler2D zone_map : source_color, filter_nearest;  // zone tint per tile (alpha = strength)
uniform sampler2D warn_map : filter_nearest;        // R = no road, G = no power
uniform float time_now = 0.0;

uniform bool use_textures = false;
uniform sampler2D grass_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sand_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float texture_metres = 6.0;                 // how many metres one texture tile covers

uniform vec3 grass_light : source_color = vec3(0.42, 0.55, 0.26);
uniform vec3 grass_dark : source_color = vec3(0.24, 0.36, 0.15);
uniform vec3 sand_colour : source_color = vec3(0.80, 0.72, 0.55);
uniform vec3 rock_colour : source_color = vec3(0.42, 0.40, 0.36);
uniform vec3 seabed_colour : source_color = vec3(0.55, 0.50, 0.38);

varying vec3 world_pos;
varying vec3 world_normal;

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

float fbm(vec2 p) {
	float total = 0.0;
	float amp = 0.5;
	for (int k = 0; k < 5; k++) {
		total += value_noise(p) * amp;
		p *= 2.03;
		amp *= 0.5;
	}
	return total;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 p = world_pos.xz;
	float h = world_pos.y;
	float slope = 1.0 - clamp(world_normal.y, 0.0, 1.0);

	// Base materials.
	vec3 grass;
	vec3 sand;
	vec3 rock;
	if (use_textures) {
		vec2 uv = p / texture_metres;
		// Two scales mixed together hide the repeating pattern.
		grass = mix(texture(grass_tex, uv).rgb, texture(grass_tex, uv * 0.137).rgb, 0.35);
		sand = texture(sand_tex, uv).rgb;
		rock = texture(rock_tex, uv * 0.5).rgb;
	} else {
		float n = fbm(p / 40.0);
		float fine = value_noise(p / 3.0);
		grass = mix(grass_dark, grass_light, smoothstep(0.25, 0.75, n)) * (0.92 + 0.16 * fine);
		sand = sand_colour * (0.94 + 0.12 * value_noise(p / 2.0));
		rock = rock_colour * (0.85 + 0.3 * fbm(p / 6.0));
	}
	// Large patches of lighter and darker ground, like fields and fairways.
	grass *= 0.85 + 0.3 * fbm(p / 400.0);

	// Beach near sea level, rock on steep slopes, seabed under water.
	float edge = (fbm(p / 25.0) - 0.5) * 2.0;
	float beach = 1.0 - smoothstep(1.2, 3.5, h + edge);
	vec3 colour = mix(grass, sand, beach);
	colour = mix(colour, rock, smoothstep(0.35, 0.6, slope));
	colour = mix(colour, seabed_colour * 0.7, 1.0 - smoothstep(-3.0, 0.0, h));

	// Zone colours and warnings, one map tile at a time.
	vec2 tile_uv = p / map_size;
	bool inside = tile_uv.x >= 0.0 && tile_uv.y >= 0.0 && tile_uv.x <= 1.0 && tile_uv.y <= 1.0;
	if (inside) {
		vec4 zone = texture(zone_map, tile_uv);
		colour = mix(colour, zone.rgb, zone.a);
		vec4 warn = texture(warn_map, tile_uv);
		float stripes = step(0.5, fract((p.x + p.y) / 8.0));
		colour = mix(colour, vec3(0.05), warn.r * stripes * 0.55);           // no road: dark stripes
		// (No power is shown by a floating icon instead of a ground colour.)
	} else {
		// Outside the playable area: muted, so the edge of the map is clear.
		colour = mix(colour, vec3(dot(colour, vec3(0.33))), 0.55) * 0.75;
	}

	ALBEDO = colour;
	ROUGHNESS = mix(0.95, 0.75, beach);
	SPECULAR = 0.3;
}
