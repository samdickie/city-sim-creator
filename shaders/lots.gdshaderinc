// The ground of the town's plots, painted one tile at a time from lot_map (see
// world3d.gd _plan_lots, which explains the bits): lawns and gardens, back
// courts, paving, yards, rough ground waiting to be built on, building sites,
// park layouts, school playgrounds, golf. Things that stand up (hedges, sheds,
// cars, benches) are boxes planned in world3d.gd; this is only the ground, so
// it costs nothing per plot. Plots reach into the verges of straight roads
// beside them, so a road tile's verges are painted as part of the plot next door.
// Included by terrain.gdshader (needs lin(), frand() and noise_tex).

uniform sampler2D lot_map : filter_nearest, repeat_disable;
uniform float tile_metres = 50.0;
uniform float street_reach = 18.0;          // how far a plot's front reaches into a straight road's tile
uniform vec3 zone_homes : source_color = vec3(0.86, 0.36, 0.30);
uniform vec3 zone_shops : source_color = vec3(0.26, 0.58, 0.92);
uniform vec3 zone_industry : source_color = vec3(0.96, 0.70, 0.15);

const int K_ROAD = 1;
const int K_VILLAS = 2;
const int K_TERRACES = 3;
const int K_TENEMENTS = 4;
const int K_COURT = 5;
const int K_SHOPS = 6;
const int K_PLAZA = 7;
const int K_INDUSTRY = 8;
const int K_EMPTY = 9;
const int K_SITE = 10;
const int K_PARK = 11;
const int K_ALLOTMENTS = 12;
const int K_CAR_PARK = 13;
const int K_CIVIC = 14;
const int K_SCHOOL = 15;
const int K_GOLF = 16;
const int K_YARD = 17;
const int K_HOSPITAL = 18;
const int K_MEADOW = 19;
const int K_WOODS = 20;          // planted woodland (its own ground is the terrain's woods floor)
const vec3 WOODS_FLOOR = vec3(0.20, 0.27, 0.12);   // = terrain.gdshader WOOD_FLOOR

const int P_LAWN = 0;
const int P_POND = 1;
const int P_FORMAL = 2;
const int P_PLAY = 3;
const int P_PITCH = 4;
const int P_BANDSTAND = 5;

struct Ctx {
	vec2 p;          // world x, z
	float px;        // metres per pixel here
	float near;      // 1 close up, 0 far away
	vec4 nC;         // smooth noises (113 m and 29 m)
	vec4 nD;
	vec3 detail;     // grass photo detail (multiply)
};

float h21(vec2 q) {
	return fract(sin(dot(q, vec2(127.1, 311.7))) * 43758.5453);
}

ivec4 lot_at(ivec2 t) {
	ivec2 size = textureSize(lot_map, 0);
	if (t.x < 0 || t.y < 0 || t.x >= size.x || t.y >= size.y) {
		return ivec4(0);
	}
	return ivec4(round(texelFetch(lot_map, t, 0) * 255.0));
}

vec2 front_vec(int d) {
	// The street side, as world3d.gd _frontage: 0 = +z, 1 = -z, 2 = +x, 3 = -x.
	return d == 0 ? vec2(0.0, 1.0) : (d == 1 ? vec2(0.0, -1.0) : (d == 2 ? vec2(1.0, 0.0) : vec2(-1.0, 0.0)));
}

int side_index(vec2 f) {
	// SIDES order (+x, -x, +z, -z), as the neighbour and reach bits.
	return f.x > 0.5 ? 0 : (f.x < -0.5 ? 1 : (f.y > 0.5 ? 2 : 3));
}

float box(vec2 q, vec2 lo, vec2 hi, float soft) {
	// 1 inside the rectangle lo..hi, soft-edged.
	vec2 d = max(lo - q, q - hi);
	return 1.0 - smoothstep(-soft, soft, max(d.x, d.y));
}

float band(float d, float half_width, float soft) {
	return 1.0 - smoothstep(half_width - soft, half_width + soft, abs(d));
}

float disc(vec2 q, float r, float soft) {
	return 1.0 - smoothstep(r - soft, r + soft, length(q));
}

// --- Surfaces

vec3 lawn(Ctx c, float tone, float stripe) {
	// Mown grass in the same family as the fields round about, a little deeper,
	// each garden its own shade, with mowing stripes close up. (tone above 1:
	// a well-kept lawn, with no worn patches.)
	vec3 g = mix(lin(vec3(0.22, 0.31, 0.14)), lin(vec3(0.31, 0.38, 0.19)), min(tone, 1.0));
	g *= 0.88 + 0.24 * c.nD.r;
	g = mix(g, lin(vec3(0.47, 0.47, 0.29)), smoothstep(0.66, 0.86, c.nC.b) * 0.35 * step(tone, 1.0));   // dry, worn patches
	float stripes = sign(sin(stripe * 1.9635)) * c.near * (1.0 - smoothstep(0.25, 0.7, c.px));
	g *= 1.0 + 0.07 * stripes;
	return g * mix(vec3(1.0), c.detail, 0.5);       // (only half the photo's dry bits: it's looked after)
}

