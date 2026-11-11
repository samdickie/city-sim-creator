// The detailed building models (assets/models/*.glb). Each part of a model (its
// .glb material: stone walls, slate roof, glass, painted frames, doors and
// shopfronts, metal, chimney pots and so on) is drawn its own way; the part's
// number comes with each vertex (world3d.gd joins all the parts into one surface).
// Per building (from the MultiMesh):
//   COLOR            rgb = wall colour (or, with a map overlay on, the plot's overlay colour);
//                    a below 0.75 = abandoned (grimy walls, boarded windows, no lights)
//   INSTANCE_CUSTOM  rgb = roof colour (or, on flat-roofed buildings, an accent colour:
//                    fire station doors, the hospital cross, a tower's spandrels), a = a random number
//                    (door and shopfront colours, roof finish, which windows are lit at night)
// Colours arrive as sRGB and are made linear here (map overlay colours arrive linear).
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

varying flat int part;  // from UV2.x (world3d.gd joins a model's parts into one surface): 0 stone, 1 roof, 2 glass, 3 frame, 4 door, 5 metal, 6 pot,
						// 7 fascia, 8 render, 9 awning, 10 lead, 11 cladding, 12 sheet, 13 accent,
						// 14 curtain (glass in the wall colour), 15 display (shop windows),
						// 16 beacon (red aviation light), 17 lamp (floodlit trim), 18 office (office glass),
						// 19 green (a roof terrace: sedum or gravel)
uniform bool use_wall_tex = false;
uniform sampler2D wall_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 wall_average = vec3(0.255, 0.22, 0.157);
uniform bool use_roof_tex = false;
uniform sampler2D roof_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 roof_average = vec3(0.284, 0.243, 0.18);
uniform float night = 0.0;
uniform float lit_share = 0.25;      // share of windows lit at night
uniform float lamp_strength = 1.0;   // how bright a lit window is
uniform float late = 0.0;            // 0 = evening, 1 = small hours: homes go dark
uniform bool overlay_on = false;

varying vec3 world_pos;
varying vec3 world_normal;
varying vec3 tint;
varying vec4 extra;
varying float height_up;
varying float derelict;        // 1 = an abandoned building
varying vec3 origin;           // the instance's position (one storey of a tower = one instance)

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float hash3(vec3 p) {
	// (Hashing two cell coordinates added together would line the lit windows up in diagonals.)
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

vec3 to_linear(vec3 c) {
	// The game's colours are written as sRGB (as a paint chart would give them).
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c));
}

vec3 triplanar(sampler2D tex, vec3 p, vec3 n, float metres) {
	// Texture without UVs: project from the three axes and blend by the surface direction.
	vec3 w = pow(abs(n), vec3(4.0));
	w /= (w.x + w.y + w.z);
	return texture(tex, p.zy / metres).rgb * w.x + texture(tex, p.xz / metres).rgb * w.y
		+ texture(tex, p.xy / metres).rgb * w.z;
}

vec3 pick(float r, vec3 a, vec3 b, vec3 c, vec3 d, vec3 e, vec3 f) {
	int k = int(r * 6.0);
	return k == 0 ? a : (k == 1 ? b : (k == 2 ? c : (k == 3 ? d : (k == 4 ? e : f))));
}

void vertex() {
	part = int(UV2.x + 0.5);
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	tint = overlay_on ? COLOR.rgb : to_linear(COLOR.rgb);   // (map overlay colours arrive linear)
	extra = vec4(to_linear(INSTANCE_CUSTOM.rgb), INSTANCE_CUSTOM.a);
	height_up = VERTEX.y;
	derelict = COLOR.a < 0.75 ? 1.0 : 0.0;
	origin = MODEL_MATRIX[3].xyz;
}

vec3 lamp_colour(float k, float warm) {
	// Window light: mostly warm tungsten in homes, cooler white in offices.
	vec3 tungsten = vec3(1.0, 0.48, 0.14);
	vec3 neutral = vec3(1.0, 0.72, 0.42);
	vec3 cool = vec3(0.62, 0.78, 1.0);
	return k < warm ? mix(tungsten, neutral, k / max(warm, 0.01) * 0.6) : (k < warm + (1.0 - warm) * 0.5 ? neutral : cool);
}

