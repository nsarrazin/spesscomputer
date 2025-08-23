shader_type spatial;
render_mode cull_back, depth_draw_opaque;

uniform float planet_radius : hint_range(0.0, 1e9) = 200000.0;
uniform float detail_scale : hint_range(0.1, 128.0) = 24.0;
uniform float detail_strength : hint_range(0.0, 2.0) = 0.15;
uniform float slope_darkening_strength : hint_range(0.0, 1.0) = 0.20;

// Ambient occlusion controls
uniform float ao_strength : hint_range(0.0, 1.0) = 0.3;
uniform float ao_radius : hint_range(0.1, 2.0) = 0.8;

// Sky glow/ambient lighting
uniform float sky_ambient_strength : hint_range(0.0, 1.0) = 0.15;
uniform vec3 sky_color : source_color = vec3(0.4, 0.6, 1.0);
uniform float horizon_boost : hint_range(0.0, 2.0) = 0.5;

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

// Simplified noise functions
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(a, b, u.x) + (c - a) * u.y * (1.0 - u.x) + (d - b) * u.x * u.y;
}

float fbm2(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	float f = 1.0;
	for (int i = 0; i < 3; i++) { // Reduced iterations for performance
		v += a * noise2(p * f);
		f *= 2.0;
		a *= 0.5;
	}
	return v;
}

// Triplanar sampling for surface detail
vec3 triplanar_weights(vec3 n) {
	vec3 an = abs(n);
	an = max(an, vec3(1e-5));
	return an / (an.x + an.y + an.z);
}

float sample_triplanar(vec3 p, vec3 n, float scale) {
	vec3 w = triplanar_weights(n);
	float tx = fbm2(p.yz * scale);
	float ty = fbm2(p.zx * scale);
	float tz = fbm2(p.xy * scale);
	return tx * w.x + ty * w.y + tz * w.z;
}

// Simple ambient occlusion using surface curvature
float calculate_ao(vec3 pos, vec3 normal, float radius) {
	float eps = radius * 0.01;
	float center_height = sample_triplanar(pos / max(planet_radius, 1e-3), normal, detail_scale);
	
	// Sample surrounding points
	float ao = 0.0;
	int samples = 8;
	for (int i = 0; i < samples; i++) {
		float angle = float(i) * 2.0 * PI / float(samples);
		vec3 offset = (cos(angle) * normal.zxy + sin(angle) * normal.yzx) * eps;
		vec3 sample_pos = pos + offset;
		float sample_height = sample_triplanar(sample_pos / max(planet_radius, 1e-3), normal, detail_scale);
		
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
	vec3 p = v_pos / max(planet_radius, 1e-3);
	vec3 n = normalize(v_normal);
	vec3 radial = normalize(v_pos);
	vec3 world_normal = normalize(v_world_normal);
	
	// Surface detail from triplanar noise
	float detail = sample_triplanar(p, n, detail_scale);
	detail = (detail - 0.5) * 2.0; // Remap to [-1, 1]
	
	// Base surface color from vertex color
	vec3 base_color = COLOR.rgb;
	
	// Apply surface detail modulation
	float detail_mod = 1.0 + detail * detail_strength * 0.5;
	base_color *= detail_mod;
	
	// Slope-based darkening (steeper slopes are darker)
	float slope = 1.0 - clamp(dot(n, radial), 0.0, 1.0);
	base_color = mix(base_color, base_color * 0.7, slope_darkening_strength * slope);
	
	// Calculate ambient occlusion
	float ao = calculate_ao(v_pos, n, ao_radius);
	
	// Sky ambient lighting calculation
	vec3 up_world = normalize(v_world_pos); // Direction from planet center
	float sky_visibility = clamp(dot(world_normal, up_world), 0.0, 1.0);
	
	// Add horizon boost for more realistic sky lighting
	float horizon_factor = 1.0 - abs(dot(world_normal, up_world));
	sky_visibility += horizon_factor * horizon_boost;
	sky_visibility = clamp(sky_visibility, 0.0, 1.0);
	
	vec3 sky_ambient = sky_color * sky_ambient_strength * sky_visibility;
	
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