vec3 rough_grass(Ctx c) {
	// Long, unmown, tussocky grass with dry bents and the odd weed.
	float tuft = texture(noise_tex, c.p / 2.3).b * 0.6 + texture(noise_tex, c.p.yx / 0.9).r * 0.4;
	vec3 g = mix(lin(vec3(0.27, 0.36, 0.16)), lin(vec3(0.45, 0.46, 0.26)),
		smoothstep(0.35, 0.85, c.nC.r * 0.5 + c.nD.g * 0.5));
	g *= 0.72 + 0.56 * mix(0.5, tuft, c.near);
	return g * c.detail;
}

vec3 shrubs(Ctx c) {
	// A planted border: lumpy dark shrubs over bark mulch.
	float lump = texture(noise_tex, c.p / 2.1).g * 0.7 + texture(noise_tex, c.p.yx / 0.8).a * 0.3;
	vec3 s = mix(lin(vec3(0.24, 0.18, 0.12)), lin(vec3(0.14, 0.25, 0.09)), smoothstep(0.32, 0.55, lump));
	return s * (0.75 + 0.5 * lump);
}

vec3 flower_bed(Ctx c) {
	// Shrubs and perennials, with drifts of one colour of flowers here and there.
	vec3 s = shrubs(c);
	float h = h21(floor(c.p / 2.6));
	vec3 flower = h < 0.3 ? lin(vec3(0.80, 0.34, 0.50)) : (h < 0.5 ? lin(vec3(0.92, 0.78, 0.30))
		: (h < 0.65 ? lin(vec3(0.90, 0.89, 0.90)) : lin(vec3(0.56, 0.36, 0.70))));
	float drift = smoothstep(0.5, 0.62, texture(noise_tex, c.p / 1.9).r) * step(h21(floor(c.p / 2.6) + 5.1), 0.6);
	return mix(s, flower * (0.8 + 0.3 * texture(noise_tex, c.p / 0.5).g), drift * 0.85);
}

vec3 soil(Ctx c) {
	return lin(vec3(0.33, 0.24, 0.16)) * (0.78 + 0.44 * c.nD.b);
}

vec3 veg_rows(Ctx c, float across) {
	// Vegetable rows: crops and bare soil.
	float row = step(0.45, fract(across / 0.8));
	vec3 crop = lin(vec3(0.26, 0.42, 0.15)) * (0.8 + 0.4 * c.nD.g);
	return mix(soil(c), crop, mix(0.5, row, c.near));
}

vec3 gravel(Ctx c, vec3 base) {
	float grain = mix(0.5, h21(floor(c.p * 7.0)), c.near * (1.0 - smoothstep(0.1, 0.3, c.px)));
	return base * (0.84 + 0.32 * grain) * (0.9 + 0.2 * c.nD.r);
}

vec3 paving(Ctx c, vec2 q, vec3 base, vec2 size, bool bond) {
	// Slabs or blocks laid in rows (bond: each row offset by half), with joints
	// that fade away once a slab is only a few pixels.
	vec2 g = q / size;
	if (bond) {
		g.x += floor(g.y) * 0.5;
	}
	vec2 edge = (0.5 - abs(fract(g) - 0.5)) * size;          // metres to the nearest joint
	float joint = 1.0 - smoothstep(0.015, 0.015 + max(c.px * 0.7, 0.03), min(edge.x, edge.y));
	joint *= 1.0 - smoothstep(0.08, 0.25, c.px / min(size.x, size.y));
	float tint = 0.93 + 0.1 * h21(floor(g));
	return base * tint * (1.0 - 0.3 * joint) * (0.93 + 0.14 * c.nD.r);
}

vec3 tarmac(Ctx c) {
	return lin(vec3(0.24, 0.24, 0.25)) * (0.85 + 0.3 * c.nD.r) * (0.95 + 0.1 * c.nC.g);
}

vec3 concrete(Ctx c, vec2 q, float bay) {
	// Concrete in poured bays, with oil stains and tyre marks.
	vec3 base = lin(vec3(0.60, 0.59, 0.56)) * (0.9 + 0.2 * c.nD.b);
	vec2 edge = (0.5 - abs(fract(q / bay) - 0.5)) * bay;
	float joint = (1.0 - smoothstep(0.03, 0.03 + max(c.px * 0.7, 0.04), min(edge.x, edge.y)))
		* (1.0 - smoothstep(0.4, 1.2, c.px));
	base *= 1.0 - 0.3 * joint;
	float stain = smoothstep(0.62, 0.8, texture(noise_tex, c.p / 7.0).r * 0.7 + c.nD.a * 0.3);
	return base * (1.0 - 0.45 * stain);
}

vec3 earth(Ctx c, vec2 q) {
	// Bare, churned earth with tyre ruts and the odd puddle.
	vec3 e = mix(lin(vec3(0.52, 0.42, 0.28)), lin(vec3(0.40, 0.31, 0.21)), smoothstep(0.3, 0.7, c.nD.g));
	float ruts = band(fract(q.x / 3.1 + 0.15 * sin(q.y / 6.0)) - 0.5, 0.08, 0.04) * c.near;
	e *= 1.0 - 0.25 * ruts;
	return e * (0.85 + 0.3 * texture(noise_tex, c.p / 1.3).r);
}

vec3 zone_colour(int zone) {
	return zone == 1 ? zone_homes : (zone == 2 ? zone_shops : zone_industry);
}

// --- Plot layouts. along: metres along the street from the plot's middle;
// back: metres back from its front (the pavement edge); depth: front to back.

