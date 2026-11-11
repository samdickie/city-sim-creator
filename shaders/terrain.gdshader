// The ground of the whole map, coloured by the lie of the land: lush low ground,
// paler dry slopes and hilltops, damp dark hollows, rough hill grazing, rock on
// steep faces; a patchwork of fields with hedges in open country; sand beaches
// with wet sand at the waterline and dune grass behind; dark ground under the
// woods. Zone colours, warnings and map overlays are painted on top.
// The mesh is a flat grid: the vertex shader lifts it to the height field (see
// world3d.gd _build_height_field), the same one height_at() reads.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec2 map_size = vec2(7000.0, 6500.0);      // playable area in metres
uniform sampler2D zone_map : source_color, filter_nearest;  // zone tint per tile (alpha = strength)
uniform sampler2D warn_map : filter_nearest;        // R = no road, G = no power
uniform float time_now = 0.0;
uniform sampler2D overlay_map : source_color, filter_nearest;  // map overlay colour per tile
uniform bool overlay_on = false;                    // showing a map overlay (land value, power...)

// The shape of the ground.
uniform sampler2D height_map : filter_nearest, repeat_disable;   // R = height, G = land mask (0 sea, 1 land)
uniform vec2 grid_origin = vec2(0.0);               // world x, z of height sample (0, 0)
uniform float grid_step = 12.5;                     // metres between samples
uniform ivec2 grid_size = ivec2(2, 2);
uniform float shore_level = 0.36;                   // land mask value at the waterline
uniform sampler2D land_map : filter_linear, repeat_disable;   // per tile: R = damp, G = woods, B = near the sea
uniform vec2 land_origin = vec2(0.0);               // world x, z of land_map's corner
uniform vec2 land_size = vec2(1.0);                 // land_map's size in metres
uniform sampler2D built_map : filter_linear, repeat_disable;  // per map tile: R = built on
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;  // four smooth noises (RGBA)
uniform float normal_boost = 2.2;                   // slopes catch the light more, so low hills read

// The field pattern (the same numbers as world3d.gd _field_at, which plants the hedgerow trees).
uniform float field_angle = 0.38;
uniform float field_row = 165.0;
uniform float field_col = 225.0;
uniform float field_jitter = 0.55;
uniform float field_wobble = 9.0;
uniform float field_split = 0.35;
uniform float field_hedge = 0.72;
uniform float plant_chance = 0.1;
uniform float plant_min_height = 35.0;
uniform float farm_max_height = 105.0;
uniform vec2 shadow_dir = vec2(0.6, 0.8);           // which way shadows fall on the ground (for hedges)
uniform float tree_range = 2600.0;                  // woods' trees are left out beyond this distance

uniform bool use_textures = false;
uniform sampler2D grass_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sand_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 grass_average = vec3(0.157, 0.117, 0.045);  // each photo's average colour (linear)
uniform vec3 sand_average = vec3(0.4, 0.35, 0.28);
uniform vec3 rock_average = vec3(0.2, 0.2, 0.2);

// Palette (sRGB, turned to linear below).
const vec3 LUSH = vec3(0.34, 0.47, 0.20);       // grazed lowland grass
const vec3 DRY = vec3(0.52, 0.55, 0.31);        // thin, sunny slopes
const vec3 DAMP = vec3(0.24, 0.37, 0.18);       // wet hollows, rushes
const vec3 MOOR = vec3(0.41, 0.42, 0.25);       // rough hill grazing
const vec3 HEATHER = vec3(0.36, 0.29, 0.25);
const vec3 DUNE = vec3(0.62, 0.62, 0.42);       // marram and machair
const vec3 SAND = vec3(0.84, 0.77, 0.60);
const vec3 WET_SAND = vec3(0.56, 0.50, 0.40);
const vec3 SEABED = vec3(0.60, 0.56, 0.44);
const vec3 ROCK = vec3(0.47, 0.45, 0.42);
const vec3 WOOD_FLOOR = vec3(0.20, 0.27, 0.12);       // undergrowth: bracken, bramble, moss
const vec3 NEEDLES = vec3(0.22, 0.24, 0.14);
const vec3 HEDGE = vec3(0.13, 0.22, 0.09);

