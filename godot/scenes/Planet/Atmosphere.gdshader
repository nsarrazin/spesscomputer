shader_type spatial;
render_mode unshaded, cull_front, depth_draw_never, blend_add;

uniform float planet_radius : hint_range(0.0, 1e9) = 200000.0;
uniform float atmosphere_height : hint_range(0.0, 1e8) = 6000.0;
uniform float outer_radius : hint_range(0.0, 1e9) = 206000.0;

uniform float intensity_rayleigh : hint_range(0.0, 2.0) = 0.25;
uniform float intensity_mie : hint_range(0.0, 2.0) = 0.05;
uniform float g : hint_range(-0.99, 0.99) = 0.8;

uniform vec3 rayleigh_color : source_color = vec3(0.55, 0.75, 1.0);
uniform vec3 mie_color : source_color = vec3(1.0, 0.95, 0.9);

// Sun light direction in planet object-space (points from planet towards sun)
uniform vec3 sun_dir_object = vec3(0.0, -1.0, 0.0);
// Camera position in planet object space, provided from script
uniform vec3 camera_pos_object = vec3(0.0);

varying vec3 v_pos_obj;

float rayleigh_phase(float cosTheta) {
	return 3.0 / (16.0 * PI) * (1.0 + cosTheta * cosTheta);
}

float hg_phase(float cosTheta, float g_val) {
	float g2 = g_val * g_val;
	float denom = pow(max(1.0 + g2 - 2.0 * g_val * cosTheta, 1e-3), 1.5);
	return (1.0 / (4.0 * PI)) * (1.0 - g2) / denom;
}

void vertex() {
	v_pos_obj = VERTEX;
}

void fragment() {
	// Camera position in planet object-space passed from script
	vec3 cam_pos_obj = camera_pos_object;
	vec3 view_dir = normalize(cam_pos_obj - v_pos_obj);
	vec3 up_from_center = normalize(v_pos_obj);
	float r = length(v_pos_obj);

	// Exponential density falloff with height above surface
	float h = max(r - planet_radius, 0.0);
	float H = max(atmosphere_height, 1.0);
	float density = exp(-h / (0.5 * H));

	// Thicker towards horizon for visual oomph
	float horizon = pow(1.0 - clamp(dot(up_from_center, view_dir), 0.0, 1.0), 1.25);
	float thickness = density * (0.6 + 1.6 * horizon);

	// Phase functions based on sun-view angle
	vec3 sun_dir = normalize(sun_dir_object);
	float cosTheta = clamp(dot(view_dir, sun_dir), -1.0, 1.0);
	float pr = rayleigh_phase(cosTheta);
	float pm = hg_phase(cosTheta, g);

	vec3 scatter = rayleigh_color * intensity_rayleigh * pr + mie_color * intensity_mie * pm;
	vec3 col = scatter * thickness;

	EMISSION = col;
	ALBEDO = vec3(0.0);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	ALPHA = clamp(length(col), 0.0, 1.0);
} 