vec3 villas(Ctx c, float along, float back, float depth, int stage, ivec2 o, inout float shine) {
	// Detached houses on 11.5 m lots (world3d.gd _plan_homes): the house on the
	// left of each lot, its drive on the right; front garden with a border and a
	// path to the door; patio, borders, vegetable patch and stepping stones out
	// the back; long gardens running to meadow at the far end.
	float lot_f = clamp(floor((along + 23.0) / 11.5), 0.0, 3.0);
	float u = along - (-17.25 + lot_f * 11.5);
	int lot = int(lot_f);
	float s1 = frand(o.x * 4 + lot, o.y, 201u);
	float s2 = frand(o.x * 4 + lot, o.y, 202u);
	float s3 = frand(o.x * 4 + lot, o.y, 203u);
	float soft = max(c.px * 0.6, 0.04);
	vec3 col = lawn(c, s1, u);
	float lane_at = depth - 25.0;
	float g0;
	float g1;
	bool front_garden;
	if (back < 6.0) {
		g0 = 0.0; g1 = 6.0; front_garden = true;
	} else if (stage < 2) {
		g0 = 15.3; g1 = depth - 0.6; front_garden = false;
	} else if (back < lane_at) {
		g0 = 15.3; g1 = lane_at - 0.3; front_garden = false;
	} else if (back < depth - 17.0) {
		g0 = lane_at + 3.0; g1 = depth - 17.0; front_garden = true;
	} else {
		g0 = depth - 8.3; g1 = depth - 0.6; front_garden = false;
	}
	float gv = back - g0;
	float glen = g1 - g0;
	vec2 q = vec2(u, gv);
	vec3 buff = lin(vec3(0.74, 0.68, 0.58));
	if (front_garden) {
		if (s2 < 0.22) {
			col = gravel(c, lin(vec3(0.66, 0.62, 0.55)));          // gravelled for a second car
		}
		col = mix(col, flower_bed(c), box(q, vec2(-5.4, 1.1), vec2(1.9, 2.0), soft) * step(0.3, s3));
		col = mix(col, paving(c, vec2(u, back), buff, vec2(0.6, 0.6), false),
			box(q, vec2(-2.6, -2.0), vec2(-1.4, glen + 1.0), soft));
	} else {
		float patio_w = 3.5 + 3.5 * s2;
		col = mix(col, paving(c, vec2(u, back), s3 < 0.5 ? buff : lin(vec3(0.58, 0.56, 0.53)), vec2(0.6, 0.6), s3 < 0.5),
			box(q, vec2(-5.3, -0.6), vec2(-5.3 + patio_w, 3.0), soft));
		float side = s3 < 0.5 ? -1.0 : 1.0;
		col = mix(col, flower_bed(c), box(vec2(u * side, gv), vec2(4.2, 3.6), vec2(5.6, glen - 1.0), soft) * step(0.18, s1));
		if (glen > 14.0 && s2 > 0.45) {
			col = mix(col, veg_rows(c, back), box(q, vec2(-4.4, glen - 11.0), vec2(1.6, glen - 3.5), soft));
		}
		if (s3 > 0.5 && glen > 8.0) {
			// Stepping stones down the lawn.
			float stone = box(vec2(u - 0.3 * sin(gv / 3.0), fract(gv / 0.9) * 0.9), vec2(-0.35, 0.15), vec2(0.35, 0.65), soft);
			col = mix(col, buff * 0.9, stone * step(3.2, gv) * step(gv, min(glen - 2.0, 26.0)));
		}
		if (glen > 30.0) {
			// The far end: long grass and wild flowers, a mown path through it.
			float wild = smoothstep(26.0, 29.0, gv) * (1.0 - band(u - 1.2 * sin(gv / 4.0), 0.6, soft));
			col = mix(col, rough_grass(c), wild);
		}
	}
	return col;
}

vec3 terraces(Ctx c, float along, float back, float depth, ivec2 o) {
	// Rows of terraced houses (world3d.gd _plan_terraces): narrow strip gardens,
	// one per house, a patio at the house end; the back lane between the rows.
	float strip_w = 46.0 / 9.0;
	float sf = clamp(floor((along + 23.0) / strip_w), 0.0, 8.0);
	float u = along - (-23.0 + (sf + 0.5) * strip_w);
	int strip = int(sf);
	float s1 = frand(o.x * 9 + strip, o.y, 211u);
	float s2 = frand(o.x * 9 + strip, o.y, 212u);
	float soft = max(c.px * 0.6, 0.04);
	float back_row = depth - 13.0;
	float lane = (4.0 + 8.5 + back_row) * 0.5 - 1.5;
	vec3 col = lawn(c, s1, u);
	vec3 buff = lin(vec3(0.72, 0.67, 0.58));
	if (back < 4.0) {
		// Tiny front gardens: grass, gravel or slabs, a path to each door.
		if (s2 < 0.35) {
			col = gravel(c, lin(vec3(0.64, 0.60, 0.54)));
		} else if (s2 < 0.55) {
			col = paving(c, vec2(along, back), buff, vec2(0.6, 0.6), false);
		}
		col = mix(col, paving(c, vec2(along, back), buff, vec2(0.6, 0.6), false), band(u + 1.2, 0.55, soft));
		return col;
	}
	float g0 = 12.5;
	float g1 = lane;
	if (back > lane + 3.0 && back < back_row) {
		g0 = lane + 3.0; g1 = back_row - 0.4;
	} else if (back >= back_row) {
		return paving(c, vec2(along, back), lin(vec3(0.60, 0.58, 0.55)), vec2(0.9, 0.6), false);   // back yards
	}
	bool house_end_low = back < lane;
	float gv = house_end_low ? back - g0 : g1 - back;      // metres from the house end
	float glen = g1 - g0;
	col = mix(col, paving(c, vec2(along, back), buff, vec2(0.6, 0.6), true), step(gv, 2.6));
	col = mix(col, flower_bed(c), box(vec2(abs(u), gv), vec2(1.7, 3.0), vec2(2.6, glen - 1.0), soft) * step(0.4, s1));
	if (s2 > 0.62 && glen > 10.0) {
		col = mix(col, veg_rows(c, back), box(vec2(u, gv), vec2(-1.6, glen - 6.0), vec2(1.3, glen - 1.0), soft));
	}
	return col;
}

