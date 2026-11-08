// The detailed building models (assets/models/*.glb). Each material of a model
// gets this shader with its own "part": stone walls, slate roof, glass, painted
// frames, doors and shopfronts, metal, chimney pots and so on.
// Per building (from the MultiMesh):
//   COLOR            wall colour (or, with a map overlay on, the plot's overlay colour)
//   INSTANCE_CUSTOM  rgb = roof colour (or, on flat-roofed buildings, an accent colour:
//                    fire station doors, the hospital cross), a = a random number (door and shopfront colours,
//                    which windows are lit at night)
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform int part = 0;   // 0 stone, 1 roof, 2 glass, 3 frame, 4 door, 5 metal, 6 pot,
						// 7 fascia, 8 render, 9 awning, 10 lead, 11 cladding, 12 sheet, 13 accent
uniform bool use_wall_tex = false;
uniform sampler2D wall_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 wall_average = vec3(0.255, 0.22, 0.157);
uniform bool use_roof_tex = false;
uniform sampler2D roof_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 roof_average = vec3(0.284, 0.243, 0.18);
uniform float night = 0.0;
uniform bool overlay_on = false;

varying vec3 world_pos;
varying vec3 world_normal;
varying vec3 tint;
varying vec4 extra;
varying float height_up;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
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
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	tint = COLOR.rgb;
	extra = INSTANCE_CUSTOM;
	height_up = VERTEX.y;
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
		// Glass: dark and glossy; at night about half the windows light up.
		vec3 cell = floor(world_pos / vec3(1.6, 2.9, 1.6));
		float which = hash(cell.xz + vec2(cell.y * 7.1, r * 13.0));
		c = mix(vec3(0.05, 0.07, 0.09), vec3(0.16, 0.18, 0.2), which * 0.5);
		rough = 0.06;
		metal = 0.35;
		float lit = step(0.45, hash(cell.zx + vec2(r * 5.3, cell.y * 2.3)));
		vec3 lamp = mix(vec3(1.0, 0.70, 0.36), vec3(1.0, 0.86, 0.62), which);
		glow = lamp * lit * night * 2.2;
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
		c = vec3(0.55, 0.30, 0.20);       // clay chimney pots
	} else if (part == 7) {
		c = pick(fract(r * 5.3), vec3(0.06, 0.20, 0.15), vec3(0.06, 0.10, 0.22), vec3(0.04, 0.04, 0.05),
			vec3(0.35, 0.06, 0.08), vec3(0.75, 0.70, 0.58), vec3(0.20, 0.28, 0.30));
		rough = 0.35;
		glow = c * night * 0.25;          // shopfronts are lit at night
	} else if (part == 9) {
		vec3 a = pick(fract(r * 2.9), vec3(0.55, 0.10, 0.10), vec3(0.10, 0.32, 0.20), vec3(0.10, 0.16, 0.38),
			vec3(0.50, 0.40, 0.10), vec3(0.15, 0.15, 0.15), vec3(0.45, 0.18, 0.30));
		float stripe = step(0.5, fract((world_pos.x + world_pos.z) * 0.9));
		c = mix(a, vec3(0.9, 0.88, 0.82), stripe * 0.85);
	} else if (part == 10) {
		c = vec3(0.30, 0.32, 0.34);       // lead flashing and flat roofs
		rough = 0.6;
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
