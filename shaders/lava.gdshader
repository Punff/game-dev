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
		// soft heat glow above the surface
		COLOR = vec4(mid.rgb, exp(d / 22.0) * 0.4);
	} else if (d < 6.0) {
		COLOR = vec4(0.05, 0.04, 0.04, 1.0);   // ink outline
	} else {
		float depth = clamp(d / 300.0, 0.0, 1.0);
		vec3 col = mix(hot.rgb, mid.rgb, smoothstep(0.0, 40.0, d));
		col = mix(col, deep.rgb, depth);
		// Cooling crust plates with glowing cracks between them (F2 - F1 cell noise).
		vec2 q = vec2(x + TIME * 14.0, p.y * 1.4) / 80.0;
		vec2 id = floor(q);
		vec2 f = fract(q);
		float f1 = 8.0;
		float f2 = 8.0;
		for (int j = -1; j <= 1; j++) {
			for (int i = -1; i <= 1; i++) {
				vec2 o = vec2(float(i), float(j));
				vec2 c = o + vec2(hash(id + o), hash(id + o + 9.1)) - f;
				float dd = dot(c, c);
				if (dd < f1) { f2 = f1; f1 = dd; } else if (dd < f2) { f2 = dd; }
			}
		}
		float edge = sqrt(f2) - sqrt(f1);
		float crust = smoothstep(0.05, 0.16, edge) * smoothstep(10.0, 60.0, d);
		vec3 crust_col = mix(vec3(0.16, 0.07, 0.06), vec3(0.07, 0.04, 0.04), depth);
		col = mix(col, crust_col, crust * 0.92);
		COLOR = vec4(col, 1.0);
	}
}