vec3 tenements(Ctx c, float along, float back, float depth, ivec2 o) {
	// The back court behind the tenements (world3d.gd _plan_homes, stage 3):
	// drying greens for each close, paths between them, paving by the back doors.
	float soft = max(c.px * 0.6, 0.04);
	float back_row = depth - 16.0;
	vec3 slabs = lin(vec3(0.62, 0.60, 0.56));
	if (back < 16.6 || back > back_row - 0.6) {
		return paving(c, vec2(along, back), slabs, vec2(0.9, 0.6), false);
	}
	float mid = (16.5 + back_row) * 0.5;
	float tone = frand(o.x * 2 + (along < 0.0 ? 0 : 1), o.y * 2 + (back < mid ? 0 : 1), 221u);
	vec3 col = lawn(c, tone * 0.7, along);
	// Paving by the back doors, a path along the middle and one down each close.
	float path = max(band(back - mid, 1.0, soft), band(along, 1.0, soft));
	path = max(path, max(step(back, 18.2), step(back_row - 2.3, back)));
	col = mix(col, paving(c, vec2(along, back), slabs, vec2(0.6, 0.6), false), path);
	// Worn grass round the clothes poles.
	float worn = smoothstep(0.55, 0.9, c.nD.g) * 0.4;
	col = mix(col, lin(vec3(0.45, 0.42, 0.30)), worn * (1.0 - path));
	return col;
}

vec3 court(Ctx c, float along, float back, float depth, ivec2 o) {
	// A landscaped court between tall blocks (world3d.gd _plan_tall_homes):
	// paving round the edge, lawn, a winding path, planting beds.
	float soft = max(c.px * 0.6, 0.04);
	float c0 = 17.5;
	float c1 = depth - 18.0;
	vec3 slabs = lin(vec3(0.70, 0.67, 0.61));
	vec3 col = paving(c, vec2(along, back), slabs, vec2(0.8, 0.8), false);
	if (back > c0 + 2.5 && back < c1 - 2.5 && abs(along) < 21.5) {
		col = lawn(c, 0.6, along);
		float path = band(along - 6.0 * sin((back - c0) / 7.0), 1.0, soft);
		col = mix(col, slabs * 0.95, path);
		float beds = box(vec2(abs(along), back), vec2(14.0, c0 + 4.0), vec2(20.0, c0 + 8.0), soft);
		col = mix(col, flower_bed(c), beds);
	}
	return col;
}

vec3 shops(Ctx c, float along, float back, float depth, int stage) {
	// Wide paved pavement in front; behind the parade a concrete service yard; a
	// planted margin round the car park (the car park itself is a slab).
	float soft = max(c.px * 0.6, 0.04);
	float parade_back = stage >= 3 ? 21.0 : 16.0;
	vec3 slabs = lin(vec3(0.69, 0.66, 0.60));
	if (back < parade_back) {
		return paving(c, vec2(along, back), slabs, vec2(0.6, 0.6), false);
	}
	vec3 col = concrete(c, vec2(along, back), 4.0);       // the service yard
	if (back > parade_back + 7.0) {
		col = tarmac(c);                                   // (under the car park's slab)
		float margin = max(step(22.2, abs(along)), step(depth - 1.5, back));
		col = mix(col, shrubs(c), margin);
	}
	return col;
}

vec3 plaza(Ctx c, float along, float back, bool cbd) {
	// Offices and towers: paved all over, granite slabs with lighter bands.
	vec3 base = cbd ? lin(vec3(0.66, 0.64, 0.61)) : lin(vec3(0.70, 0.66, 0.58));
	vec3 col = paving(c, vec2(along, back), base, vec2(1.2, 0.6), true);
	float soft = max(c.px * 0.6, 0.04);
	float bands = band(fract(back / 9.0) - 0.5, 0.06, soft / 9.0) + band(along, 0.4, soft);
	return mix(col, base * 1.18, clamp(bands, 0.0, 1.0) * 0.8);
}

vec3 industry(Ctx c, float along, float back, float depth) {
	// A concrete yard with stains and tyre marks, gravel at the back, scrub and
	// weeds along the fences.
	vec3 col = concrete(c, vec2(along, back), 6.0);
	float tracks = band(fract(along / 3.4) - 0.5, 0.1, 0.05) * step(back, 8.0) * c.near;
	col *= 1.0 - 0.18 * tracks;
	float rough_back = smoothstep(depth - 11.0, depth - 9.0, back + (c.nD.r - 0.5) * 4.0);
	col = mix(col, gravel(c, lin(vec3(0.52, 0.49, 0.44))), rough_back);
	float scrub = smoothstep(21.5, 23.5, abs(along) + (c.nD.g - 0.5) * 3.0)
		+ smoothstep(depth - 3.0, depth - 1.0, back + (c.nD.b - 0.5) * 3.0);
	col = mix(col, rough_grass(c) * 0.85, clamp(scrub, 0.0, 1.0));
	return col;
}

