// Tree canopies: each blob gets a lumpy outline, leaf clumps of light and
// shade, a darker underside and a little light through the leaves.
// COLOR = the canopy colour (from the MultiMesh, in sRGB).
shader_type spatial;
render_mode diffuse_lambert_wrap, specular_schlick_ggx;

varying vec3 world_pos;
varying vec3 leaf_colour;
varying float local_y;

float hash3(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

float noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	vec3 u = f * f * (3.0 - 2.0 * f);
	float a = mix(mix(hash3(i), hash3(i + vec3(1, 0, 0)), u.x),
		mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), u.x), u.y);
	float b = mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), u.x),
		mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), u.x), u.y);
	return mix(a, b, u.z);
}

vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c));
}

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// Push the surface in and out so the outline isn't a perfect ball.
	float bump = noise3(w * 0.45) - 0.5;
	VERTEX += NORMAL * bump * 0.22;
	world_pos = w;
	leaf_colour = to_linear(COLOR.rgb);
	local_y = VERTEX.y;              // -0.5 (bottom) to 0.5 (top) on the unit shapes
}

void fragment() {
	// Clumps of leaves about a metre across, with finer speckle on top.
	float clump = noise3(world_pos * 0.9);
	float fine = noise3(world_pos * 3.1);
	vec3 c = leaf_colour * (0.62 + 0.55 * clump) * (0.88 + 0.24 * fine);
	// Darker underneath and in the middle of the tree.
	c *= mix(0.55, 1.08, smoothstep(-0.5, 0.45, local_y));
	ALBEDO = c;
	ROUGHNESS = 0.92;
	SPECULAR = 0.18;
	BACKLIGHT = c * 0.45;           // sunlight glowing through the leaves
}
