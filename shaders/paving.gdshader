// Flat surfaces laid on the plots (world3d.gd _slab): car parks, pavements,
// driveways, yards. COLOR.rgb is the surface's colour; COLOR.a says what it is
// made of, so it gets the right texture (see world3d.gd SURFACE_...):
//   1.0 plain   0.8 tarmac (patched, oil-stained)   0.6 paving slabs
//   0.4 block paving (drives)   0.2 concrete in bays   0.05 a swimming pool
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;   // the terrain's four smooth noises

varying vec3 world_pos;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float joints(vec2 q, vec2 size, float px) {
	// 1 on the joints between slabs or blocks, fading once they're tiny on screen.
	vec2 edge = (0.5 - abs(fract(q / size) - 0.5)) * size;
	float j = 1.0 - smoothstep(0.015, 0.015 + max(px * 0.7, 0.03), min(edge.x, edge.y));
	return j * (1.0 - smoothstep(0.08, 0.25, px / min(size.x, size.y)));
}

void fragment() {
	vec2 p = world_pos.xz;
	float px = max(length(fwidth(p)), 0.02);
	vec3 base = pow(COLOR.rgb, vec3(2.2));     // (colours are given in sRGB)
	float kind = COLOR.a;
	vec4 n1 = texture(noise_tex, p / 29.0);
	vec4 n2 = texture(noise_tex, p / 6.5);
	vec3 col = base * (0.94 + 0.12 * n1.r);
	float rough = 0.9;
	if (kind > 0.7 && kind < 0.9) {
		// Tarmac: grainy, with darker patched repairs, oil under the parked cars, faded wear.
		float grain = mix(0.5, hash(floor(p * 9.0)), 1.0 - smoothstep(0.05, 0.2, px));
		col = base * (0.85 + 0.3 * grain) * (0.9 + 0.2 * n1.g);
		float patches = step(0.72, texture(noise_tex, p / 13.0).b);
		col *= 1.0 - 0.18 * patches;
		col *= 1.0 - 0.3 * smoothstep(0.62, 0.8, n2.r);
		col = mix(col, col * 1.35, smoothstep(0.55, 0.8, n1.a) * 0.6);   // sun-bleached, worn
		rough = 0.85;
	} else if (kind > 0.5 && kind < 0.7) {
		// Paving slabs, 0.6 m, each a slightly different shade.
		col = base * (0.93 + 0.1 * hash(floor(p / 0.6))) * (1.0 - 0.3 * joints(p, vec2(0.6), px));
		col *= 1.0 - 0.15 * smoothstep(0.65, 0.85, n2.g);       // weathering
	} else if (kind > 0.3 && kind < 0.5) {
		// Block paving in a stretcher bond.
		vec2 q = p / vec2(0.2, 0.1);
		q.x += floor(q.y) * 0.5;
		col = base * (0.9 + 0.16 * hash(floor(q))) * (1.0 - 0.25 * joints(q * vec2(0.2, 0.1), vec2(0.2, 0.1), px));
	} else if (kind < 0.1) {
		// A swimming pool: bright, glossy, with soft ripples and a pale tiled edge.
		col = base * (0.85 + 0.3 * n2.b) * (1.0 + 0.25 * smoothstep(0.6, 0.9, texture(noise_tex, p / 2.3 + TIME * 0.02).r));
		rough = 0.06;
	} else if (kind > 0.1 && kind < 0.3) {
		// Concrete bays with stains.
		col = base * (1.0 - 0.3 * joints(p, vec2(5.0), px)) * (0.9 + 0.2 * n1.b);
		col *= 1.0 - 0.4 * smoothstep(0.65, 0.82, n2.r * 0.7 + n1.a * 0.3);
	}
	ALBEDO = col;
	ROUGHNESS = rough;
}