vec3 empty_plot(Ctx c, float along, float back, float depth, int zone, int density) {
	// Zoned and waiting: rough grass, a mown strip by the street, and a line in
	// the zone's colour round the plot (one line for low density, two for
	// medium, three for high), with a faint wash of it that grows with distance
	// so zones still read from far away.
	float soft = max(c.px * 0.6, 0.04);
	vec3 col = rough_grass(c);
	col = mix(col, lawn(c, 0.7, along), step(back, 2.5));
	vec3 tint = zone_colour(zone);
	float wash = mix(0.06, 0.5, smoothstep(0.6, 4.0, c.px));
	col = mix(col, tint, wash);
	float edge = min(min(back - 0.6, depth - 1.0 - back), 23.6 - abs(along));
	float w = max(0.35, c.px * 1.2);
	float lines = band(edge, w, soft);
	if (density >= 1) lines = max(lines, band(edge - 1.4 - w, w, soft));
	if (density >= 2) lines = max(lines, band(edge - 2.8 - w * 2.0, w, soft));
	return mix(col, tint * 1.05, lines * step(-0.5, edge) * 0.92);
}

vec3 building_site(Ctx c, float along, float back, float depth, int zone) {
	// Being built: churned earth, a hard-core track in from the street, puddles,
	// and a faint wash of the zone colour.
	float soft = max(c.px * 0.6, 0.04);
	vec3 col = earth(c, vec2(along, back));
	float track = band(along - 14.0 - 2.0 * sin(back / 9.0), 2.2, soft);
	col = mix(col, gravel(c, lin(vec3(0.56, 0.53, 0.49))), track);
	float puddle = smoothstep(0.79, 0.81, texture(noise_tex, c.p / 21.0).g) * (1.0 - track);
	col = mix(col, lin(vec3(0.30, 0.31, 0.32)), puddle * 0.8);
	return mix(col, zone_colour(zone), mix(0.03, 0.35, smoothstep(0.8, 4.0, c.px)));
}