varying vec3 world_pos;
varying vec3 world_normal;
varying float coast;
varying float far_land;          // 1 on the plain distant land round the detailed ground

vec3 lin(vec3 c) {
	return pow(c, vec3(2.2));
}

float frand(int x, int y, uint salt) {
	// Integer hash, the same as world3d.gd _field_rand.
	uint h = (uint(x) * 73856093u) ^ (uint(y) * 19349663u) ^ (salt * 83492791u);
	h ^= h >> 13u;
	h *= 1274126177u;
	h ^= h >> 16u;
	return float(h & 65535u) / 65535.0;
}

float row_line(int r, float u) {
	// Where the boundary at the bottom of field row r runs (v, in the field frame).
	return float(r) * field_row + field_wobble * sin(u / 310.0 + 6.2832 * frand(r, 0, 1u));
}

float col_line(int c, int r, float v) {
	// Where the boundary at the left of field c in row r runs (u).
	return (float(c) + field_jitter * (frand(c, r, 2u) - 0.5) + frand(r, 0, 3u)) * field_col
		+ field_wobble * sin(v / 270.0 + 6.2832 * frand(c, r, 4u));
}

void field_at(vec2 p, out ivec2 id, out float edge, out vec2 hedge_off, out vec2 mid) {
	// Which field p is in, how far it is from the field's edge, the offset from
	// the nearest hedge (in world x, z) and the middle of the field.
	float ca = cos(field_angle);
	float sa = sin(field_angle);
	float u = p.x * ca + p.y * sa;
	float v = -p.x * sa + p.y * ca;
	int r = int(floor(v / field_row));
	if (v < row_line(r, u)) {
		r -= 1;
	} else if (v >= row_line(r + 1, u)) {
		r += 1;
	}
	float v0 = row_line(r, u);
	float v1 = row_line(r + 1, u);
	int c = int(floor(u / field_col - frand(r, 0, 3u)));
	if (u < col_line(c, r, v)) {
		c -= 1;
	} else if (u >= col_line(c + 1, r, v)) {
		c += 1;
	}
	float u0 = col_line(c, r, v);
	float u1 = col_line(c + 1, r, v);
	int sub = 0;
	float vs = -1e6;
	bool split = frand(c, r, 5u) < field_split;
	if (split) {
		vs = mix(v0, v1, 0.35 + 0.3 * frand(c, r, 6u));
		sub = v > vs ? 1 : 0;
	}
	float lo = sub == 1 ? vs : v0;
	float hi = (split && sub == 0) ? vs : v1;
	edge = min(min(v - lo, hi - v), min(u - u0, u1 - u));
	// The nearest hedge (some boundaries are just a fence).
	vec2 best = vec2(1e5);
	int seg = int(floor(u / 90.0));
	if (frand(seg, r, 7u) < field_hedge && v - v0 < length(best)) best = vec2(0.0, v - v0);
	if (frand(seg, r + 1, 7u) < field_hedge && v1 - v < length(best)) best = vec2(0.0, v - v1);
	if (frand(c, r, 8u) < field_hedge && u - u0 < length(best)) best = vec2(u - u0, 0.0);
	if (frand(c + 1, r, 8u) < field_hedge && u1 - u < length(best)) best = vec2(u - u1, 0.0);
	if (split && frand(c, r, 9u) < field_hedge && abs(v - vs) < length(best)) best = vec2(0.0, v - vs);
	hedge_off = vec2(best.x * ca - best.y * sa, best.x * sa + best.y * ca);
	id = ivec2(c, r * 2 + sub);
	vec2 mq = vec2((u0 + u1) * 0.5, (lo + hi) * 0.5);
	mid = vec2(mq.x * ca - mq.y * sa, mq.x * sa + mq.y * ca);
}

