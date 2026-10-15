shader_type canvas_item;

// Lava body drawn on one ColorRect that follows the camera horizontally.
// `surface` is the distance from the rect's top to the mean lava surface.

uniform vec2 rect_size = vec2(2000.0, 2000.0);
uniform float surface = 60.0;
uniform float world_x = 0.0;
uniform vec4 hot : source_color = vec4(1.0, 0.78, 0.25, 1.0);
uniform vec4 mid : source_color = vec4(1.0, 0.38, 0.12, 1.0);
uniform vec4 deep : source_color = vec4(0.45, 0.06, 0.12, 1.0);

void fragment() {
	vec2 p = UV * rect_size;
	float x = p.x + world_x;
	float wave = sin(x * 0.018 + TIME * 2.1) * 6.0 + sin(x * 0.043 - TIME * 1.4) * 3.5 + sin(x * 0.007 + TIME * 0.6) * 5.0;
	float sy = surface + wave;
	float d = p.y - sy;            // > 0 inside the lava
	if (d < 0.0) {
		// glow above the surface
		float g = exp(d / 18.0);
		COLOR = vec4(mid.rgb, g * 0.45);
	} else {
		float depth = clamp(d / 260.0, 0.0, 1.0);
		vec3 col = mix(mid.rgb, deep.rgb, depth);
		// slow churning blobs
		float blob = sin(x * 0.011 + p.y * 0.02 + TIME * 0.8) * sin(x * 0.007 - p.y * 0.013 - TIME * 0.5);
		col = mix(col, hot.rgb, smoothstep(0.55, 0.95, blob) * (1.0 - depth) * 0.6);
		// bright crust line
		col = mix(hot.rgb, col, smoothstep(0.0, 7.0, d));
		COLOR = vec4(col, 1.0);
	}
}
