shader_type canvas_item;

// Molten slag: ink outline at the surface, cooling black crust plates
// drifting on rust, and a halftone heat glow above it.

uniform vec2 rect_size = vec2(2000.0, 2000.0);
uniform float surface = 60.0;
uniform float world_x = 0.0;
uniform vec4 hot : source_color = vec4(0.95, 0.70, 0.22, 1.0);
uniform vec4 mid : source_color = vec4(0.82, 0.30, 0.13, 1.0);
uniform vec4 deep : source_color = vec4(0.30, 0.06, 0.08, 1.0);

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void fragment() {
	vec2 p = UV * rect_size;
	float x = p.x + world_x;
	float wave = sin(x * 0.012 + TIME * 1.7) * 9.0 + sin(x * 0.031 - TIME * 1.1) * 4.0;
	float sy = surface + wave;
	float d = p.y - sy;
	if (d < 0.0) {
		// halftone heat haze above the surface
		vec2 hc = fract(FRAGCOORD.xy / 8.0) - 0.5;
		float r = clamp(1.0 + d / 70.0, 0.0, 1.0) * 0.5;
		float dotv = 1.0 - smoothstep(r - 0.05, r + 0.05, length(hc));
		COLOR = vec4(mid.rgb, dotv * 0.75);
	} else if (d < 6.0) {
		COLOR = vec4(0.05, 0.04, 0.04, 1.0);   // ink outline
	} else {
		float depth = clamp(d / 300.0, 0.0, 1.0);
		vec3 col = mix(hot.rgb, mid.rgb, smoothstep(0.0, 40.0, d));
		col = mix(col, deep.rgb, depth);
		// drifting crust plates (cell noise)
		vec2 q = vec2(x + TIME * 14.0, p.y * 1.6) / 70.0;
		vec2 id = floor(q);
		vec2 f = fract(q);
		float m = 1.0;
		for (int j = -1; j <= 1; j++) {
			for (int i = -1; i <= 1; i++) {
				vec2 o = vec2(float(i), float(j));
				vec2 c = o + vec2(hash(id + o), hash(id + o + 9.1)) - f;
				m = min(m, dot(c, c));
			}
		}
		float crust = smoothstep(0.12, 0.3, m) * (0.35 + 0.65 * depth);
		col = mix(col, vec3(0.06, 0.04, 0.04), crust * 0.8);
		COLOR = vec4(col, 1.0);
	}
}
