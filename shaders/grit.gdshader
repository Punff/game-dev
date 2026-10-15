shader_type canvas_item;

// Full-screen "old cel / worn print" overlay drawn on top of everything.
// No screen read: it just lays dark grain, dust, the odd hair and a
// vignette over the frame with alpha, so it costs almost nothing.
// Animated at a choppy ~12 fps, like film being hand-cranked.

uniform float strength = 1.0;

// "Hash without sine" (Dave Hoskins) - no visible patterns on WebGL.
float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	vec2 px = FRAGCOORD.xy;
	float frame = mod(floor(TIME * 12.0), 97.0);
	float n = hash(floor(px / 2.0) + frame * 17.0);

	// Dark grain
	float a = (n - 0.5) * 0.16 * strength;
	vec3 col = vec3(0.05, 0.04, 0.035);
	// Dust specks (light) and grime blotches (dark)
	vec2 cell = floor(px / 3.0);
	float d = hash(cell + frame * 3.1);
	if (d > 0.99975) {
		col = vec3(0.92, 0.88, 0.78);
		a = 0.55 * strength;
	} else if (d < 0.0004) {
		a = 0.6 * strength;
	}
	// A hair / scratch now and then
	float hx = hash(vec2(frame, 7.0));
	if (hx > 0.86 && abs(px.x - hx * 2000.0 + 300.0) < 1.0) {
		a = max(a, 0.35 * strength);
	}
	// Uneven vignette and a slight flicker
	vec2 v = UV - 0.5;
	float vig = smoothstep(0.25, 0.85, length(v * vec2(1.1, 1.3)));
	a = max(a, 0.0) + vig * 0.55 + (hash(vec2(frame)) - 0.5) * 0.03 * strength;
	COLOR = vec4(col, clamp(a, 0.0, 0.85));
}