vec3 park(Ctx c, ivec2 o, int plan, int same, int reach_mask, inout float shine) {
	// A park tile, laid out in the tile's own x, z (world3d.gd _park_layout).
	// Sides that join more park carry on (paths cross over); other sides get a
	// shrub border and a path round the inside of the railings.
	vec2 r = c.p - (vec2(o) + 0.5) * tile_metres;
	float half_t = tile_metres * 0.5;
	float soft = max(c.px * 0.6, 0.05);
	vec4 ext = vec4(half_t);
	for (int s = 0; s < 4; s++) {
		if (((reach_mask >> s) & 1) == 1) {
			ext[s] += street_reach;
		}
	}
	vec3 col = lawn(c, 1.0 + 0.6 * c.nC.g, r.x * 0.7 + r.y * 0.7) * (0.9 + 0.2 * c.nC.g);
	float edge = 1e4;
	if ((same & 1) == 0) edge = min(edge, ext.x - r.x);
	if ((same & 2) == 0) edge = min(edge, ext.y + r.x);
	if ((same & 4) == 0) edge = min(edge, ext.z - r.y);
	if ((same & 8) == 0) edge = min(edge, ext.w + r.y);
	col = mix(col, shrubs(c), band(edge - 1.3, 0.9, soft));      // a shrub border inside the railings
	vec3 path_col = lin(vec3(0.72, 0.66, 0.54));
	float path = band(edge - 4.2, 1.1, soft);
	// Paths through to the park next door, meandering the same way on both sides.
	// (In a park more than one tile deep, only every other row has one, and
	// every other column, so a big park has a few long paths, not a grid.)
	vec2 w = c.p;
	if ((same & 3) != 0 && ((same & 12) == 0 || (o.y & 1) == 0)) {
		path = max(path, band(r.y - 7.0 * sin(w.x / 21.0 + float(o.y) * 1.7), 1.2, soft));
	}
	if ((same & 12) != 0 && ((same & 3) == 0 || (o.x & 1) == 0)) {
		path = max(path, band(r.x - 7.0 * sin(w.y / 23.0 + float(o.x) * 2.3), 1.2, soft));
	}
	vec2 off = (vec2(frand(o.x, o.y, 111u), frand(o.x, o.y, 112u)) - 0.5) * 8.0;
	if (plan == P_POND) {
		vec2 q = r - off;
		float wobble = 1.6 * sin(atan(q.y, q.x) * 3.0 + float(o.x)) + 1.0 * sin(atan(q.y, q.x) * 5.0);
		float d = length(q) - (10.5 + wobble);
		col = mix(col, lin(vec3(0.20, 0.27, 0.12)) * (0.8 + 0.4 * c.nD.g), band(d - 0.2, 1.3, soft));   // reeds
		float water = 1.0 - smoothstep(-soft, soft, d);
		col = mix(col, lin(vec3(0.13, 0.24, 0.26)) * (0.9 + 0.2 * c.nC.r), water);
		shine = max(shine, water);
		path = max(path, band(d - 4.5, 1.1, soft));
	} else if (plan == P_FORMAL) {
		float cross_paths = max(band(r.x, 1.2, soft), band(r.y, 1.2, soft));
		float ring = disc(r, 6.0, soft);
		vec2 a = abs(r);
		float beds = box(a, vec2(4.5, 4.5), vec2(15.0, 15.0), soft) * (1.0 - disc(r, 7.5, soft));
		float hedge = beds * (1.0 - box(a, vec2(5.3, 5.3), vec2(14.2, 14.2), soft));
		col = mix(col, flower_bed(c), beds);
		col = mix(col, lin(vec3(0.12, 0.22, 0.09)), hedge);                       // low box hedging
		path = max(path, max(cross_paths, ring));
		col = mix(col, path_col, path);
		float basin = disc(r, 3.0, soft);
		col = mix(col, lin(vec3(0.80, 0.77, 0.70)), basin);
		float pool = disc(r, 2.4, soft);
		col = mix(col, lin(vec3(0.20, 0.36, 0.42)), pool);
		shine = max(shine, pool);
		return col;
	} else if (plan == P_PLAY) {
		vec2 q = r - vec2(7.0, -7.0) - off * 0.4;
		float play = box(q, vec2(-8.0, -6.0), vec2(8.0, 6.0), soft);
		vec3 safety = mix(lin(vec3(0.62, 0.28, 0.20)), lin(vec3(0.24, 0.48, 0.30)), step(0.0, q.x - 1.0));
		col = mix(col, safety * (0.9 + 0.2 * c.nD.r), play);
		float sandpit = box(q, vec2(-6.5, 1.5), vec2(-2.5, 4.5), soft);
		col = mix(col, lin(vec3(0.82, 0.74, 0.56)), sandpit);
		path = max(path * (1.0 - play), band(r.x + r.y * 0.9, 1.1, soft) * (1.0 - play));
	} else if (plan == P_PITCH) {
		// A football pitch with stripes along it and white lines.
		col = lawn(c, 0.75, r.x * 0.62) * 1.04;
		vec2 h = vec2(min(ext.x, ext.y) - 6.0, min(ext.z, ext.w) - 6.0);
		h = min(h, vec2(26.0, 17.0));
		vec2 a = abs(r);
		float lw = max(0.09, c.px * 0.5);
		float lines = band(max(a.x - h.x, a.y - h.y), lw, soft) * step(max(a.x - h.x, a.y - h.y), 0.5);
		lines = max(lines, band(r.x, lw, soft) * step(a.y, h.y));
		lines = max(lines, band(length(r) - 4.5, lw, soft));
		vec2 box_d = vec2(a.x - (h.x - 6.0), a.y - 9.0);
		lines = max(lines, band(max(box_d.x, box_d.y), lw, soft) * step(h.x - 6.0, a.x) * step(a.y, 9.0 + lw) * step(a.x, h.x));
		col = mix(col, lin(vec3(0.92, 0.92, 0.88)), lines * 0.9);
		path *= step(h.x + 3.0, a.x) + step(h.y + 3.0, a.y);
	} else if (plan == P_BANDSTAND) {
		float plaza = disc(r, 9.5, soft);
		vec2 a = abs(r);
		float spokes = band(r.x - r.y, 1.2, soft) * step(9.0, length(r));
		path = max(max(path, spokes), plaza);
		col = mix(col, flower_bed(c), band(length(r) - 11.5, 1.0, soft));
	} else {
		// Open lawn: a wild flower meadow patch and a path winding across.
		float meadow = smoothstep(0.58, 0.66, texture(noise_tex, c.p / 31.0).b);
		col = mix(col, mix(rough_grass(c), flower_bed(c), 0.25), meadow);
		if (same == 0) {
			path = max(path, band(r.y - r.x * 0.5 - 6.0 * sin(r.x / 9.0 + float(o.y)), 1.1, soft));
		}
	}
	return mix(col, path_col * (0.92 + 0.16 * c.nD.r), path);
}

vec3 allotments(Ctx c, float along, float back, float depth, ivec2 o) {
	// Plots of vegetables, soil and fruit cages with grass paths between.
	float soft = max(c.px * 0.6, 0.04);
	vec2 cell = vec2(11.0, (depth - 6.0) / 6.0);
	vec2 q = vec2(along + 22.0, back - 3.0);
	vec2 id = floor(q / cell);
	vec2 in_cell = q - id * cell;
	vec3 col = lawn(c, 0.4, along);
	float plot = box(in_cell, vec2(0.7, 0.6), cell - vec2(0.7, 0.6), soft) * step(0.0, q.y) * step(q.y, depth - 6.0)
		* step(0.0, q.x) * step(q.x, 44.0);
	float k = h21(id + vec2(float(o.x), float(o.y)) * 7.0);
	vec3 bed = k < 0.55 ? veg_rows(c, in_cell.x * (k < 0.3 ? 1.0 : 0.0) + back * (k < 0.3 ? 0.0 : 1.0))
		: (k < 0.8 ? soil(c) : rough_grass(c));
	return mix(col, bed, plot);
}

