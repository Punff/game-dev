shader_type canvas_item;

uniform float time;

void fragment() {
    vec2 uv = UV * 3.0;
    float plasma = sin(uv.x + time) + sin((uv.y + time) * 0.5) + sin((uv.x + uv.y + time) * 0.5);
    plasma += sin(sqrt(uv.x * uv.x + uv.y * uv.y + 1.0) + time);
    
    float intensity = (sin(plasma + time) * 0.5 + 0.5);
    
    vec3 col1 = vec3(0.02, 0.02, 0.04);
    vec3 col2 = vec3(0.08, 0.05, 0.12);
    vec3 col3 = vec3(0.05, 0.12, 0.15);
    vec3 col4 = vec3(0.15, 0.08, 0.05);
    
    vec3 col;
    if (intensity < 0.25) {
        col = mix(col1, col2, intensity * 4.0);
    } else if (intensity < 0.5) {
        col = mix(col2, col3, (intensity - 0.25) * 4.0);
    } else if (intensity < 0.75) {
        col = mix(col3, col4, (intensity - 0.5) * 4.0);
    } else {
        col = mix(col4, col1, (intensity - 0.75) * 4.0);
    }
    
    COLOR = vec4(col, 1.0);
}