float height_fetch(vec2 p) {
	ivec2 c = clamp(ivec2(round((p - grid_origin) / grid_step)), ivec2(0), grid_size - ivec2(1));
	return texelFetch(height_map, c, 0).r;
}

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	if (UV.x > 0.5) {
		// The far land beyond the detailed ground: its heights are in the mesh.
		world_pos = w;
		world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
		coast = UV.y;
		far_land = 1.0;
	} else {
		far_land = 0.0;
		ivec2 c = ivec2(round((w.xz - grid_origin) / grid_step));
		ivec2 top = grid_size - ivec2(1);
		vec2 s = texelFetch(height_map, clamp(c, ivec2(0), top), 0).rg;
		float hl = texelFetch(height_map, clamp(c - ivec2(1, 0), ivec2(0), top), 0).r;
		float hr = texelFetch(height_map, clamp(c + ivec2(1, 0), ivec2(0), top), 0).r;
		float hu = texelFetch(height_map, clamp(c - ivec2(0, 1), ivec2(0), top), 0).r;
		float hd = texelFetch(height_map, clamp(c + ivec2(0, 1), ivec2(0), top), 0).r;
		VERTEX.y = s.r;
		NORMAL = normalize(vec3(hl - hr, 2.0 * grid_step, hu - hd));
		world_pos = vec3(w.x, s.r, w.z);
		world_normal = NORMAL;
		coast = s.g;
	}
}

