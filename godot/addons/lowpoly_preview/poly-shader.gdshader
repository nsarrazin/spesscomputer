shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_always;

// ---------- inputs ----------
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;
uniform sampler2D depth_texture  : hint_depth_texture,  repeat_disable, filter_nearest;

uniform float edge_thickness    = 1.0;   // pixels
uniform float edge_depth_thresh = 0.002;
uniform vec3  edge_color        = vec3(0.05);

uniform float shade_levels   = 3.0;
uniform float shade_strength = 0.35;

// ---------- helpers ----------
float depth_at(vec2 uv) {
    return texture(depth_texture, uv).r;                     // non-linear depth
}

float edge_factor(vec2 uv) {
    vec2 pixel   = vec2(1.0) / VIEWPORT_SIZE;                // ← moved here
    float center = depth_at(uv);
    float sum    = 0.0;

    for (int x = -1; x <= 1; x++) {
        for (int y = -1; y <= 1; y++) {
            vec2 off = vec2(float(x), float(y)) * pixel * edge_thickness;
            sum += step(edge_depth_thresh, abs(depth_at(uv + off) - center));
        }
    }
    return clamp(sum / 9.0, 0.0, 1.0);
}

vec3 toon_shade(vec3 col) {
    float lum   = dot(col, vec3(0.299, 0.587, 0.114));
    float band  = floor(lum * shade_levels) / (shade_levels - 1.0);
    float dark  = mix(0.0, shade_strength, 1.0 - band);
    return col * (1.0 - dark);
}

void fragment() {
    vec3 col = texture(screen_texture, SCREEN_UV).rgb;
    col = toon_shade(col);
    col = mix(col, edge_color, edge_factor(SCREEN_UV));
    ALBEDO = col;   // unshaded → final colour
}
