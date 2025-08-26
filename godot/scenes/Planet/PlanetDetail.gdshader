shader_type spatial;
render_mode cull_back, depth_draw_opaque;

uniform float planet_radius : hint_range(0.0, 1e9) = 200000.0;
uniform float detail_scale : hint_range(0.1, 128.0) = 24.0;
uniform float detail_strength : hint_range(0.0, 2.0) = 0.15;
uniform float slope_darkening_strength : hint_range(0.0, 1.0) = 0.20;

// Blending controls
uniform float color_brightness : hint_range(1.0, 4.0) = 1.8;
uniform float lod_fade_start : hint_range(1.0, 1e9) = 400000.0;
uniform float lod_fade_end : hint_range(1.0, 1e9) = 800000.0;
uniform float far_scale_multiplier : hint_range(0.0, 1.0) = 0.05;

// Toon shading
uniform float posterize_levels : hint_range(2.0, 16.0) = 5.0;
uniform float texture_influence : hint_range(0.0, 1.0) = 0.15;

// Ambient occlusion controls
uniform float ao_strength : hint_range(0.0, 1.0) = 0.3;
uniform float ao_radius : hint_range(0.1, 2.0) = 0.8;

// Sky glow/ambient lighting
uniform float sky_ambient_strength : hint_range(0.0, 1.0) = 0.15;
uniform vec3 sky_color : source_color = vec3(0.4, 0.6, 1.0);
uniform float horizon_boost : hint_range(0.0, 2.0) = 0.5;

// Ground texture
uniform sampler2D ground_texture : source_color, filter_linear_mipmap, repeat_enable;

// Atmosphere rim controls (simplified)
uniform float atmo_height : hint_range(0.0, 1e8) = 6000.0;
uniform float atmo_intensity : hint_range(0.0, 1.0) = 0.2;
uniform vec3 atmo_color : source_color = vec3(0.55, 0.75, 1.0);
uniform vec3 atmo_sun_dir_object = vec3(0.0, -1.0, 0.0);
uniform vec3 atmo_camera_pos_object = vec3(0.0);

varying vec3 v_pos;
varying vec3 v_normal;
varying vec3 v_world_pos;
varying vec3 v_world_normal;

// Triplanar sampling for surface detail
vec3 triplanar_weights(vec3 n) {
	vec3 an = abs(n);
	an = max(an, vec3(1e-5));
	return an / (an.x + an.y + an.z);
}

vec3 sample_triplanar_color(vec3 p, vec3 n, float scale) {
	vec3 w = triplanar_weights(n);
	vec3 tx = texture(ground_texture, p.yz * scale).rgb;
	vec3 ty = texture(ground_texture, p.zx * scale).rgb;
	vec3 tz = texture(ground_texture, p.xy * scale).rgb;
	return tx * w.x + ty * w.y + tz * w.z;
}

// Simple ambient occlusion using surface curvature (now in stable coordinate space)
float calculate_ao(vec3 pos, vec3 normal, float radius) {
	// Use normalized position for stable sampling coordinates
	vec3 normalized_pos = normalize(pos);
	float eps = radius * 0.01;

	// Sample height using stable coordinates
	float center_height = dot(sample_triplanar_color(normalized_pos, normal, detail_scale), vec3(0.299, 0.587, 0.114));

	// Sample surrounding points in tangent space
	float ao = 0.0;
	int samples = 6; // Reduced for performance
	for (int i = 0; i < samples; i++) {
		float angle = float(i) * 2.0 * PI / float(samples);

		// Create tangent vectors
		vec3 tangent = normalize(cross(normal, vec3(0.0, 1.0, 0.0)));
		if (length(tangent) < 0.1) {
			tangent = normalize(cross(normal, vec3(1.0, 0.0, 0.0)));
		}
		vec3 bitangent = normalize(cross(normal, tangent));

		// Sample offset in tangent space
		vec3 offset = (cos(angle) * tangent + sin(angle) * bitangent) * eps;
		vec3 sample_pos = normalize(normalized_pos + offset * 0.01);

		float sample_height = dot(sample_triplanar_color(sample_pos, normal, detail_scale), vec3(0.299, 0.587, 0.114));

		// If surrounding point is higher, it contributes to occlusion
		ao += max(0.0, sample_height - center_height);
	}

	return 1.0 - clamp(ao / float(samples) * ao_strength, 0.0, 1.0);
}

