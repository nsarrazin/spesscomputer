shader_type spatial;
render_mode cull_back, depth_draw_opaque;

uniform float planet_radius : hint_range(0.0, 1e9) = 200000.0;
uniform float detail_scale : hint_range(0.1, 128.0) = 24.0;
uniform float detail_strength : hint_range(0.0, 2.0) = 0.15;
uniform float normal_strength : hint_range(0.0, 2.0) = 0.0;
uniform float detail_fade_start : hint_range(0.0, 1e9) = 150000.0;
uniform float detail_fade_end   : hint_range(0.0, 1e9) = 600000.0;
uniform float slope_darkening_strength : hint_range(0.0, 1.0) = 0.20;
uniform float cavity_strength : hint_range(0.0, 1.0) = 0.12;

varying vec3 v_pos;
varying vec3 v_nrm;

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
	for (int i = 0; i < 5; i++) {
		v += a * noise2(p * f);
		f *= 2.0;
		a *= 0.5;
	}
	return v;
}

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

vec3 triplanar_gradient(vec3 p, vec3 n, float scale) {
	float eps = 0.01;
	float c = sample_triplanar(p, n, scale);
	float cx = sample_triplanar(p + vec3(eps, 0.0, 0.0), n, scale) - c;
	float cy = sample_triplanar(p + vec3(0.0, eps, 0.0), n, scale) - c;
	float cz = sample_triplanar(p + vec3(0.0, 0.0, eps), n, scale) - c;
	return vec3(cx, cy, cz) / eps;
}

void vertex() {
	v_pos = VERTEX;      // object-space
	v_nrm = NORMAL;      // object-space
}

void fragment() {
	// Use object-space position scaled by planet radius for stable triplanar coords
	vec3 p = v_pos / max(planet_radius, 1e-3);
	vec3 n = normalize(v_nrm);
	vec3 radial = normalize(v_pos);

	float detail_weight = 1.0; // camera-distance fade disabled to avoid world-space deps

	// Triplanar procedural height/detail
	float h = sample_triplanar(p, n, detail_scale);
	float detail = (h - 0.5) * 2.0; // [-1, 1]

	// Base from vertex color
	vec3 base = COLOR.rgb;

	// Slope darkening based on angle to radial up
	float slope = 1.0 - clamp(dot(n, radial), 0.0, 1.0);

	// Cavity term from local gradient magnitude
	vec3 grad = triplanar_gradient(p, n, detail_scale);
	float grad_mag = length(grad);
	float cavity = smoothstep(0.08, 0.6, grad_mag);
	float cavity_term = cavity * cavity_strength * detail_weight;

	// Detail modulation, narrowed range and clamped
	float t = detail * 0.5 + 0.5;
	float detail_mod = mix(1.0 - detail_strength, 1.0 + detail_strength * 0.25, t);
	detail_mod = mix(1.0, detail_mod, detail_weight);

	// Final albedo
	vec3 albedo = base * detail_mod;
	albedo = mix(albedo, albedo * 0.88, slope_darkening_strength * slope * detail_weight);
	albedo *= (1.0 - 0.15 * cavity_term);
	albedo = clamp(albedo, vec3(0.08), vec3(0.92));

	ALBEDO = albedo;
	SPECULAR = 0.02;
	ROUGHNESS = clamp(0.96 + 0.03 * (1.0 - slope) + 0.04 * cavity_term, 0.0, 1.0);
}