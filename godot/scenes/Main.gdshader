shader_type spatial;
render_mode unshaded,
            cull_disabled,
            depth_test_disabled,   // ← fixed spelling
            depth_draw_never,
            skip_vertex_transform;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;
uniform sampler2D depth_texture  : hint_depth_texture,  repeat_disable, filter_nearest;

uniform float edge_thickness    = 1.0;     // pixels
uniform float edge_depth_thresh = 0.002;   // clip-space diff
uniform vec3  edge_color        = vec3(0.05);

uniform int   shade_levels      = 3;       // 1-8
uniform float shade_strength    = 0.35;    // 0-1

/* vertex: keep quad verts in clip-space */
void vertex() {
    POSITION = vec4(VERTEX.xy, 0.0, 1.0);
}

/* helpers */
float depth_at(vec2 uv) {
    return texture(depth_texture, uv).r;
}

float edge_factor(vec2 uv) {
    float c = depth_at(uv);
    float hits = 0.0;
    for (int x = -1; x <= 1; ++x)
        for (int y = -1; y <= 1; ++y) {
            vec2 o = vec2(float(x), float(y)) * edge_thickness;
            hits += step(edge_depth_thresh, abs(depth_at(uv + o) - c));
        }
    return clamp(hits / 9.0, 0.0, 1.0);
}

vec3 toonify(vec3 col) {
    float l = dot(col, vec3(0.299, 0.587, 0.114));
    float band = floor(l * float(shade_levels)) / max(float(shade_levels - 1), 1.0);
    float darken = mix(0.0, shade_strength, 1.0 - band);
    return col * (1.0 - darken);
}

/* fragment */
void fragment() {
    vec3 col = texture(screen_texture, SCREEN_UV).rgb;
    col = toonify(col);
    col = mix(col, edge_color, edge_factor(SCREEN_UV));
    ALBEDO = col;
    ALPHA = 1.0;
}
