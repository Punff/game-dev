shader_type canvas_item;

// Backdrop in one pass: smoky gradient, two parallax layers of endless
// towers with a few lit windows, and light film grain.

uniform vec4 sky_top : source_color = vec4(0.10, 0.14, 0.20, 1.0);
uniform vec4 sky_bottom : source_color = vec4(0.35, 0.16, 0.14, 1.0);
uniform vec4 island_color : source_color = vec4(0.05, 0.05, 0.05, 1.0); // towers
uniform vec4 accent : source_color = vec4(0.89, 0.66, 0.17, 1.0);
uniform vec2 cam_pos = vec2(0.0);
uniform vec2 view_size = vec2(1280.0, 720.0);
uniform float half_width = 1100.0;
uniform float detail = 1.0;
uniform float time_offset = 0.0;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

// Endless vertical towers: returns (coverage, window light).
vec2 towers(vec2 p, float cell_w, float seed) {
	float cx = floor(p.x / cell_w);
	float h = hash(vec2(cx, seed));
	if (h < 0.35) return vec2(0.0);
	float w = cell_w * (0.3 + 0.45 * hash(vec2(cx, seed + 1.0)));
	float off = (hash(vec2(cx, seed + 2.0)) - 0.5) * (cell_w - w);
	float lx = p.x - cx * cell_w - cell_w * 0.5 - off;
	if (abs(lx) > w * 0.5) return vec2(0.0);
	// windows
	vec2 wcell = vec2(22.0, 30.0);
	vec2 wid = floor(vec2(lx + w * 0.5, p.y) / wcell);
	vec2 wf = fract(vec2(lx + w * 0.5, p.y) / wcell);
	float lit = step(0.93, hash(wid + vec2(cx * 7.0, seed)));
	float win = lit * step(0.3, wf.x) * step(wf.x, 0.7) * step(0.3, wf.y) * step(wf.y, 0.75);
	// dark seams at the tower edge
	float edge = step(w * 0.5 - 6.0, abs(lx));
	return vec2(1.0, win * (1.0 - edge));
}

void fragment() {
	vec2 uv = UV;
	vec2 rel = (uv - 0.5) * view_size;
	float t = TIME + time_offset;
	vec2 px = FRAGCOORD.xy;

	// Smoky gradient, warmer toward the bottom of the screen
	vec3 col = mix(sky_top.rgb, sky_bottom.rgb, smoothstep(0.1, 1.0, uv.y));

	// Far towers
	if (detail > 0.5) {
		vec2 fp = rel + cam_pos * vec2(0.2, 0.2);
		vec2 far = towers(fp, 260.0, 3.0);
		col = mix(col, mix(island_color.rgb, sky_top.rgb, 0.65), far.x);
		col = mix(col, accent.rgb * 0.6, far.y * 0.35);
	}
	// Near towers
	vec2 np = rel + cam_pos * vec2(0.45, 0.45);
	vec2 near = towers(np, 380.0, 11.0);
	// Keep towers a step back from pure ink so gameplay pops in front.
	col = mix(col, mix(island_color.rgb, sky_top.rgb, 0.3), near.x);
	col = mix(col, accent.rgb * 0.8, near.y * 0.6);

	// Film grain, scratches, vignette
	float grain = hash(px + fract(t * 7.13) * 100.0) - 0.5;
	col += grain * 0.04;
	vec2 v = uv - 0.5;
	col *= 1.0 - dot(v, v) * 1.1;

	COLOR = vec4(col, 1.0);
}
