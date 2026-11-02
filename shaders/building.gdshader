// Walls of every building. Draws windows, floors, shop fronts and
// weathering from the building's real size, so one simple box looks like a building.
// Per building (from the MultiMesh):
//   COLOR            wall colour
//   INSTANCE_CUSTOM  x = width, y = height, z = depth (metres), w = style
//                    style 0 = house, 1 = shop, 2 = industry, 3 = flats, 4 = power plant,
//                    5 = modern glass (bands of glazing with slim mullions),
//                    6 = classical sandstone, 7 = modern framed glazing with clad bays,
//                    8 = classical with shopfronts, 9 = plain paint (doors, signs)
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform bool use_texture = false;
uniform sampler2D wall_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float wall_texture_metres = 3.0;
uniform vec3 wall_average = vec3(0.255, 0.22, 0.157);   // the stone photo's average colour (linear)
uniform float night = 0.0;                                // 0 = day, 1 = night: lights come on
uniform bool overlay_on = false;   // map overlay: COLOR is the plot's overlay colour

varying vec3 local_pos;
varying vec3 local_normal;
varying vec4 size_style;
varying vec3 wall_colour;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	local_pos = VERTEX;            // unit box: x,z from -0.5 to 0.5, y from 0 to 1
	local_normal = NORMAL;
	size_style = INSTANCE_CUSTOM;
	wall_colour = COLOR.rgb;
}

