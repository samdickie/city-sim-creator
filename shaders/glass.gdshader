// Frosted glass for the interface panels: the game behind is blurred, mostly
// drained of colour and darkened to a cool slate, so white text reads the same
// over bright grass, dark sea or at night. Rounded corners, a soft sheen from the
// top, a hairline highlight round the edge and a soft shadow underneath.
// "size" is the panel's size in pixels and "pad" the shadow margin round it
// (the ColorRect is the panel plus "pad" on every side; both set by hud.gd).
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform vec2 size = vec2(100.0, 100.0);
uniform float pad = 0.0;
uniform float radius = 16.0;
uniform vec4 tint : source_color = vec4(0.07, 0.085, 0.11, 0.70);
uniform float blur = 3.2;
uniform float colour_left = 0.25;     // how much of the colour behind shows through (0 = grey)
uniform float shadow = 0.30;

float rounded_box(vec2 p, vec2 half_size, float r) {
	vec2 q = abs(p) - half_size + r;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void fragment() {
	vec2 full = size + 2.0 * pad;
	vec2 p = UV * full - full * 0.5;
	float r = min(radius, min(size.x, size.y) * 0.5);
	float d = rounded_box(p, size * 0.5, r);
	float inside = 1.0 - smoothstep(-1.0, 0.5, d);

	// Shadow: a soft blur of the panel's shape, nudged down a little.
	float ds = rounded_box(p - vec2(0.0, 3.0), size * 0.5, r);
	float shade = shadow * (1.0 - smoothstep(-4.0, max(pad, 1.0), ds));

	// Glass: a few blurred taps of the screen behind, so the mip blocks don't show.
	vec2 px = SCREEN_PIXEL_SIZE * 6.0;
	vec3 behind = textureLod(screen_tex, SCREEN_UV, blur).rgb * 0.4;
	behind += textureLod(screen_tex, SCREEN_UV + vec2(px.x, px.y), blur).rgb * 0.15;
	behind += textureLod(screen_tex, SCREEN_UV + vec2(-px.x, px.y), blur).rgb * 0.15;
	behind += textureLod(screen_tex, SCREEN_UV + vec2(px.x, -px.y), blur).rgb * 0.15;
	behind += textureLod(screen_tex, SCREEN_UV + vec2(-px.x, -px.y), blur).rgb * 0.15;
	float luma = dot(behind, vec3(0.299, 0.587, 0.114));
	behind = mix(vec3(luma), behind, colour_left);
	vec3 c = mix(behind, tint.rgb, tint.a);
	vec2 uv = (p + size * 0.5) / size;                     // 0-1 over the panel itself
	c += vec3(0.05) * (1.0 - uv.y);                        // a soft sheen from the top
	float rim = 1.0 - smoothstep(0.0, 1.4, abs(d + 0.8));
	c = mix(c, vec3(1.0), rim * (0.08 + 0.12 * (1.0 - uv.y)));   // hairline edge, brighter on top

	COLOR = vec4(c * inside, max(inside, shade * (1.0 - inside)));
}
