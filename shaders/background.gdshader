shader_type canvas_item;

// Noir-jazz backdrop in one pass: smoky gradient, comic halftone glow,
// a pale moon, two parallax layers of endless megastructure towers with
// lit windows, film grain + scratches, and hazard-striped side walls.

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
	float lit = step(0.82, hash(wid + vec2(cx * 7.0, seed)));
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

	// Comic halftone glow rising from the bottom
	float glow = smoothstep(0.35, 1.05, uv.y);
	vec2 hc = fract(px / 9.0) - 0.5;
	float dot_r = glow * 0.55;
	float halftone = 1.0 - smoothstep(dot_r - 0.06, dot_r + 0.06, length(hc));
	col = mix(col, sky_bottom.rgb * 1.6 + accent.rgb * 0.15, halftone * 0.55);

	// Big pale moon, barely moving, halftone-shaded
	vec2 mp = rel + cam_pos * 0.02 - vec2(view_size.x * 0.22, -view_size.y * 0.18);
	float md = length(mp);
	float mr = min(view_size.x, view_size.y) * 0.22;
	if (md < mr) {
		float shade = clamp((mp.x + mp.y) / mr * 0.6 + 0.5, 0.0, 1.0);
		float hd = 1.0 - smoothstep(shade * 0.5 - 0.05, shade * 0.5 + 0.05, length(hc));
		vec3 moon = mix(vec3(0.93, 0.89, 0.78), vec3(0.93, 0.89, 0.78) * 0.55, hd);
		col = mix(col, moon, 0.85 * (1.0 - smoothstep(mr - 2.0, mr, md)));
	}

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

	// Side walls: ink with hazard stripes along the edge
	float wx = rel.x + cam_pos.x;
	float out_d = abs(wx) - half_width;
	if (out_d > 0.0) {
		col = vec3(0.055, 0.047, 0.043);
		float stripe = step(0.5, fract((wx * sign(wx) + rel.y + cam_pos.y) / 56.0));
		col = mix(col, accent.rgb, stripe * (1.0 - step(34.0, out_d)));
		col = mix(col, vec3(0.0), step(34.0, out_d) * step(out_d, 40.0));
	}

	// Film grain, scratches, vignette
	float grain = hash(px + fract(t * 7.13) * 100.0) - 0.5;
	col += grain * 0.07 * (0.5 + detail * 0.5);
	if (detail > 0.5) {
		float sx = floor(px.x / 2.0);
		float scratch = step(0.9985, hash(vec2(sx, floor(t * 12.0))));
		col = mix(col, vec3(0.9, 0.85, 0.7), scratch * 0.25);
	}
	vec2 v = uv - 0.5;
	col *= 1.0 - dot(v, v) * 1.1;

	COLOR = vec4(col, 1.0);
}
