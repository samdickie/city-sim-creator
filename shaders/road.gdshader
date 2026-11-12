// Tarmac with kerbs and a dashed centre line.
// UV.x runs across the road (0 to 1), UV.y along it in metres.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform bool use_texture = false;
uniform sampler2D tarmac_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 tarmac_colour : source_color = vec3(0.17, 0.17, 0.18);
uniform vec3 kerb_colour : source_color = vec3(0.62, 0.61, 0.58);
uniform float night = 0.0;          // 0 = day, 1 = night: street lights come on
// The Traffic map view: the road surface takes its tile's colour from the overlay
// map (congestion), so the network reads clearly from afar. Other views leave it.
uniform bool overlay_on = false;
uniform sampler2D overlay_map : source_color, filter_nearest;
uniform vec2 map_size = vec2(7000.0, 6500.0);   // playable area in metres

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
	// Roads leading into a junction: a give-way line (UV2.y 0.5, quiet streets)
	// and, where it's busy (UV2.y 1), a zebra crossing a few metres back.
	float zebra_zone = step(0.75, UV2.y) * step(12.5, UV.y) * step(UV.y, 16.5) * (1.0 - kerb);
	float bars = step(0.5, fract(across * 12.0 / 1.1));
	colour = mix(colour, vec3(0.92), zebra_zone * bars);
	// Give-way line where the road meets the junction.
	float give_way = step(0.25, UV2.y) * step(17.5, UV.y) * step(UV.y, 17.9) * (1.0 - kerb);
	colour = mix(colour, vec3(0.92), give_way);
	// Dashed white centre line on straight sections (UV2.x = 1), not on the crossing.
	float dash = step(0.5, fract(UV.y / 6.25)) * step(abs(across - 0.5), 0.012) * UV2.x;   // 4 dashes per half tile
	colour = mix(colour, vec3(0.9), dash * (1.0 - zebra_zone));
	if (overlay_on) {
		vec4 ov = texture(overlay_map, world_pos.xz / map_size);
		if (ov.a > 0.01) {
			// Tarmac fully in the colour, pavements a shade lighter, markings faint.
			vec3 lit = ov.rgb * mix(0.95, 1.15, kerb);
			colour = mix(lit, colour, (zebra_zone * bars + give_way + dash) * 0.25);
			EMISSION = ov.rgb * 0.18;               // still readable at night
		}
	}
	ALBEDO = colour;
	ROUGHNESS = mix(0.88, 0.7, kerb);

	// Street lights every 25 m along both pavements (staggered), with a pool of
	// warm light on the road beneath each one. Only on full road pieces (UV2.x = 1).
	if (night > 0.01 && UV2.x > 0.5) {
		float road_width = 12.0;
		float along_left = mod(UV.y, 25.0) - 12.5;
		float along_right = mod(UV.y + 12.5, 25.0) - 12.5;
		float d_left = length(vec2((across - 0.07) * road_width, along_left));
		float d_right = length(vec2((across - 0.93) * road_width, along_right));
		float d = min(d_left, d_right);
		float pool = 1.0 - smoothstep(0.0, 8.0, d);
		float bulb = 1.0 - smoothstep(0.35, 0.6, d);
		EMISSION += vec3(1.0, 0.62, 0.28) * (pool * pool * 0.5 + bulb * 1.8) * night;
	}
}
