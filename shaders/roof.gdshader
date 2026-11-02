// Roofs: slate or tile courses running across the slope, with weathering.
// COLOR = roof colour (from the MultiMesh).
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;

uniform bool use_texture = false;
uniform sampler2D roof_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 roof_average = vec3(0.284, 0.243, 0.18);   // the slate photo's average colour (linear)
uniform bool overlay_on = false;   // map overlay: COLOR is the plot's overlay colour

varying vec3 world_pos;
varying vec3 roof_colour;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	roof_colour = COLOR.rgb;
}

void fragment() {
	vec3 colour = roof_colour;
	vec2 p = world_pos.xz + vec2(world_pos.y * 0.7);
	if (use_texture) {
		colour *= clamp(texture(roof_tex, p / 2.5).rgb / roof_average, 0.3, 1.8);
	} else {
		float course = fract(world_pos.y / 0.25);
		colour *= mix(0.8, 1.0, smoothstep(0.0, 0.15, course));
		colour *= 0.9 + 0.15 * hash(floor(p / vec2(0.3, 0.25)));
	}
	if (overlay_on) {
		colour = mix(colour, roof_colour, 0.6);
		EMISSION = roof_colour * 0.15;
	}
	ALBEDO = colour;
	ROUGHNESS = 0.6;
	SPECULAR = 0.4;
}
