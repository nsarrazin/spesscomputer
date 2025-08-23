shader_type spatial;
render_mode unshaded, cull_front, depth_draw_never, blend_add;

uniform float planet_radius : hint_range(0.0, 1e9) = 200000.0;
uniform float atmosphere_height : hint_range(0.0, 1e8) = 6000.0;

// Simplified atmosphere controls
uniform float intensity : hint_range(0.0, 2.0) = 0.5;
uniform vec3 atmosphere_color : source_color = vec3(0.55, 0.75, 1.0);
uniform float density_falloff : hint_range(0.1, 2.0) = 0.8;
uniform float horizon_power : hint_range(1.0, 4.0) = 2.0;

// Sun light direction in planet object-space (points from planet towards sun)
uniform vec3 sun_dir_object = vec3(0.0, -1.0, 0.0);
// Camera position in planet object space, provided from script
uniform vec3 camera_pos_object = vec3(0.0);

varying vec3 v_pos_obj;

void vertex() {
	v_pos_obj = VERTEX;
}

void fragment() {
	vec3 cam_pos_obj = camera_pos_object;
	vec3 view_dir = normalize(cam_pos_obj - v_pos_obj);
	vec3 up_from_center = normalize(v_pos_obj);
	float r = length(v_pos_obj);

	// Exponential density falloff with height above surface
	float h = max(r - planet_radius, 0.0);
	float H = max(atmosphere_height, 1.0);
	float density = exp(-h / (density_falloff * H));

	// Enhanced horizon effect for more atmospheric depth
	float horizon = 1.0 - clamp(dot(up_from_center, view_dir), 0.0, 1.0);
	horizon = pow(horizon, horizon_power);
	
	// Sun direction influence for simple scattering
	vec3 sun_dir = normalize(sun_dir_object);
	float sun_alignment = clamp(dot(view_dir, sun_dir), 0.0, 1.0);
	float scattering = 0.6 + 0.4 * sun_alignment;

	// Final atmospheric glow
	float thickness = density * horizon * scattering;
	vec3 final_color = atmosphere_color * intensity * thickness;

	EMISSION = final_color;
	ALBEDO = vec3(0.0);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	ALPHA = clamp(length(final_color), 0.0, 1.0);
} 