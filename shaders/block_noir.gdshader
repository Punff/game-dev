shader_type canvas_item;

uniform float outline_width : hint_range(0.0, 10.0) = 2.0;
uniform vec4 outline_color : source_color = vec4(0, 0, 0, 1);

// Shadow & Rim Light
uniform vec2 shadow_offset = vec2(4.0, 4.0);
uniform vec4 shadow_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform vec4 rim_color : source_color = vec4(1.0, 1.0, 1.0, 0.3);
uniform float rim_width : hint_range(0.0, 5.0) = 2.0;

void fragment() {
    vec2 size = TEXTURE_PIXEL_SIZE;
    vec4 tex_col = texture(TEXTURE, UV);
    vec4 col = tex_col * COLOR;
    
    // 1. Stable Outline sampling
    float outline_alpha = 0.0;
    outline_alpha = max(outline_alpha, texture(TEXTURE, UV + vec2(outline_width, 0.0) * size).a);
    outline_alpha = max(outline_alpha, texture(TEXTURE, UV + vec2(-outline_width, 0.0) * size).a);
    outline_alpha = max(outline_alpha, texture(TEXTURE, UV + vec2(0.0, outline_width) * size).a);
    outline_alpha = max(outline_alpha, texture(TEXTURE, UV + vec2(0.0, -outline_width) * size).a);
    
    // 2. Drop Shadow (Offset behind)
    float shadow_alpha = texture(TEXTURE, UV - shadow_offset * size).a;
    
    // 3. Rim Light (Highlight on top-left edge)
    float rim_alpha = 0.0;
    if (tex_col.a > 0.1) {
        float neighbor_a = texture(TEXTURE, UV - vec2(-rim_width, -rim_width) * size).a;
        rim_alpha = clamp(tex_col.a - neighbor_a, 0.0, 1.0);
    }

    if (tex_col.a > 0.1) {
        // Add rim highlight to the main block color
        col = mix(col, rim_color, rim_alpha * rim_color.a);
        COLOR = col;
    } else {
        // Outside the main texture: check for outline or shadow
        if (outline_alpha > 0.1) {
            COLOR = outline_color;
        } else if (shadow_alpha > 0.1) {
            COLOR = shadow_color;
        } else {
            discard;
        }
    }
}