vec3 school(Ctx c, float along, float back, float depth) {
	// Tarmac playground at the front with painted games; a playing field behind
	// with a pitch marked out.
	float soft = max(c.px * 0.6, 0.04);
	if (back < 19.0) {
		vec3 col = tarmac(c) * 1.1;
		vec2 q = vec2(along - 20.0, back - 10.0);
		float lw = max(0.06, c.px * 0.5);
		float court_lines = band(max(abs(q.x) - 3.5, abs(q.y) - 6.5), lw, soft);
		vec2 hop = vec2(along - 8.0, back - 9.0);
		float hopscotch = box(hop, vec2(-0.6, -3.0), vec2(0.6, 3.0), soft) * step(0.3, fract(hop.y / 1.2 + 0.5));
		col = mix(col, lin(vec3(0.95, 0.85, 0.30)), court_lines);
		col = mix(col, lin(vec3(0.85, 0.85, 0.85)), hopscotch * 0.5);
		return col;
	}
	vec3 col = lawn(c, 0.7, along * 0.8);
	float a0 = 21.0;
	float b0 = depth - 4.0;
	vec2 q = vec2(along, back);
	float lw = max(0.08, c.px * 0.5);
	float outline = band(max(abs(along) - 19.0, max(a0 - back, back - b0)), lw, soft);
	float halfway = band(along, lw, soft) * step(a0, back) * step(back, b0);
	float circle = band(length(q - vec2(0.0, (a0 + b0) * 0.5)) - 4.0, lw, soft);
	return mix(col, lin(vec3(0.92, 0.92, 0.88)), max(outline, max(halfway, circle)) * 0.9);
}

vec3 golf(Ctx c, ivec2 o, int same, float along, float back, float depth) {
	// Fairway striped by the mower, rough along the edges of the course; a green
	// (its flag is a prop), sand bunkers round it and a tee, placed as in
	// world3d.gd _plan_building (Tile.GOLF).
	vec2 r = c.p - (vec2(o) + 0.5) * tile_metres;
	vec3 fairway = lawn(c, 0.85, (r.x + r.y) * 0.7) * vec3(1.02, 1.06, 1.0);
	float edge = 1e4;
	float half_t = tile_metres * 0.5;
	if ((same & 1) == 0) edge = min(edge, half_t - r.x);
	if ((same & 2) == 0) edge = min(edge, half_t + r.x);
	if ((same & 4) == 0) edge = min(edge, half_t - r.y);
	if ((same & 8) == 0) edge = min(edge, half_t + r.y);
	float rough = 1.0 - smoothstep(6.0, 9.0, edge + (c.nC.r - 0.5) * 6.0);
	vec3 col = mix(fairway, rough_grass(c), rough);
	float soft = max(c.px * 0.6, 0.05);
	vec2 q = vec2(along, back);
	vec2 g = vec2((frand(o.x, o.y, 121u) - 0.5) * 24.0, 14.0 + frand(o.x, o.y, 122u) * (depth - 30.0));
	float d = length((q - g) / vec2(7.5, 6.5));
	col = mix(col, lawn(c, 1.3, q.x * 0.3) * vec3(0.95, 1.12, 0.95), 1.0 - smoothstep(1.18 - soft * 0.2, 1.22, d));
	col = mix(col, lawn(c, 1.6, 0.0) * vec3(1.0, 1.18, 1.0), 1.0 - smoothstep(0.98, 1.02, d));     // the green
	for (int k = 0; k < 3; k++) {
		if (k == 2 && frand(o.x, o.y, 124u) < 0.5) {
			break;
		}
		float a = 6.2832 * frand(o.x * 3 + k, o.y, 123u);
		vec2 b = g + vec2(cos(a) * 10.0, sin(a) * 9.0);
		vec2 side = vec2(-sin(a), cos(a)) * 1.6;
		float sand = max(disc(q - b - side, 2.4, soft), disc(q - b + side, 1.9, soft));
		col = mix(col, lin(vec3(0.86, 0.80, 0.62)) * (0.92 + 0.12 * c.nD.r), sand);
	}
	float tee = box(q, vec2(-g.x * 0.5 - 3.0, depth - 8.0), vec2(-g.x * 0.5 + 3.0, depth - 4.0), soft);
	return mix(col, lawn(c, 1.6, q.x) * vec3(1.0, 1.12, 1.0), tee);
}

