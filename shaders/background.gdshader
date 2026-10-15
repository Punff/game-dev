shader_type canvas_item;

// Backdrop in one pass: smoky gradient, two parallax layers of endless
// towers with a few lit windows. Grain/grime comes from the global Grit overlay.

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

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

// Two-octave value noise: cheap "brush / smoke" mottling.
float fbm(vec2 p) {
	return vnoise(p) * 0.65 + vnoise(p * 2.3 + 7.1) * 0.35;
}

// Endless vertical towers: returns (coverage, window light).
vec2 towers(vec2 p, float cell_w, float seed) {
	float cx = floor(p.x / cell_w);
	float h = hash(vec2(cx, seed));
	if (h < 0.35) return vec2(0.0);
	float w = cell_w * (0.3 + 0.45 * hash(vec2(cx, seed + 1.0)));
	float off = (hash(vec2(cx, seed + 2.0)) - 0.5) * (cell_w - w);
	float lx = p.x - cx * cell_w - cell_w * 0.5 - off + sin(p.y * 0.013 + h * 30.0) * 4.0 + (vnoise(vec2(p.y * 0.08, cx)) - 0.5) * 3.0;
	if (abs(lx) > w * 0.5) return vec2(0.0);
	// windows
	vec2 wcell = vec2(22.0, 30.0);
	vec2 wid = floor(vec2(lx + w * 0.5, p.y) / wcell);
	vec2 wf = fract(vec2(lx + w * 0.5, p.y) / wcell);
	float lit = step(0.93, hash(wid + vec2(cx * 7.0, seed)));
	float win = lit * step(0.3, wf.x) * step(wf.x, 0.7) * step(0.3, wf.y) * step(wf.y, 0.75);
	// dark seams at the tower edge, and floor bands every so often
	float edge = step(w * 0.5 - 6.0, abs(lx));
	float band = step(mod(p.y + h * 500.0, 180.0), 6.0) * 0.35;
	return vec2(1.0 + band, win * (1.0 - edge));
}

void fragment() {
	vec2 uv = UV;
	vec2 rel = (uv - 0.5) * view_size;
	float t = TIME + time_offset;
	vec2 px = FRAGCOORD.xy;

	// Smoky gradient, warmer toward the bottom of the screen, with drifting
	// smoke and painterly mottling so nothing is a flat fill.
	vec3 col = mix(sky_top.rgb, sky_bottom.rgb, smoothstep(0.1, 1.0, uv.y));
	float smoke = fbm((rel + cam_pos * 0.08) / 260.0 + vec2(t * 0.02, 0.0));
	col *= 0.8 + smoke * 0.4;

	// Far towers
	if (detail > 0.5) {
		vec2 fp = rel + cam_pos * vec2(0.2, 0.2);
		vec2 far = towers(fp, 260.0, 3.0);
		col = mix(col, mix(island_color.rgb, sky_top.rgb, 0.65) * (0.85 + fbm(fp / 30.0) * 0.3), min(far.x, 1.0));
		col = mix(col, accent.rgb * 0.6, far.y * 0.35);
	}
	// Near towers
	vec2 np = rel + cam_pos * vec2(0.45, 0.45);
	vec2 near = towers(np, 380.0, 11.0);
	// Keep towers a step back from pure ink so gameplay pops in front.
	float paint = fbm(np / 40.0) * 0.5 + fbm(np / 9.0) * 0.5;
	vec3 tower = mix(island_color.rgb, sky_top.rgb, 0.3) * (0.75 + paint * 0.5);
	col = mix(col, tower * (1.0 - max(near.x - 1.0, 0.0)), min(near.x, 1.0));
	col = mix(col, accent.rgb * 0.8, near.y * 0.6);


	COLOR = vec4(col, 1.0);
}
