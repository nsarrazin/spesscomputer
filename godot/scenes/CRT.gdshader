shader_type canvas_item;
render_mode unshaded;

// Use the current screen as input (Godot 4 style)
uniform sampler2D screen_tex : hint_screen_texture/*, filter_nearest*/;

// -------------------- Parameters (mirroring your originals) --------------------
uniform float CRTgamma         : hint_range(0.1, 5.0) = 2.4;
uniform float monitorgamma     : hint_range(0.1, 5.0) = 2.2;
uniform float d                : hint_range(0.1, 3.0) = 3.0;
uniform float CURVATURE        : hint_range(0.0, 1.0) = 1.0;
uniform float R                : hint_range(0.1, 10.0) = 0.1;
uniform float cornersize       : hint_range(0.001, 1.0) = 0.03;
uniform float cornersmooth     : hint_range(80.0, 2000.0) = 1000.0;
uniform float x_tilt           : hint_range(-0.5, 0.5) = 0.0;
uniform float y_tilt           : hint_range(-0.5, 0.5) = 0.0;
uniform float overscan_x       : hint_range(-125.0, 125.0) = 110.0; // percent
uniform float overscan_y       : hint_range(-125.0, 125.0) = 110.0; // percent
uniform float DOTMASK          : hint_range(0.0, 0.3) = 0.3;
uniform float SHARPER          : hint_range(1.0, 3.0)   = 1.0;
uniform float scanline_weight  : hint_range(0.05, 1.0)  = 0.5;
uniform float lum              : hint_range(0.0, 1.0)   = 0.2;

// 480i specific parameters
uniform bool enable_480i       = true;   // Enable 480i interlaced mode
uniform float interlace_offset : hint_range(0.0, 1.0) = 0.5; // Offset for interlace timing
uniform bool clamp_resolution  = true;   // Clamp to 640x480 regardless of window size
uniform float target_width     : hint_range(320.0, 1920.0) = 640.0;  // Target horizontal resolution
uniform float target_height    : hint_range(240.0, 1080.0) = 480.0;  // Target vertical resolution

// Optional stylistic Y scale for beam geometry (set 0.75 for "classic" look)
uniform float aspect_y_scale   : hint_range(0.25, 2.0)  = 1.0;

// Behavior toggles analogous to #defines
uniform bool LINEAR_PROCESSING = true;  // work in "linearized" domain then apply monitor gamma
uniform bool OVERSAMPLE        = true;  // vertical oversample for scanline moiré reduction

// Lightweight bloom (bright-pass + small blur on screen texture)
uniform float bloom_intensity  : hint_range(0.0, 1.0) = 0.25;
uniform float bloom_threshold  : hint_range(0.0, 2.0) = 1.0;  // >1 = only very bright
uniform float bloom_radius_px  : hint_range(0.0, 8.0) = 2.0;
uniform vec4 corner_bg_color : source_color = vec4(0.0745098, 0.0745098, 0.09411765, 1.0);

float FIXF(float c) { return max(abs(c), 1e-5); }
vec4  FIX4(vec4 c)  { return max(abs(c), vec4(1e-5)); }

// 480i uses 59.94 Hz field rate (29.97 fps x 2 fields)
float frame_mod2() { 
    if (enable_480i) {
        return floor(mod(TIME * 59.94 + interlace_offset, 2.0));
    } else {
        return floor(mod(TIME * 60.0, 2.0));
    }
}

vec4 TEX2D(vec2 uv) {
    vec4 s = texture(screen_tex, uv);
    return LINEAR_PROCESSING ? pow(s, vec4(CRTgamma)) : s;
}

/*** Curvature math ***/
float intersect(vec2 xy, vec4 sca, float d_, float R_) {
    float A = dot(xy, xy) + d_*d_;
    float B = 2.0 * (R_ * (dot(xy, sca.xy) - d_ * sca.z * sca.w) - d_*d_);
    float C = d_*d_ + 2.0 * R_ * d_ * sca.z * sca.w;
    return (-B - sqrt(B*B - 4.0*A*C)) / (2.0*A);
}