void fragment() {
	vec2 p = world_pos.xz;
	float h = world_pos.y;
	float slope = 1.0 - clamp(world_normal.y, 0.0, 1.0);   // 0 = flat
	float dist = length(VERTEX);
	float near = 1.0 - smoothstep(250.0, 1800.0, dist);    // fine detail fades with distance
	vec4 land = texture(land_map, (p - land_origin) / land_size) * (1.0 - far_land);
	vec2 tile_uv = p / map_size;
	bool inside = tile_uv.x >= 0.0 && tile_uv.y >= 0.0 && tile_uv.x <= 1.0 && tile_uv.y <= 1.0;
	float built = inside ? texture(built_map, tile_uv).r : 0.0;
	float wild = 1.0 - built;
	float px = max(length(fwidth(p)), 0.05);              // metres covered by one pixel here

	// Smooth noise at four scales: slow drifts, broad patches, small patches, fine.
	vec4 nA = texture(noise_tex, p / 2600.0);
	vec4 nB = texture(noise_tex, p / 520.0 + nA.xy * 0.4);
	vec4 nC = texture(noise_tex, p.yx / 113.0);
	vec4 nD = texture(noise_tex, p / 29.0);

	// --- Grass that follows the land: dry on slopes and high ground, damp in hollows.
	float dryness = clamp(slope * 5.0 + smoothstep(25.0, 130.0, h) * 0.35 + (nB.r - 0.5) * 0.8, 0.0, 1.0);
	vec3 col = mix(lin(LUSH), lin(DRY), dryness * 0.85);
	col = mix(col, lin(DAMP), clamp(land.r * 1.4 + (nB.g - 0.6) * 0.8, 0.0, 1.0) * (1.0 - dryness) * 0.85);
	float moor = smoothstep(70.0, 125.0, h + (nA.g - 0.5) * 60.0) * wild;
	col = mix(col, mix(lin(MOOR), lin(HEATHER), smoothstep(0.45, 0.8, nC.b * 0.7 + nD.a * 0.3) * 0.55), moor * 0.75);
	col *= 0.88 + 0.24 * nC.r;
	col *= vec3(0.94 + 0.12 * nA.r, 1.0, 0.94 + 0.12 * nA.b);

	// --- Fields with hedges in open country; conifer plantations on the hills.
	float farm = wild * (1.0 - smoothstep(0.12, 0.4, land.g)) * (1.0 - smoothstep(0.08, 0.35, land.b))
		* (1.0 - smoothstep(0.2, 0.32, slope)) * (1.0 - smoothstep(farm_max_height - 15.0, farm_max_height + 15.0, h));
	float plantation = 0.0;
	float hedge_shade = 1.0;
	if (wild > 0.01 && land.b < 0.4) {
		ivec2 id;
		float edge;
		vec2 hedge_off;
		vec2 mid;
		field_at(p, id, edge, hedge_off, mid);
		if (frand(id.x, id.y, 12u) < plant_chance && height_fetch(mid) > plant_min_height) {
			plantation = wild;
		}
		if (farm > 0.01) {
			float kind = frand(id.x, id.y, 10u);
			float tone = frand(id.x, id.y, 11u);
			float ca = cos(field_angle);
			float sa = sin(field_angle);
			float along = p.x * ca + p.y * sa;     // the way the field was worked
			vec3 fc;
			if (kind < 0.62) {
				fc = lin(mix(vec3(0.29, 0.44, 0.17), vec3(0.40, 0.52, 0.22), tone));        // pasture
			} else if (kind < 0.8) {
				fc = lin(mix(vec3(0.44, 0.53, 0.25), vec3(0.51, 0.57, 0.30), tone));        // silage, cut
				fc *= 1.0 + 0.06 * sign(sin(along / 2.6)) * near;
			} else if (kind < 0.88) {
				fc = lin(mix(vec3(0.31, 0.40, 0.19), vec3(0.37, 0.43, 0.23), tone));        // rough grazing
				fc *= 0.82 + 0.36 * smoothstep(0.3, 0.7, nD.g);
			} else if (kind < 0.96) {
				fc = lin(mix(vec3(0.58, 0.57, 0.33), vec3(0.66, 0.61, 0.37), tone));        // barley
				fc *= 1.0 + 0.04 * sin(along / 1.4) * near;
			} else {
				fc = lin(mix(vec3(0.38, 0.31, 0.22), vec3(0.45, 0.37, 0.27), tone));        // ploughed
				fc *= 1.0 + 0.1 * sin(along / 0.9) * near;
			}
			// Keep some of the land's own light and shade (dry slopes, damp hollows).
			fc = mix(fc, col, 0.3);
			fc *= 0.92 + 0.16 * nD.r;
			// A grassy margin round the edge, then the hedge and its shadow.
			col = mix(col, fc, farm * smoothstep(1.5, 4.0, edge));
			float off = length(hedge_off);
			float width = 1.4 + 0.9 * nD.b;
			float soft = max(0.4, px * 0.7);
			float gaps = step(0.22, nD.a + 0.15);
			float hedge = (1.0 - smoothstep(width - soft, width + soft, off)) * gaps * farm
				* mix(1.0, 0.55, smoothstep(0.6, 3.0, px));   // fainter once thinner than a pixel
			// The hedge's shadow: about 5 m long, on the side away from the light.
			float facing = dot(hedge_off / max(off, 0.001), shadow_dir);
			float reach = width + 5.0 * max(facing, 0.0);
			float shadow = step(0.0, facing) * (1.0 - smoothstep(reach - soft, reach + soft, off)) * farm;
			hedge_shade = 1.0 - 0.4 * shadow * gaps * mix(1.0, 0.5, smoothstep(0.6, 3.0, px));
			col = mix(col, lin(HEDGE) * (0.7 + 0.6 * nD.g), hedge);
		}
	}
	col *= hedge_shade;

	// --- Photo detail close up (two scales, so it never visibly repeats).
	if (use_textures) {
		vec2 uv = p / 6.0;
		vec3 detail = mix(texture(grass_tex, uv).rgb, texture(grass_tex, uv.yx * 0.213 + 0.37).rgb, 0.45);
		col *= mix(vec3(1.0), clamp(detail / grass_average, 0.55, 1.6), 0.8 * near);
	} else {
		col *= 1.0 + (nD.g - 0.5) * 0.15 * near;
	}

	// --- Woods: dark leaf litter and undergrowth; needles under plantations.
	// Beyond where the trees themselves are drawn, the canopy is painted on.
	float far_trees = smoothstep(tree_range * 0.8, tree_range * 0.95, dist);
	// (lumpy at three sizes: single crowns, groups of trees, stands)
	float crowns = texture(noise_tex, p / 7.0).g * 0.35 + texture(noise_tex, p.yx / 23.0).a * 0.4 + nC.g * 0.25;
	crowns = smoothstep(0.32, 0.68, crowns);
	vec3 canopy = mix(lin(vec3(0.10, 0.17, 0.07)), lin(vec3(0.27, 0.38, 0.14)), crowns)
		* (0.85 + 0.3 * nB.g);
	float woods = smoothstep(0.42, 0.58, land.g + (nC.a - 0.5) * 0.25 + (nD.g - 0.5) * 0.12) * wild;
	col = mix(col, mix(lin(WOOD_FLOOR) * (0.75 + 0.5 * nD.r), canopy, far_trees), woods * 0.92);
	col = mix(col, mix(lin(NEEDLES) * (0.8 + 0.4 * nD.r), canopy * vec3(0.72, 0.85, 0.85), far_trees), plantation * 0.92);

	// --- Rock where the ground is steep.
	vec3 rock = lin(ROCK) * (0.8 + 0.4 * nD.g);
	if (use_textures) {
		rock = mix(rock, texture(rock_tex, p / 9.0).rgb / rock_average * lin(ROCK), near);
	}
	col = mix(col, rock, smoothstep(0.3, 0.45, slope + (nC.a - 0.5) * 0.12));

	// --- The shore: dune grass, then dry sand, wet sand at the water, seabed below.
	float dune = smoothstep(0.3, 0.75, land.b + (nB.b - 0.5) * 0.3) * wild * (1.0 - plantation);
	vec3 dune_col = lin(DUNE) * (0.85 + 0.3 * nD.r) * (0.85 + 0.3 * smoothstep(0.4, 0.6, nC.g));
	col = mix(col, dune_col, dune * 0.85);
	float m = coast + (nC.g - 0.5) * 0.06 + (nD.b - 0.5) * 0.03;
	vec3 sand = lin(SAND) * (0.92 + 0.16 * nC.r);
	if (use_textures) {
		sand = mix(sand, texture(sand_tex, p / 5.0).rgb / sand_average * lin(SAND), 0.6 * near);
	}
	float sandy = 1.0 - smoothstep(shore_level + 0.17, shore_level + 0.27, m + built * 0.14);
	col = mix(col, sand, sandy);
	float wet = 1.0 - smoothstep(shore_level + 0.01, shore_level + 0.07, m);
	col = mix(col, lin(WET_SAND) * (0.9 + 0.2 * nD.r), wet);
	float under = 1.0 - smoothstep(-2.5, -0.05, h);
	col = mix(col, lin(SEABED) * (0.75 + 0.3 * nC.r) * mix(1.0, 0.55, smoothstep(0.0, 8.0, -h)), under);

	// --- Zone colours, warnings and map overlays, one map tile at a time.
	vec3 glow = vec3(0.0);
	if (inside && overlay_on) {
		// Map overlay: plain grey ground with each tile's colour on top.
		vec4 ov = texture(overlay_map, tile_uv);
		col = vec3(dot(col, vec3(0.33))) * 0.7;
		col = mix(col, ov.rgb, ov.a);
		glow = ov.rgb * ov.a * 0.15;                    // still readable at night
	} else if (inside) {
		vec4 zone = texture(zone_map, tile_uv);
		col = mix(col, zone.rgb, zone.a);
		vec4 warn = texture(warn_map, tile_uv);
		float stripes = step(0.5, fract((p.x + p.y) / 8.0));
		col = mix(col, vec3(0.05), warn.r * stripes * 0.55);           // no road: dark stripes
		// (No power is shown by a floating icon instead of a ground colour.)
	}
	// Beyond the playable map the land carries on, just a little quieter, with a
	// faint line where building stops.
	vec2 outside = max(max(-p, p - map_size), vec2(0.0));
	float beyond = smoothstep(0.0, 400.0, length(outside));
	float grey = dot(col, vec3(0.3, 0.55, 0.15));
	col = mix(col, vec3(grey), (overlay_on ? 0.6 : 0.2) * beyond) * (1.0 - (overlay_on ? 0.35 : 0.08) * beyond);
	vec2 to_edge = min(abs(p), abs(p - map_size));
	float on_line = (1.0 - smoothstep(0.5, 0.5 + max(px, 0.8), min(to_edge.x, to_edge.y)))
		* step(-2.5, min(p.x, p.y)) * step(max(p.x - map_size.x, p.y - map_size.y), 2.5);
	on_line *= 1.0 - smoothstep(1.5, 6.0, px);           // (only close enough to see)
	col *= 1.0 + 0.3 * on_line * (1.0 - under);

	ALBEDO = col;
	EMISSION = glow;
	ROUGHNESS = mix(mix(0.95, 0.8, sandy), 0.45, wet);
	SPECULAR = mix(0.25, 0.5, wet);
	// Slopes turned a little further towards or away from the light than they
	// really are, so gentle hills read (looks only; the ground keeps its shape).
	vec3 n = normalize(vec3(world_normal.x * normal_boost, world_normal.y, world_normal.z * normal_boost));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
}
