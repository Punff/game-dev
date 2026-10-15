shader_type canvas_item;

uniform float offset : hint_range(0.0, 10.0) = 1.0;
uniform bool enabled = true;

void fragment() {
    if (enabled) {
        float r = texture(TEXTURE, UV + vec2(SCREEN_PIXEL_SIZE.x * offset, 0.0)).r;
        float g = texture(TEXTURE, UV).g;
        float b = texture(TEXTURE, UV - vec2(SCREEN_PIXEL_SIZE.x * offset, 0.0)).b;
        COLOR = vec4(r, g, b, texture(TEXTURE, UV).a);
    } else {
        COLOR = texture(TEXTURE, UV);
    }
}