vec2 bkwtrans_as(vec2 xy, vec4 sca, vec2 aspect, float d_, float R_) {
    float c = intersect(xy, sca, d_, R_);
    vec2 point_ = vec2(c) * xy;
    point_ -= vec2(-R_) * sca.xy;
    point_ /= vec2(R_);
    vec2 tang = sca.xy / sca.zw;
    vec2 poc = point_ / sca.zw;
    float A = dot(tang, tang) + 1.0;
    float B = -2.0 * dot(poc, tang);
    float C = dot(poc, poc) - 1.0;
    float a = (-B + sqrt(B*B - 4.0*A*C)) / (2.0*A);
    vec2 uv = (point_ - a * sca.xy) / sca.zw;
    float r = FIXF(R_ * acos(a));
    return uv * r / sin(r / R_);
}

vec2 fwtrans_as(vec2 uv, vec4 sca, vec2 aspect, float d_, float R_) {
    float r = FIXF(length(uv));
    uv *= sin(r / R_) / r;
    float x = 1.0 - cos(r / R_);
    float D = d_ / R_ + x * sca.z * sca.w + dot(uv, sca.xy);
    return d_ * (uv * sca.zw - x * sca.xy) / D;
}

vec3 maxscale_as(vec4 sca, vec2 aspect, float d_, float R_) {
    vec2 c = bkwtrans_as(-R_ * sca.xy / (1.0 + R_/d_ * sca.z * sca.w), sca, aspect, d_, R_);
    vec2 a = 0.5 * aspect;
    vec2 lo = vec2(
        fwtrans_as(vec2(-a.x, c.y), sca, aspect, d_, R_).x,
        fwtrans_as(vec2(c.x, -a.y), sca, aspect, d_, R_).y
    ) / aspect;
    vec2 hi = vec2(
        fwtrans_as(vec2(+a.x, c.y), sca, aspect, d_, R_).x,
        fwtrans_as(vec2(c.x, +a.y), sca, aspect, d_, R_).y
    ) / aspect;
    return vec3((hi + lo) * aspect * 0.5, max(hi.x - lo.x, hi.y - lo.y));
}

/*** Beam profile ***/
vec4 scanlineWeights(float distance_, vec4 color_, float scan_w, float lum_) {
    vec4 wid = 2.0 + 2.0 * pow(color_, vec4(4.0));
    float v = distance_ / scan_w;
    vec4 weights = vec4(v);
    vec4 arg = pow(weights * inversesqrt(0.5 * wid), wid);
    return (lum_ + 1.4) * exp(-arg) / (0.6 + 0.2 * wid);
}

/*** Lightweight bloom ***/
vec3 bloom_sample(vec2 uv, vec2 px, float threshold) {
    vec3 c = pow(texture(screen_tex, uv).rgb, vec3(1.0));
    float b = max(max(c.r, c.g), c.b) - threshold;
    b = max(b, 0.0);
    return c * b;
}

vec3 bloom_apply(vec2 uv, vec2 screen_px, float intensity, float radius_px, float threshold) {
    if (intensity <= 0.0 || radius_px <= 0.0) return vec3(0.0);
    vec2 r = screen_px * radius_px;

    vec3 acc = bloom_sample(uv, screen_px, threshold) * 0.25;
    acc += bloom_sample(uv + vec2( r.x,  0.0), screen_px, threshold) * 0.125;
    acc += bloom_sample(uv + vec2(-r.x,  0.0), screen_px, threshold) * 0.125;
    acc += bloom_sample(uv + vec2( 0.0,  r.y), screen_px, threshold) * 0.125;
    acc += bloom_sample(uv + vec2( 0.0, -r.y), screen_px, threshold) * 0.125;

    float s = 0.088;
    acc += bloom_sample(uv + vec2( r.x,  r.y), screen_px, threshold) * s;
    acc += bloom_sample(uv + vec2(-r.x,  r.y), screen_px, threshold) * s;
    acc += bloom_sample(uv + vec2( r.x, -r.y), screen_px, threshold) * s;
    acc += bloom_sample(uv + vec2(-r.x, -r.y), screen_px, threshold) * s;

    return acc * intensity;
}