// The ground of the plot at this point. Returns false where there's no plot
// (open country). shine: 1 on water.
bool lot_ground(Ctx c, out vec3 col, out float shine) {
	col = vec3(0.0);
	shine = 0.0;
	ivec2 tile = ivec2(floor(c.p / tile_metres));
	ivec4 here = lot_at(tile);
	if (here.r == 0) {
		return false;
	}
	ivec2 owner = tile;
	ivec4 lot = here;
	vec2 f = vec2(0.0, 1.0);
	bool found = here.r != K_ROAD;
	vec2 rel = c.p - (vec2(tile) + 0.5) * tile_metres;
	if (!found) {
		// A road: which plot does this verge belong to? The one on this side.
		ivec2 sx = ivec2(rel.x >= 0.0 ? 1 : -1, 0);
		ivec2 sz = ivec2(0, rel.y >= 0.0 ? 1 : -1);
		bool x_first = abs(rel.x) > abs(rel.y);
		for (int k = 0; k < 2; k++) {
			ivec2 d = ((k == 0) == x_first) ? sx : sz;
			ivec4 n = lot_at(tile + d);
			if (n.r > K_ROAD) {
				owner = tile + d;
				lot = n;
				f = -vec2(d);
				found = true;
				break;
			}
		}
		if (!found) {
			// The corners of a junction: paved in town, grass in the suburbs.
			int diag = lot_at(tile + sx + sz).r;
			bool town = diag == K_SHOPS || diag == K_PLAZA || diag == K_CIVIC || diag == K_TENEMENTS
				|| diag == K_COURT || diag == K_HOSPITAL;
			col = town ? paving(c, c.p, lin(vec3(0.66, 0.64, 0.60)), vec2(0.6, 0.6), false)
				: lawn(c, 0.55, rel.x + rel.y);
			if (diag == K_PARK) {
				col = lawn(c, 1.0 + 0.6 * c.nC.g, rel.x * 0.7 + rel.y * 0.7) * (0.9 + 0.2 * c.nC.g);
			}
			if (diag == K_WOODS) {
				col = lin(WOODS_FLOOR) * (0.75 + 0.5 * c.nD.r);
			}
			if (diag == K_INDUSTRY || diag == K_YARD) {
				col = mix(gravel(c, lin(vec3(0.52, 0.50, 0.45))), rough_grass(c), smoothstep(0.4, 0.6, c.nD.g));
			}
			return true;
		}
	} else {
		f = front_vec(lot.g & 3);
	}
	int kind = lot.r;
	int detail = lot.g >> 3;
	int same = lot.b & 15;
	int flags = lot.a;
	int reach_mask = flags >> 4;
	float reach = float((reach_mask >> side_index(f)) & 1) * street_reach;
	vec2 orel = c.p - (vec2(owner) + 0.5) * tile_metres;
	float along = dot(orel, vec2(-f.y, f.x));
	float back = tile_metres * 0.5 + reach - dot(orel, f);
	float depth = tile_metres + reach;
	if (kind == K_WOODS) {
		if (owner == tile) {
			return false;     // the terrain paints the woods' floor (and their canopy from afar)
		}
		// A road's verge beside woodland: the woods' floor, then a mown strip by the kerb.
		float out_m = dot(orel, f) - tile_metres * 0.5;    // metres out from the woodland
		vec3 woods_floor = lin(WOODS_FLOOR) * (0.75 + 0.5 * c.nD.r);
		col = mix(woods_floor, lawn(c, 0.55, along), smoothstep(8.0, 11.0, out_m + (c.nD.g - 0.5) * 5.0));
		return true;
	}
	if (back < 0.0 && kind != K_PARK) {
		// Between the kerb and the plot: a grass verge in the suburbs, paving in town.
		bool paved = kind == K_SHOPS || kind == K_PLAZA || kind == K_CIVIC || kind == K_TENEMENTS
			|| kind == K_COURT || kind == K_HOSPITAL;
		if (kind == K_INDUSTRY || kind == K_YARD) {
			col = mix(gravel(c, lin(vec3(0.52, 0.50, 0.45))), rough_grass(c), smoothstep(0.4, 0.6, c.nD.g));
			return true;
		}
		col = paved ? paving(c, vec2(along, back), lin(vec3(0.66, 0.64, 0.60)), vec2(0.6, 0.6), false)
			: lawn(c, 0.55, along);
		return true;
	}
	if (kind == K_VILLAS) {
		col = villas(c, along, back, depth, detail, owner, shine);
	} else if (kind == K_TERRACES) {
		col = terraces(c, along, back, depth, owner);
	} else if (kind == K_TENEMENTS) {
		col = tenements(c, along, back, depth, owner);
	} else if (kind == K_COURT) {
		col = court(c, along, back, depth, owner);
	} else if (kind == K_SHOPS) {
		col = shops(c, along, back, depth, detail);
	} else if (kind == K_PLAZA || kind == K_CIVIC) {
		col = plaza(c, along, back, (flags & 2) != 0 && kind == K_PLAZA);
	} else if (kind == K_INDUSTRY) {
		col = industry(c, along, back, depth);
	} else if (kind == K_EMPTY) {
		col = empty_plot(c, along, back, depth, (lot.b >> 4) & 3, (lot.b >> 6) & 3);
	} else if (kind == K_SITE) {
		col = building_site(c, along, back, depth, (lot.b >> 4) & 3);
	} else if (kind == K_PARK) {
		col = park(c, owner, detail, same, reach_mask, shine);
	} else if (kind == K_ALLOTMENTS) {
		col = allotments(c, along, back, depth, owner);
	} else if (kind == K_CAR_PARK) {
		col = tarmac(c);
	} else if (kind == K_SCHOOL) {
		col = school(c, along, back, depth);
	} else if (kind == K_GOLF) {
		col = golf(c, owner, same, along, back, depth);
	} else if (kind == K_YARD) {
		col = mix(concrete(c, vec2(along, back), 5.0), gravel(c, lin(vec3(0.55, 0.53, 0.49))),
			smoothstep(0.45, 0.55, c.nC.g));
	} else if (kind == K_HOSPITAL) {
		col = back < 12.0 ? plaza(c, along, back, false) : lawn(c, 0.6, along);
	} else {
		col = rough_grass(c);
	}
	if ((flags & 1) != 0) {
		// Abandoned: gardens gone to seed.
		col = mix(col, rough_grass(c), 0.55 * smoothstep(0.3, 0.6, c.nD.a + 0.2));
	}
	return true;
}
