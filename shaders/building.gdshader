// Walls of every building. Draws windows, floors, shop fronts and
// weathering from the building's real size, so one simple box looks like a building.
// Per building (from the MultiMesh):
//   COLOR            wall colour
//   INSTANCE_CUSTOM  x = width, y = height, z = depth (metres), w = style
//                    style 0 = house, 1 = shop, 2 = industry, 3 = flats, 4 = power plant
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform bool use_texture = false;
uniform sampler2D wall_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float wall_texture_metres = 3.0;

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
	if (use_texture && style != 2) {
		colour *= texture(wall_tex, vec2(u, v) / wall_texture_metres).rgb * 1.6;
	} else {
		// Stone blocks / panels with slight colour variation.
		vec2 block = floor(vec2(u / 0.9, v / 0.45) + vec2(floor(v / 0.45) * 0.5, 0.0));
		colour *= 0.9 + 0.12 * hash(block);
	}
	// Darker near the ground (dirt and shadow).
	colour *= mix(0.7, 1.0, smoothstep(0.0, 1.5, v));

	float rough = 0.85;
	float metal = 0.0;

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
		if (style == 4) {
			window = false;
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
			float which = hash(floor(vec2(u / spacing, v / floor_h)) + size.xz);
			colour = mix(vec3(0.07, 0.09, 0.12), vec3(0.32, 0.30, 0.26), step(0.85, which));
			rough = 0.08;
			metal = 0.3;
		} else if (cell_v < 0.32 && cell_v > 0.26 && style != 2 && style != 4 && edge_margin && cell_u > 0.18 && cell_u < 0.82) {
			// Stone sill under each window.
			colour *= 1.25;
		}
	}

	ALBEDO = colour;
	ROUGHNESS = rough;
	METALLIC = metal;
}
