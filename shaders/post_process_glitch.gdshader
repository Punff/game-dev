shader_type canvas_item;

uniform float aberration_amount : hint_range(0.0, 10.0) = 1.0;
uniform float scanline_count = 50.0;
uniform float glitch_intensity : hint_range(0.0, 1.0) = 0.0;
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453123);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	
	// Random Glitch Displacement
	if (glitch_intensity > 0.0) {
		float g = step(1.0 - glitch_intensity * 0.1, hash(vec2(TIME * 10.0, floor(uv.y * 20.0))));
		uv.x += g * 0.02 * (hash(vec2(TIME)) - 0.5);
	}
	
	// Chromatic Aberration
	float r = texture(screen_texture, uv + vec2(SCREEN_PIXEL_SIZE.x * aberration_amount, 0.0)).r;
	float g = texture(screen_texture, uv).g;
	float b = texture(screen_texture, uv - vec2(SCREEN_PIXEL_SIZE.x * aberration_amount, 0.0)).b;
	
	vec4 col = vec4(r, g, b, 1.0);
	
	// Subtle Scanlines for comic look
	float s = sin(uv.y * scanline_count * PI * 2.0);
	col.rgb = mix(col.rgb, col.rgb * 0.9, clamp(s * 0.5 + 0.5, 0.0, 1.0) * 0.2);
	
	COLOR = col;
}
