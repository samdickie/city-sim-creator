// Frosted glass for the interface panels: the game behind is blurred and tinted,
// with rounded corners, a soft sheen from the top and a hairline highlight round
// the edge. "size" is the panel's size in pixels (set by hud.gd).
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform vec2 size = vec2(100.0, 100.0);
uniform float radius = 22.0;
uniform vec4 tint : source_color = vec4(0.11, 0.13, 0.12, 0.58);
uniform float blur = 3.6;

float rounded_box(vec2 p, vec2 half_size, float r) {
	vec2 q = abs(p) - half_size + r;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void fragment() {
	vec2 p = UV * size - size * 0.5;
	float d = rounded_box(p, size * 0.5, radius);
	float inside = 1.0 - smoothstep(-1.0, 0.5, d);
	vec3 behind = textureLod(screen_tex, SCREEN_UV, blur).rgb;
	vec3 c = mix(behind, tint.rgb, tint.a);
	c += vec3(0.06) * (1.0 - UV.y);                       // a soft sheen from the top
	float rim = 1.0 - smoothstep(0.0, 1.4, abs(d + 0.8));
	c = mix(c, vec3(1.0), rim * (0.10 + 0.12 * (1.0 - UV.y)));   // hairline edge, brighter on top
	COLOR = vec4(c, inside);
}