// -------------------- Main --------------------
void fragment() {
    // Live framebuffer sizes
    vec2 texture_size = vec2(textureSize(screen_tex, 0));
    
    // For 480i clamping: render as if we have low resolution but fill the full canvas
    vec2 video_size = clamp_resolution ? vec2(target_width, target_height) : texture_size;
    vec2 screen_px = 1.0 / texture_size;  // Keep original for bloom calculations
    vec2 output_size = texture_size;

    // Aspect for curvature domain
    vec2 aspect = vec2(output_size.x / output_size.y, 1.0);
    aspect.y *= aspect_y_scale;

    // Tilt/stretch setup
    vec2 sinangle = sin(vec2(x_tilt, y_tilt));
    vec2 cosangle = cos(vec2(x_tilt, y_tilt));
    vec4 sin_cos_angle = vec4(sinangle.x, sinangle.y, cosangle.x, cosangle.y);
    vec3 stretch = maxscale_as(sin_cos_angle, aspect, d, R);

    // 480i interlacing - force 2.0 for proper interlaced mode
    float il_y = enable_480i ? 2.0 : clamp(floor(video_size.y / 200.0), 1.0, 2.0);
    vec2 ilfac = vec2(1.0, il_y);

    // "texel size" in the sampling lattice - use video_size for clamped resolution
    vec2 TextureSize = vec2(SHARPER * video_size.x, video_size.y);
    vec2 one = ilfac / TextureSize;

    // For dotmask parity - adjust for clamped resolution
    float mod_factor = SCREEN_UV.x * video_size.x;

    // ---- Curvature mapping (to get sample UV 'xy') ----
    vec2 texCoord = SCREEN_UV;
    vec2 xy;
    if (CURVATURE > 0.5) {
        vec2 cd = texCoord;
        cd = (cd - vec2(0.5)) * aspect * stretch.z + stretch.xy;
        xy = (bkwtrans_as(cd, sin_cos_angle, aspect, d, R) /
              (vec2(overscan_x, overscan_y) / 100.0) / aspect + vec2(0.5));
    } else {
        xy = texCoord;
    }

    // ---- Corner mask ----
    vec2 cd2 = xy;
    cd2 = (cd2 - vec2(0.5)) * vec2(overscan_x, overscan_y) / 100.0 + vec2(0.5);
    cd2 = min(cd2, vec2(1.0) - cd2) * aspect;
    vec2 cdist = vec2(cornersize);
    cd2 = (cdist - min(cd2, cdist));
    float dist_c = sqrt(dot(cd2, cd2));
    float cval = clamp((cdist.x - dist_c) * cornersmooth, 0.0, 1.0);

    // ---- Build sampling lattice in curved UV ----
    float ilfloat = (ilfac.y > 1.5) ? mod(frame_mod2(), 2.0) : 0.0;

    // For clamped resolution: pixelate by sampling at lower resolution
    vec2 sample_uv = xy;
    if (clamp_resolution) {
        // Convert to pixel coordinates, floor to create pixelation, then back to UV
        vec2 pixel_coords = sample_uv * video_size;
        pixel_coords = floor(pixel_coords) + vec2(0.5);
        sample_uv = pixel_coords / video_size;
    }

    vec2 ratio_scale_tex = (sample_uv * TextureSize - vec2(0.5) + vec2(0.0, ilfloat)) / ilfac;
    vec2 uv_ratio_tex = fract(ratio_scale_tex);
    vec2 base_xy = (floor(ratio_scale_tex) * ilfac + vec2(0.5) - vec2(0.0, ilfloat)) / TextureSize;

    // Lanczos2 horizontal coefficients (same)
    const float PI_ = 3.14159265358979323846;
    vec4 coeffs = PI_ * vec4(1.0 + uv_ratio_tex.x, uv_ratio_tex.x, 1.0 - uv_ratio_tex.x, 2.0 - uv_ratio_tex.x);
    coeffs = FIX4(coeffs);
    coeffs = 2.0 * sin(coeffs) * sin(coeffs * 0.5) / (coeffs * coeffs);
    coeffs /= dot(coeffs, vec4(1.0));

    // Sample current and next scanline (still in curved UV)
    vec4 col = clamp(
        coeffs.x * TEX2D(base_xy + vec2(-one.x, 0.0)) +
        coeffs.y * TEX2D(base_xy + vec2( 0.0 , 0.0)) +
        coeffs.z * TEX2D(base_xy + vec2( one.x, 0.0)) +
        coeffs.w * TEX2D(base_xy + vec2( 2.0*one.x, 0.0)),
        0.0, 1.0);

    vec2 next_y = base_xy + vec2(0.0, one.y);
    vec4 col2 = clamp(
        coeffs.x * TEX2D(next_y + vec2(-one.x, 0.0)) +
        coeffs.y * TEX2D(next_y + vec2( 0.0 , 0.0)) +
        coeffs.z * TEX2D(next_y + vec2( one.x, 0.0)) +
        coeffs.w * TEX2D(next_y + vec2( 2.0*one.x, 0.0)),
        0.0, 1.0);

    if (!LINEAR_PROCESSING) {
        col  = pow(col , vec4(CRTgamma));
        col2 = pow(col2, vec4(CRTgamma));
    }

    // ---- NEW: use SCREEN-SPACE phase for vertical beam weights ----
    // This makes scanlines uniform and not "elliptical" under curvature.
    float y_screen_tex = (SCREEN_UV.y * TextureSize.y - 0.5 + ilfloat) / ilfac.y;
    float uv_ratio_scr = fract(y_screen_tex);

    vec4 w1 = scanlineWeights(uv_ratio_scr,           col,  scanline_weight, lum);
    vec4 w2 = scanlineWeights(1.0 - uv_ratio_scr,     col2, scanline_weight, lum);

    if (OVERSAMPLE) {
        // In screen space, output/video match here; keep a small spread constant.
        float filter = 1.0;
        float v = uv_ratio_scr + (1.0/3.0) * filter;
        w1 = (w1 + scanlineWeights(v,                 col,  scanline_weight, lum)) / 3.0;
        w2 = (w2 + scanlineWeights(abs(1.0 - v),      col2, scanline_weight, lum)) / 3.0;

        v = uv_ratio_scr - (2.0/3.0) * filter;
        w1 +=      scanlineWeights(abs(v),            col,  scanline_weight, lum)  / 3.0;
        w2 +=      scanlineWeights(abs(1.0 - v),      col2, scanline_weight, lum)  / 3.0;
    }

    vec3 content_rgb = (col * w1 + col2 * w2).rgb;

    // Dot-mask (content only)
    vec3 dotMaskWeights = mix(
        vec3(1.0, 1.0 - DOTMASK, 1.0),
        vec3(1.0 - DOTMASK, 1.0, 1.0 - DOTMASK),
        floor(mod(mod_factor, 2.0))
    );
    content_rgb *= dotMaskWeights;

    // Bloom (content only)
    if (bloom_intensity > 0.0) {
        vec3 glow = bloom_apply(clamp_resolution ? sample_uv : xy, screen_px, bloom_intensity, bloom_radius_px, bloom_threshold);
        content_rgb = clamp(content_rgb + glow * cval, 0.0, 10.0);
    }

    // Blend content with corner background (already linear due to source_color)
    vec3 rgb = mix(corner_bg_color.rgb, content_rgb, cval);

    // Output in linear space; Godot handles display gamma conversion
    COLOR = vec4(rgb, 1.0);
}
