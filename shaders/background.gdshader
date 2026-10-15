shader_type canvas_item;

// Single-pass procedural backdrop: sky gradient, twinkling stars, two layers
// of parallax floating islands and the out-of-bounds side walls.
// No textures and no screen reads, so it is cheap on WebGL2.

uniform vec4 sky_top : source_color = vec4(0.10, 0.09, 0.20, 1.0);
uniform vec4 sky_bottom : source_color = vec4(0.20, 0.13, 0.30, 1.0);
uniform vec4 island_color : source_color = vec4(0.14, 0.12, 0.26, 1.0);
uniform vec4 accent : source_color = vec4(1.0, 0.6, 0.4, 1.0);
uniform vec2 cam_pos = vec2(0.0);
uniform vec2 view_size = vec2(1280.0, 720.0);
uniform float half_width = 660.0;
uniform float detail = 1.0;
uniform float time_offset = 0.0;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float rbox(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + r;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

// Floating island silhouettes in a grid; one island per cell. Each island is
// a flat top slab with a tapering rocky underside (a pointed ellipse).
float islands(vec2 p, vec2 cell, float seed) {
	vec2 id = floor(p / cell);
	vec2 f = p - id * cell - cell * 0.5;
	float h = hash(id + seed);
	if (h < 0.45) return 0.0;
	vec2 jitter = (vec2(hash(id + seed + 3.1), hash(id + seed + 7.7)) - 0.5) * cell * 0.3;
	float w = cell.x * (0.14 + 0.14 * hash(id + 1.3));
	float th = cell.y * (0.035 + 0.02 * hash(id + 2.9));
	vec2 q = f - jitter;
	float top = rbox(q, vec2(w, th), th * 0.9);
	// Underside: width shrinks with depth, slightly wobbly edge.
	float depth = w * (0.55 + 0.4 * hash(id + 5.3));
	float y = clamp(q.y / depth, 0.0, 1.0);
	float wob = sin(q.y * 0.15 + h * 20.0) * 4.0;
	float half_w = w * 0.92 * (1.0 - y) * (1.0 - y * 0.3) + wob * (1.0 - y);
	float under = max(abs(q.x) - half_w, max(-q.y, q.y - depth));
	float d = min(top, under);
	return 1.0 - smoothstep(-1.0, 1.0, d);
}

void fragment() {
	vec2 uv = UV;
	vec2 rel = (uv - 0.5) * view_size;
	float t = TIME + time_offset;

	vec3 col = mix(sky_top.rgb, sky_bottom.rgb, smoothstep(0.0, 1.0, uv.y));

	// Stars (very far, barely move)
	vec2 sp = rel + cam_pos * 0.04;
	vec2 sid = floor(sp / 42.0);
	float s = hash(sid);
	if (s > 0.86) {
		vec2 so = (vec2(hash(sid + 1.0), hash(sid + 2.0)) - 0.5) * 30.0;
		float d = length(sp - sid * 42.0 - 21.0 - so);
		float tw = 0.55 + 0.45 * sin(t * (1.0 + s * 3.0) + s * 40.0);
		col += vec3(1.0, 0.95, 0.9) * (1.0 - smoothstep(0.6, 1.8, d)) * tw * 0.55 * detail;
	}

	// Far islands
	if (detail > 0.5) {
		float far = islands(rel + cam_pos * 0.15 + vec2(t * 4.0, 0.0), vec2(420.0, 300.0), 11.0);
		col = mix(col, mix(island_color.rgb, sky_top.rgb, 0.45), far * 0.8);
	}
	// Near islands with a lit rim
	vec2 np = rel + cam_pos * 0.35;
	float near = islands(np, vec2(560.0, 420.0), 37.0);
	float near_up = islands(np + vec2(0.0, 3.0), vec2(560.0, 420.0), 37.0);
	col = mix(col, island_color.rgb, near);
	col += accent.rgb * clamp(near - near_up, 0.0, 1.0) * 0.35;

	// Side walls outside the playable column
	float wx = rel.x + cam_pos.x;
	float out_d = abs(wx) - half_width;
	if (out_d > 0.0) {
		float stripes = step(0.5, fract((wx + rel.y + cam_pos.y) / 48.0)) * 0.06;
		vec3 wall = sky_top.rgb * 0.45 + stripes;
		col = mix(col, wall, 0.85);
		col += accent.rgb * (1.0 - smoothstep(0.0, 6.0, out_d)) * 0.5;
	}

	// Soft vignette
	vec2 v = uv - 0.5;
	col *= 1.0 - dot(v, v) * 0.55;

	COLOR = vec4(col, 1.0);
}