void vertex() {
	v_pos = VERTEX;
	v_normal = NORMAL;
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	// Surface coordinates and normals
	vec3 p = normalize(v_pos); // Use normalized position for stable sampling
	vec3 n = normalize(v_normal);
	vec3 radial = normalize(v_pos);
	vec3 world_normal = normalize(v_world_normal);

	// LOD blending based on distance
	float dist = distance(v_pos, atmo_camera_pos_object);
	float lod_mix = smoothstep(lod_fade_start, lod_fade_end, dist);

	// Sample detail at two scales and blend
	vec3 color_near = sample_triplanar_color(p, n, detail_scale);
	vec3 color_far = sample_triplanar_color(p, n, detail_scale * far_scale_multiplier);
	vec3 texture_color = mix(color_near, color_far, lod_mix);

	float detail = dot(texture_color, vec3(0.299, 0.587, 0.114));
	detail = (detail - 0.5) * 2.0; // Remap to [-1, 1]

	// Base surface color from vertex color
	float texture_lum = dot(texture_color, vec3(0.299, 0.587, 0.114));
	vec3 base_color = COLOR.rgb;

	// Texture influence increases as camera gets closer
	float distance_influence = clamp(1.0 - (dist / lod_fade_start), 0.0, 1.0);
	float dynamic_texture_influence = texture_influence * distance_influence;

	base_color = mix(base_color, base_color * texture_lum, dynamic_texture_influence);
	base_color *= color_brightness;

	// Apply surface detail modulation
	float detail_mod = 1.0 + detail * detail_strength * 0.5;
	base_color *= detail_mod;

	// Slope-based darkening (steeper slopes are darker)
	float slope = 1.0 - clamp(dot(n, radial), 0.0, 1.0);
	base_color = mix(base_color, base_color * 0.7, slope_darkening_strength * slope);

	// Toon shading via posterization
	base_color = floor(base_color * posterize_levels) / posterize_levels;

	// Calculate ambient occlusion
	float ao = calculate_ao(v_pos, n, ao_radius);

	// Sky ambient lighting calculation
	vec3 up_world = normalize(v_world_pos); // Direction from planet center
	float sky_visibility = clamp(dot(world_normal, up_world), 0.0, 1.0);

	// Add horizon boost for more realistic sky lighting
	float horizon_factor = 1.0 - abs(dot(world_normal, up_world));
	sky_visibility += horizon_factor * horizon_boost;
	sky_visibility = clamp(sky_visibility, 0.0, 1.0);

	// Reduce sky ambient contribution, especially on ice (which has high blue in vertex COLOR)
	float ice_mask = smoothstep(0.7, 0.8, COLOR.b);
	vec3 sky_ambient = sky_color * sky_ambient_strength * sky_visibility * (1.0 - ice_mask * 0.9);

	// Simple atmosphere rim effect
	vec3 cam_pos = atmo_camera_pos_object;
	vec3 view_dir = normalize(cam_pos - v_pos);
	float height = max(length(v_pos) - planet_radius, 0.0);
	float H = max(atmo_height, 1.0);
	float density = exp(-height / (0.8 * H));
	float rim = 1.0 - clamp(dot(radial, view_dir), 0.0, 1.0);
	rim = pow(rim, 2.0);
	vec3 atmo_emission = atmo_color * atmo_intensity * density * rim;

	// Final surface properties
	ALBEDO = clamp(base_color * ao, vec3(0.05), vec3(0.95));
	SPECULAR = 0.02;
	ROUGHNESS = clamp(0.9 + 0.1 * (1.0 - slope), 0.0, 1.0);
	EMISSION = atmo_emission + sky_ambient;
}