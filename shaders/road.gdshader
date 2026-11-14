// Tarmac with kerbs and white lines: a road, an avenue or a motorway.
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
	// The kind of road (0 road, 1 avenue, 2 motorway) comes with the centre line
	// flag: UV2.x = flag + 2 x kind. Widths as ROAD_HALF_WIDTHS in world3d.gd.
	int kind = int(floor(UV2.x * 0.5 + 0.01));
	float full = UV2.x - float(kind) * 2.0;      // 1 on full pieces of road, 0 on junction squares and kerbs
	float width = kind == 0 ? 12.0 : (kind == 1 ? 20.0 : 28.0);
	float across = UV.x;
	float m = abs(across - 0.5) * width;         // metres from the middle of the road
	// Pavements along both edges (a motorway has none).
	float kerb = kind == 2 ? 0.0 : step(width * 0.5 - (kind == 0 ? 1.68 : 2.2), m);
	colour = mix(colour, kerb_colour, kerb);
	// Down the middle: an avenue's planted strip (grass between kerbs), a
	// motorway's concrete (the barrier stands on it).
	float median = 0.0;
	if (kind == 1) {
		median = step(m, 1.5) * full;
		vec3 grass = vec3(0.10, 0.17, 0.05) * (0.85 + 0.3 * hash(floor(world_pos.xz * 3.0)));
		colour = mix(colour, mix(grass, kerb_colour, step(1.25, m)), median);
	} else if (kind == 2) {
		median = step(m, 0.9) * full;
		colour = mix(colour, kerb_colour * 0.75, median);
	}
	float clear_road = (1.0 - kerb) * (1.0 - median);
	// Roads leading into a junction: a give-way line (UV2.y 0.5, quiet streets)
	// and, where it's busy (UV2.y 1), a zebra crossing a few metres back.
	float zebra_zone = step(0.75, UV2.y) * step(12.5, UV.y) * step(UV.y, 16.5) * clear_road;
	float bars = step(0.5, fract(across * width / 1.1));
	colour = mix(colour, vec3(0.92), zebra_zone * bars);
	// Give-way line where the road meets the junction.
	float give_way = step(0.25, UV2.y) * step(17.5, UV.y) * step(UV.y, 17.9) * clear_road;
	colour = mix(colour, vec3(0.92), give_way);
	// White lines on full pieces, not on the crossing: a road's dashed centre
	// line; an avenue's lane lines; a motorway's lane lines and solid edge lines.
	float dashes = step(0.5, fract(UV.y / 6.25));   // 4 dashes per half tile
	float dash = 0.0;
	if (kind == 0) {
		dash = dashes * step(m, 0.144);
	} else if (kind == 1) {
		dash = dashes * step(abs(m - 4.65), 0.07);
	} else {
		dash = dashes * (step(abs(m - 5.0), 0.08) + step(abs(m - 8.5), 0.08))
			+ step(abs(m - 1.35), 0.09) + step(abs(m - 12.0), 0.09);
	}
	dash *= full;
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
	// warm light on the road beneath each one; a motorway's stand in the middle
	// and light both sides. Only on full road pieces.
	if (night > 0.01 && full > 0.5) {
		float x = (across - 0.5) * width;
		float lamp = kind == 0 ? 5.16 : (kind == 1 ? 9.2 : 0.0);
		float reach = kind == 0 ? 8.0 : (kind == 1 ? 10.0 : 14.0);
		float along_left = mod(UV.y, 25.0) - 12.5;
		float along_right = mod(UV.y + 12.5, 25.0) - 12.5;
		float d_left = length(vec2(x + lamp, along_left));
		float d_right = length(vec2(x - lamp, along_right));
		float d = min(d_left, d_right);
		float pool = 1.0 - smoothstep(0.0, reach, d);
		float bulb = (1.0 - smoothstep(0.35, 0.6, d)) * (kind == 2 ? 0.0 : 1.0);
		EMISSION += vec3(1.0, 0.62, 0.28) * (pool * pool * 0.5 + bulb * 1.8) * night;
	}
}