void fragment() {
	vec3 size = size_style.xyz;
	int style = int(size_style.w + 0.5);

	// Position on this face in metres: u across, v up from the ground.
	bool side_x = abs(local_normal.x) > 0.5;
	float u = side_x ? (local_pos.z + 0.5) * size.z : (local_pos.x + 0.5) * size.x;
	float v = local_pos.y * size.y;
	bool is_roof = local_normal.y > 0.5;

	vec3 colour = wall_colour;
	if (style == 9) {
		// Plain paint: no stone, no windows.
	} else if (use_texture && style != 2 && style != 5 && style != 7) {
		// Stone detail from the photo, keeping each building's own colour.
		colour *= clamp(texture(wall_tex, vec2(u, v) / wall_texture_metres).rgb / wall_average, 0.3, 1.8);
	} else {
		// Stone blocks / panels with slight colour variation.
		vec2 block = floor(vec2(u / 0.9, v / 0.45) + vec2(floor(v / 0.45) * 0.5, 0.0));
		colour *= 0.9 + 0.12 * hash(block);
	}
	// Darker near the ground (dirt and shadow).
	colour *= mix(0.7, 1.0, smoothstep(0.0, 1.5, v));

	float rough = 0.85;
	float metal = 0.0;
	vec3 glow = vec3(0.0);
	float sash_bar = 0.0;      // 1 on the white glazing bars of classical sash windows

	if (!is_roof) {
		float floor_h = style == 2 ? 6.0 : 3.0;
		float spacing = style == 1 ? 3.2 : (style == 2 ? 6.0 : 2.8);
		float cell_u = fract(u / spacing);
		float cell_v = fract(v / floor_h);
		float storey = floor(v / floor_h);
		bool edge_margin = u > 0.8 && u < (side_x ? size.z : size.x) - 0.8;
		bool below_top = v < size.y - 0.6;

		bool window = cell_u > 0.22 && cell_u < 0.78 && cell_v > 0.32 && cell_v < 0.82
			&& edge_margin && below_top && v > 0.6;
		if (style == 2) {
			// Industry: a band of high windows only.
			window = window && cell_v > 0.55;
		}
		if (style == 4 || style == 9) {
			window = false;
		}
		if (style == 5) {
			// Floor-to-ceiling glazing with slim mullions every 1.6 m and a
			// slab edge between floors.
			floor_h = 3.2;
			cell_v = fract(v / floor_h);
			storey = floor(v / floor_h);
			window = cell_v > 0.14 && fract(u / 1.6) > 0.05 && below_top && v > 0.4;
		}
		if (style == 6 || style == 8) {
			// Classical: a tall rusticated ground floor, then tall sash windows in
			// lighter stone surrounds, with a string course at every floor.
			float ground = 4.2;
			floor_h = 3.4;
			spacing = 2.7;
			// Centre the window grid on the face, so no window is cut off at a corner.
			float face_w = side_x ? size.z : size.x;
			cell_u = fract((u - fract(face_w / spacing) * spacing * 0.5) / spacing);
			if (v < ground) {
				cell_v = v / ground;
				storey = 0.0;
				colour *= mix(0.8, 1.0, step(0.08, fract(v / 0.5)));   // rustication grooves
				window = edge_margin && cell_u > 0.28 && cell_u < 0.72 && cell_v > 0.16 && cell_v < 0.8;
				if (style == 8) {
					// Shopfronts with a dark painted fascia above.
					window = edge_margin && v > 0.5 && v < 3.2 && fract(u / 5.0) > 0.1;
					if (v >= 3.2 && v < 3.8) {
						colour = vec3(0.09, 0.14, 0.12);
					}
				}
			} else {
				float upper = v - ground;
				cell_v = fract(upper / floor_h);
				storey = 1.0 + floor(upper / floor_h);
				window = edge_margin && below_top && cell_u > 0.31 && cell_u < 0.69 && cell_v > 0.18 && cell_v < 0.84;
				bool surround = cell_u > 0.25 && cell_u < 0.75 && cell_v > 0.12 && cell_v < 0.9;
				if (surround && !window && edge_margin && below_top) {
					colour *= 1.2;
				}
				if (cell_v < 0.05) {
					colour *= 1.15;   // string course
				}
				if (window) {
					// Astragals: one upright and one cross bar per sash.
					float wu = (cell_u - 0.31) / 0.38;
					float wv = (cell_v - 0.18) / 0.66;
					sash_bar = (abs(wu - 0.5) < 0.05 || abs(wv - 0.5) < 0.035) ? 1.0 : 0.0;
				}
			}
		}
		if (style == 7) {
			// Modern premium: storey-high glazing between slim light frames, every
			// third bay clad (timber, bronze or stone = the wall colour), white slab edges.
			floor_h = 3.2;
			spacing = 2.4;
			float face_w = side_x ? size.z : size.x;
			float u_c = u - fract(face_w / spacing) * spacing * 0.5;
			cell_u = fract(u_c / spacing);
			cell_v = fract(v / floor_h);
			storey = floor(v / floor_h);
			float bay = floor(u_c / spacing);
			bool clad = mod(bay, 3.0) < 1.0;
			bool slab_edge = cell_v < 0.09;
			bool frame_line = cell_u < 0.05;
			window = !clad && !slab_edge && !frame_line && below_top;
			if (slab_edge || frame_line) {
				colour = vec3(0.88, 0.88, 0.86);
			} else if (clad) {
				colour = wall_colour * (0.92 + 0.12 * hash(vec2(bay, storey)));   // panel to panel variation
			}
		}
		if (style == 1 && storey < 0.5) {
			// Shop front: a big glass window along the ground floor with a fascia above.
			window = edge_margin && v > 0.4 && v < 2.5;
			if (v >= 2.5 && v < 3.0) {
				colour = vec3(0.12, 0.16, 0.2);
			}
		}
		if (window) {
			// Glass: dark, glossy, the odd one with curtains or lights.
			vec2 window_id = floor(vec2(u / spacing, v / floor_h)) + size.xz;
			float which = hash(window_id);
			colour = mix(vec3(0.07, 0.09, 0.12), vec3(0.32, 0.30, 0.26), step(0.85, which));
			rough = 0.08;
			metal = 0.3;
			if (style == 5 || style == 7) {
				// Tinted glass that reflects the sky, slightly varied pane to pane.
				colour = mix(vec3(0.10, 0.17, 0.24), vec3(0.16, 0.24, 0.30), which);
				rough = 0.04;
				metal = 0.65;
			}
			if (sash_bar > 0.5) {
				colour = vec3(0.86, 0.85, 0.80);   // painted timber glazing bars
				rough = 0.6;
				metal = 0.0;
			}
			// At night, about half the windows are lit, in slightly different warm tones.
			float lit = step(0.45, hash(window_id + vec2(3.7, 1.3)));
			vec3 lamp = mix(vec3(1.0, 0.72, 0.38), vec3(1.0, 0.86, 0.62), hash(window_id + 9.1));
			if (style == 1 && storey < 0.5) {
				lit = 1.0;   // shop windows stay lit
				lamp = vec3(1.0, 0.92, 0.78);
			}
			glow = lamp * lit * night * 2.2 * (1.0 - sash_bar);
		} else if (cell_v < 0.32 && cell_v > 0.26 && (style < 2 || style == 3) && edge_margin && cell_u > 0.18 && cell_u < 0.82) {
			// Stone sill under each window.
			colour *= 1.25;
		}
	}

	if (overlay_on) {
		// Map overlay: the plot's colour dominates (windows still show faintly).
		colour = mix(colour, wall_colour, 0.75);
		glow = glow * 0.2 + wall_colour * 0.15;
		metal = 0.0;
		rough = 0.8;
	}
	ALBEDO = colour;
	ROUGHNESS = rough;
	METALLIC = metal;
	EMISSION = glow;
}