void fragment() {
	vec3 c = tint;
	float rough = 0.85;
	float metal = 0.0;
	vec3 glow = vec3(0.0);
	float r = extra.a;
	if (part == 0) {
		// Sandstone: the building's colour, with the stone photo's detail.
		if (use_wall_tex) {
			c *= clamp(triplanar(wall_tex, world_pos, world_normal, 3.0) / wall_average, 0.3, 1.8);
		}
		c *= mix(0.72, 1.0, smoothstep(0.0, 1.2, height_up));
	} else if (part == 8) {
		// Painted render: smooth, with faint weathering.
		c *= 0.94 + 0.08 * hash(floor(world_pos.xy * 2.0) + floor(world_pos.zy * 2.0));
		c *= mix(0.8, 1.0, smoothstep(0.0, 1.0, height_up));
	} else if (part == 1) {
		c = extra.rgb;
		if (use_roof_tex) {
			c *= clamp(triplanar(roof_tex, world_pos, world_normal, 2.5) / roof_average, 0.3, 1.8);
		}
		rough = 0.65;
	} else if (part == 2) {
		// Glass: dark and glossy; at night some windows light up, fewer late on.
		vec3 cell = floor(world_pos / vec3(1.6, 2.9, 1.6));
		float which = hash3(cell + vec3(0.0, 0.0, r * 13.0));
		c = mix(vec3(0.05, 0.07, 0.09), vec3(0.16, 0.18, 0.2), which * 0.5);
		rough = 0.06;
		metal = 0.35;
		float share = lit_share * (1.0 - 0.55 * late);
		float lit = step(1.0 - share, hash3(cell * 1.31 + vec3(r * 5.3, 7.7, 2.9)));
		vec3 lamp = lamp_colour(hash3(cell * 0.77 + vec3(r * 2.1, 3.3, 1.1)), 0.75);
		glow = lamp * lit * night * lamp_strength;
	} else if (part == 3) {
		c = vec3(0.88, 0.87, 0.82);       // white painted timber
		rough = 0.55;
	} else if (part == 4) {
		c = pick(fract(r * 3.7), vec3(0.08, 0.16, 0.32), vec3(0.10, 0.24, 0.16), vec3(0.45, 0.08, 0.08),
			vec3(0.05, 0.05, 0.06), vec3(0.32, 0.10, 0.16), vec3(0.06, 0.28, 0.30));
		rough = 0.4;
	} else if (part == 5) {
		c = vec3(0.09, 0.09, 0.10);
		rough = 0.45;
		metal = 0.4;
	} else if (part == 6) {
		c = vec3(0.30, 0.11, 0.06);       // clay chimney pots (and brick plinths)
	} else if (part == 7) {
		// Painted shopfronts, each shop its own colour, with a lettered sign on the fascia board.
		float along = abs(world_normal.x) > 0.5 ? world_pos.z : world_pos.x;
		float shop = floor(along / 5.0);
		float k = fract(r * 5.3 + hash(vec2(shop, r)) * 0.6);
		c = pick(k, vec3(0.04, 0.16, 0.10), vec3(0.03, 0.06, 0.20), vec3(0.03, 0.03, 0.035),
			vec3(0.36, 0.03, 0.04), vec3(0.62, 0.42, 0.06), vec3(0.04, 0.22, 0.24));
		rough = 0.35;
		glow = c * night * 0.3;           // shopfronts are lit at night
		bool board = height_up > 2.98 && height_up < 3.28 && abs(world_normal.y) < 0.5;
		float letter = step(0.3, fract(along * 2.6)) * step(0.33, hash(vec2(floor(along * 2.6), r * 7.0)))
			* step(0.2, fract(along / 5.0)) * step(fract(along / 5.0), 0.8);
		if (board && letter > 0.5 && derelict < 0.5) {
			vec3 ink = k > 0.66 && k < 0.83 ? vec3(0.02, 0.02, 0.02) : vec3(0.85, 0.78, 0.55);
			c = ink;
			glow = ink * night * 1.4;
		}
	} else if (part == 9) {
		vec3 a = pick(fract(r * 2.9), vec3(0.55, 0.10, 0.10), vec3(0.10, 0.32, 0.20), vec3(0.10, 0.16, 0.38),
			vec3(0.50, 0.40, 0.10), vec3(0.15, 0.15, 0.15), vec3(0.45, 0.18, 0.30));
		float stripe = step(0.5, fract((world_pos.x + world_pos.z) * 0.9));
		c = mix(a, vec3(0.9, 0.88, 0.82), stripe * 0.85);
	} else if (part == 10) {
		// Lead flashing, and flat roofs: dark membrane or grey gravel.
		c = vec3(0.075, 0.08, 0.088);
		rough = 0.6;
		if (world_normal.y > 0.7) {
			float grain = hash(floor(world_pos.xz * 3.0));
			float patch = hash(floor(world_pos.xz / 3.0) + r);
			if (fract(r * 3.3) < 0.55) {
				c = vec3(0.045, 0.048, 0.052) * (0.9 + 0.2 * patch);              // bitumen membrane
			} else {
				c = vec3(0.12, 0.118, 0.112) * (0.85 + 0.3 * grain);              // gravel ballast
				rough = 0.95;
			}
		}
	} else if (part == 11 || part == 12) {
		// Ribbed metal: walls in the building's colour, roofs in the roof colour.
		vec3 base = part == 11 ? tint : extra.rgb;
		float along = abs(world_normal.x) > 0.5 ? world_pos.z : world_pos.x;
		if (part == 12) {
			along = world_pos.x + world_pos.z;
		}
		float rib = smoothstep(0.35, 0.5, abs(fract(along * 3.0) - 0.5) * 2.0);
		c = base * (0.86 + 0.16 * rib);
		c *= mix(0.85, 1.0, smoothstep(0.0, 2.0, height_up));
		rough = 0.5;
		metal = 0.35;
	} else if (part == 13) {
		c = extra.rgb;                    // painted in the building's second colour
		rough = 0.4;
	} else if (part == 14 || part == 18) {
		// Curtain walling in the building's own glass (blue, green, bronze, silver),
		// or dark office glass in a stone or concrete frame. Glossy, a little varied
		// pane to pane. At night offices light up a floor at a time, in cool white.
		vec3 pane = floor(world_pos / vec3(1.5, 3.0, 1.5));
		float which = hash3(pane + vec3(0.0, 0.0, r * 13.0));
		c = part == 14 ? tint * mix(0.62, 1.0, which) : mix(vec3(0.04, 0.05, 0.065), vec3(0.11, 0.12, 0.13), which * 0.6);
		rough = 0.05;
		metal = part == 14 ? 0.55 : 0.4;
		float storey = hash(origin.xz * 0.37 + vec2(floor(origin.y / 3.0 + 0.5), r));
		float lit = max(step(0.62, storey) * step(0.2, which), step(0.85, hash3(pane * 1.37 + vec3(r, 4.1, 0.0))));
		vec3 lamp = lamp_colour(hash(vec2(storey, r * 3.1)), 0.15);
		glow = lamp * lit * night * lamp_strength * 0.75;
	} else if (part == 15) {
		// Shop windows: dark glass with goods and lights behind it; lit all evening.
		float along = abs(world_normal.x) > 0.5 ? world_pos.z : world_pos.x;
		float which = hash(vec2(floor(along * 1.3), r * 9.0));
		c = mix(vec3(0.05, 0.06, 0.07), vec3(0.30, 0.24, 0.16), which * 0.45);
		rough = 0.06;
		metal = 0.3;
		glow = mix(vec3(1.0, 0.78, 0.5), vec3(0.95, 0.92, 0.85), which) * night * lamp_strength * 1.1;
	} else if (part == 19) {
		// The roof terrace of a modern block: planted with sedum, or gravel.
		float patch = hash(floor(world_pos.xz / 2.0) + r);
		float grain = hash(floor(world_pos.xz * 3.0));
		c = fract(r * 3.3) < 0.45 ? mix(vec3(0.07, 0.11, 0.035), vec3(0.15, 0.13, 0.05), patch)
			: vec3(0.12, 0.118, 0.112) * (0.85 + 0.3 * grain);
		rough = 0.95;
	} else if (part == 16) {
		// Red aviation light on a tall building's top.
		c = vec3(0.5, 0.04, 0.03);
		glow = vec3(4.0, 0.15, 0.08) * night + vec3(0.5, 0.0, 0.0);
	} else if (part == 17) {
		// Floodlit trim on a tower's crown: pale by day, glowing at night.
		c = vec3(0.80, 0.80, 0.76);
		rough = 0.5;
		glow = vec3(1.0, 0.86, 0.62) * night * 1.6;
	}
	if (derelict > 0.5 && !overlay_on) {
		// Abandoned: faded and grimy, streaks running down the walls, moss on the
		// roof, windows and doors boarded up, and no lights at night.
		float grey = dot(c, vec3(0.3, 0.59, 0.11));
		float along = abs(world_normal.x) > 0.5 ? world_pos.z : world_pos.x;
		float streak = hash(vec2(floor(along * 1.7), r * 31.0));
		c = mix(c, vec3(grey) * vec3(0.95, 0.92, 0.85), 0.6) * mix(0.6, 0.88, streak);
		if (part == 1 || part == 12) {
			float moss = hash(floor(world_pos.xz / 1.3));
			c = mix(c, vec3(0.06, 0.09, 0.04), step(0.7, moss) * 0.6);
		}
		if (part == 2 || part == 4 || part == 7 || part == 14 || part == 15 || part == 18) {
			// Weathered plywood over windows, doors and shopfronts; the odd pane just broken.
			vec3 pane = floor(world_pos / vec3(1.6, 2.9, 1.6));
			float board = hash(pane.xz + vec2(pane.y * 3.3, r * 17.0));
			bool broken = (part == 2 || part == 14 || part == 18) && board >= 0.8;
			c = broken ? vec3(0.02, 0.02, 0.025) : vec3(0.24, 0.18, 0.11) * (0.8 + 0.3 * hash(pane.zx + 1.7));
		}
		glow = vec3(0.0);
		metal *= 0.3;
		rough = max(rough, 0.7);
	}
	if (overlay_on) {
		// Map overlay: the plot's colour dominates.
		c = mix(c, tint, 0.78);
		glow = glow * 0.2 + tint * 0.15;
		metal = 0.0;
		rough = 0.8;
	}
	ALBEDO = c;
	ROUGHNESS = rough;
	METALLIC = metal;
	EMISSION = glow;
}
