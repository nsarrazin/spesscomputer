@tool
extends Node3D

@onready var mesh_instance = $MeshInstance3D
@onready var collision_shape_instance = $CollisionShape3D

@export var regenerate_in_editor: bool = false: set = _regenerate_in_editor_button

@export_group("Dimensions")
@export var radius: float = 200000.0
@export var segments: int = 128
@export_group("Terrain Noise")
@export var relief_scale: float = 0.06
@export_group("Base Noise")
@export var base_frequency: float = 0.08
@export var base_octaves: int = 4
@export var base_lacunarity: float = 2.0
@export var base_gain: float = 0.45
@export_group("Detail Noise")
@export var detail_frequency: float = 2.5
@export var detail_octaves: int = 4
@export var detail_lacunarity: float = 2.2
@export var detail_gain: float = 0.48
@export_group("Micro Noise")
@export var micro_frequency: float = 6.0
@export var micro_octaves: int = 3
@export var micro_lacunarity: float = 2.4
@export var micro_gain: float = 0.52
@export var micro_strength: float = 0.25
@export_group("Feature Shaping")
@export var flatten_deadband: float = 0.15
@export var terrace_steps: int = 7
@export var terrace_strength: float = 3
@export var range_strength: float = 0.35
@export var range_frequency_main: float = 1.6
@export var range_anisotropy: float = 0.2
@export var range_rotation_deg: float = 47.0
@export_group("Polar Ice Caps")
@export var ice_cap_latitude_start: float = 0.82 # Latitude where the transition to ice caps begins
@export var ice_cap_latitude_full: float = 0.86 # Latitude where the transition to ice caps is complete
@export var ice_cap_height_bias: float = 0.25 # Raised height of the final ice cap, relative to relief_scale
@export_group("Mesh Quality")
@export var smooth_iterations: int = 0
@export var smooth_lambda: float = 0.5
@export var alternate_quad_diagonals: bool = true
@export_group("Performance")
@export var use_threaded_generation: bool = false
@export var generation_chunk_size: int = 8
@export_group("Physics")
@export var rotation_speed: float = 0.005
@export var gravitational_pull: float = 3e9
@export_group("Atmosphere")
@export var atmosphere_height_scale: float = 0.4 # fraction of radius
@export var atmosphere_intensity: float = 0.5
@export var atmosphere_mie_intensity: float = 0.3
@export var atmosphere_g: float = 0.5 # mie anisotropy
@export var atmosphere_color: Color = Color(0.55, 0.75, 1.0)
@export var atmosphere_mie_color: Color = Color(1.0, 0.95, 0.9)
@export var atmosphere_segments: int = 32
@export var use_mesh_atmosphere: bool = true
@export_group("Scatter")
@export var enable_scatter: bool = true
@export var scatter_radius: float = 800.0
@export var scatter_rebuild_move_deg: float = 2.0
@export var scatter_max_slope_deg: float = 28.0
@export var scatter_max_altitude: float = 1200.0
@export var scatter_hide_above_altitude: float = 2500.0
@export var pebble_count: int = 1400
@export var pebble_scale_range: Vector2 = Vector2(0.25, 0.8)
@export var boulder_count: int = 60
@export var boulder_scale_range: Vector2 = Vector2(2.0, 6.0)
@export var boulder_min_spacing: float = 25.0
@export var scatter_cast_shadows: bool = true
@export var scatter_color_pebble: Color = Color(0.30, 0.20, 0.16)
@export var scatter_color_boulder: Color = Color(0.26, 0.18, 0.14)
@export var scatter_draw_distance: float = 8000.0
@export var scatter_update_interval: float = 0.25
@export_group("") # End groups

var noise: FastNoiseLite = FastNoiseLite.new() # detail
var noise_base: FastNoiseLite = FastNoiseLite.new()
var noise_micro: FastNoiseLite = FastNoiseLite.new()
var surface_tool = SurfaceTool.new()
var mesh = ArrayMesh.new()
var max_terrain_height = 0.0
var vertices: Array[Vector3] = []
var initialized = false
var range_basis: Basis

# Performance optimization variables
var height_cache: Dictionary = {}
var generation_in_progress: bool = false

# Scatter runtime state
var pebbles_mmi: MultiMeshInstance3D
var boulders_mmi: MultiMeshInstance3D
var scatter_rng := RandomNumberGenerator.new()
var precomp_pebble: Array[Transform3D] = []
var precomp_boulder: Array[Transform3D] = []
var scatter_update_accum: float = 0.0
var last_scatter_center_dir: Vector3 = Vector3.ZERO
var scatter_initialized_dir: bool = false

# Collision nodes created/managed at runtime
var landing_static_body: StaticBody3D
var landing_collision_shape: CollisionShape3D

# Atmosphere nodes/material
var atmosphere_mesh_instance: MeshInstance3D
var atmosphere_material: ShaderMaterial

func _ready() -> void:
	# Configure noise 
	_configure_noise_instances()
	
	# Cache a basis to orient mountain ranges (deterministic)
	var axis: Vector3 = Vector3(0.42, 0.86, 0.27).normalized()
	range_basis = Basis(axis, deg_to_rad(range_rotation_deg))
	
	# Optimize global physics
	Engine.physics_ticks_per_second = 30
	Engine.max_physics_steps_per_frame = 4
	
	# Generate mesh with collision
	generate_planet()
	
	# Setup atmosphere shell if enabled
	if use_mesh_atmosphere:
		_create_or_update_atmosphere()
	
	# Prepare scatter nodes
	if enable_scatter:
		_ensure_scatter_nodes()
		_precompute_scatter()
		_update_scatter()
	
	initialized = true

func generate_planet() -> void:
	if generation_in_progress:
		return
	generation_in_progress = true
	print("Generating planet mesh...")
	
	# Clear cache for fresh generation
	height_cache.clear()
	
	if use_threaded_generation:
		generate_planet_mesh_threaded()
	else:
		generate_planet_mesh()
	
	generation_in_progress = false
	

func _cube_face_dir(face: int, u: float, v: float) -> Vector3:
	match face:
		0:
			return Vector3(1.0, v, -u)
		1:
			return Vector3(-1.0, v, u)
		2:
			return Vector3(u, 1.0, -v)
		3:
			return Vector3(u, -1.0, v)
		4:
			return Vector3(u, v, 1.0)
		_:
			return Vector3(-u, v, -1.0)

func _spherify_cube_dir(face: int, u: float, v: float) -> Vector3:
	var c: Vector3 = _cube_face_dir(face, u, v)
	var x: float = c.x
	var y: float = c.y
	var z: float = c.z
	var x2: float = x * x
	var y2: float = y * y
	var z2: float = z * z
	var sx: float = x * sqrt(1.0 - 0.5 * (y2 + z2) + (y2 * z2) / 3.0)
	var sy: float = y * sqrt(1.0 - 0.5 * (z2 + x2) + (z2 * x2) / 3.0)
	var sz: float = z * sqrt(1.0 - 0.5 * (x2 + y2) + (x2 * y2) / 3.0)
	return Vector3(sx, sy, sz)

func get_normal_for_vertex_index(i: int) -> Vector3:
	return vertices[i].normalized()

func generate_planet_mesh_threaded() -> void:
	print("Using threaded planet generation...")
	# For now, call regular version but with processing breaks
	generate_planet_mesh_chunked()

func generate_planet_mesh_chunked() -> void:
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	# Generate cube-sphere vertices in chunks
	var segs: int = maxi(segments, 4)
	vertices.clear()
	var uvs: Array[Vector2] = []
	var dirs: Array[Vector3] = []
	var heights: Array[float] = []
	
	# Reset height tracker
	max_terrain_height = 0.0
	
	print("Generating ", (segs + 1) * (segs + 1) * 6, " vertices...")
	
	# Build vertices for 6 faces with chunked processing
	for face in range(6):
		for iy_start in range(0, segs + 1, generation_chunk_size):
			var iy_end = mini(iy_start + generation_chunk_size, segs + 1)
			for iy in range(iy_start, iy_end):
				var v = (float(iy) / float(segs)) * 2.0 - 1.0
				for ix in range(segs + 1):
					var u = (float(ix) / float(segs)) * 2.0 - 1.0
					var dir = _spherify_cube_dir(face, u, v).normalized()
					dirs.append(dir)
					var height = calculate_terrain_height(dir)
					heights.append(height)
					if abs(height) > max_terrain_height:
						max_terrain_height = abs(height)
					var pos = dir * (radius + height)
					vertices.append(pos)
					uvs.append(Vector2(float(ix) / float(segs), float(iy) / float(segs)))
			# Yield every chunk to prevent frame drops
			if iy_end < segs + 1:
				await get_tree().process_frame
	
	print("Generated vertices, building triangles...")
	_build_planet_triangles(segs, uvs)

func generate_planet_mesh() -> void:
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	# Generate cube-sphere vertices
	var segs: int = maxi(segments, 4)
	vertices.clear()
	var uvs: Array[Vector2] = []
	var dirs: Array[Vector3] = []
	var heights: Array[float] = []
	
	# Reset height tracker
	max_terrain_height = 0.0
	
	# Build vertices for 6 faces
	for face in range(6):
		for iy in range(segs + 1):
			var v = (float(iy) / float(segs)) * 2.0 - 1.0
			for ix in range(segs + 1):
				var u = (float(ix) / float(segs)) * 2.0 - 1.0
				var dir = _spherify_cube_dir(face, u, v).normalized()
				dirs.append(dir)
				var height = calculate_terrain_height(dir)
				heights.append(height)
				if abs(height) > max_terrain_height:
					max_terrain_height = abs(height)
				var pos = dir * (radius + height)
				vertices.append(pos)
				uvs.append(Vector2(float(ix) / float(segs), float(iy) / float(segs)))
	
	# Optional face-local smoothing to reduce jaggedness
	if smooth_iterations > 0 and segs >= 2:
		var face_stride: int = (segs + 1) * (segs + 1)
		for _i in range(smooth_iterations):
			var new_heights: Array[float] = heights.duplicate()
			for face in range(6):
				var base: int = face * face_stride
				for iy in range(1, segs):
					for ix in range(1, segs):
						var idx: int = base + iy * (segs + 1) + ix
						var n0: int = idx - 1
						var n1: int = idx + 1
						var n2: int = idx - (segs + 1)
						var n3: int = idx + (segs + 1)
						var avg: float = (heights[n0] + heights[n1] + heights[n2] + heights[n3]) * 0.25
						new_heights[idx] = lerpf(heights[idx], avg, clampf(smooth_lambda, 0.0, 1.0))
			heights = new_heights
			# Recompute vertices and max height after smoothing
			max_terrain_height = 0.0
			for i in range(heights.size()):
				if abs(heights[i]) > max_terrain_height:
					max_terrain_height = abs(heights[i])
				vertices[i] = dirs[i] * (radius + heights[i])
	
	_build_planet_triangles(segs, uvs)

func _build_planet_triangles(segs: int, uvs: Array[Vector2]) -> void:
	# Create triangles per face (alternate diagonals to reduce directional artifacts)
	var face_stride2: int = (segs + 1) * (segs + 1)
	for face in range(6):
		var base2: int = face * face_stride2
		for iy in range(segs):
			for ix in range(segs):
				var i0: int = base2 + iy * (segs + 1) + ix
				var i1: int = i0 + 1
				var i2: int = i0 + (segs + 1)
				var i3: int = i2 + 1
				var flip: bool = alternate_quad_diagonals and (((ix + iy) & 1) == 1)
				if flip:
					# Diagonal (i0-i3)
					_add_triangle(i0, i2, i3, uvs)
					_add_triangle(i0, i3, i1, uvs)
				else:
					# Diagonal (i1-i2)
					_add_triangle(i0, i2, i1, uvs)
					_add_triangle(i1, i2, i3, uvs)
	
	surface_tool.index()
	mesh = surface_tool.commit()
	
	# Build/update trimesh collision for landing
	_update_collision_from_mesh()
	
	# Create and apply lunar material
	var material = create_planet_material()
	
	mesh_instance.mesh = mesh
	mesh_instance.material_override = material

func _add_triangle(i0: int, i1: int, i2: int, uvs: Array[Vector2]) -> void:
	# Add triangle with reduced function calls
	surface_tool.set_uv(uvs[i0])
	surface_tool.set_color(get_color_for_vertex_index(i0))
	surface_tool.set_normal(get_normal_for_vertex_index(i0))
	surface_tool.add_vertex(vertices[i0])
	
	surface_tool.set_uv(uvs[i1])
	surface_tool.set_color(get_color_for_vertex_index(i1))
	surface_tool.set_normal(get_normal_for_vertex_index(i1))
	surface_tool.add_vertex(vertices[i1])
	
	surface_tool.set_uv(uvs[i2])
	surface_tool.set_color(get_color_for_vertex_index(i2))
	surface_tool.set_normal(get_normal_for_vertex_index(i2))
	surface_tool.add_vertex(vertices[i2])


func _ensure_collision_nodes() -> void:
	if landing_static_body == null or not is_instance_valid(landing_static_body):
		if is_instance_valid(collision_shape_instance) and collision_shape_instance.get_parent() is StaticBody3D:
			landing_static_body = collision_shape_instance.get_parent()
			landing_collision_shape = collision_shape_instance
		else:
			landing_static_body = StaticBody3D.new()
			landing_static_body.name = "PlanetStaticBody"
			add_child(landing_static_body)
			if is_instance_valid(collision_shape_instance):
				collision_shape_instance.get_parent().remove_child(collision_shape_instance)
				landing_static_body.add_child(collision_shape_instance)
				landing_collision_shape = collision_shape_instance
			else:
				landing_collision_shape = CollisionShape3D.new()
				landing_static_body.add_child(landing_collision_shape)
		# Physics material for better landing behavior
	var pm := PhysicsMaterial.new()
	pm.friction = 1.0
	pm.bounce = 0.0
	landing_static_body.physics_material_override = pm
	# Ensure the physics engine knows the surface is moving (rotating planet)
	landing_static_body.constant_linear_velocity = Vector3.ZERO
	landing_static_body.constant_angular_velocity = Vector3(0.0, rotation_speed, 0.0)

func _update_collision_from_mesh() -> void:
	_ensure_collision_nodes()
	if mesh == null:
		return
	var shape := mesh.create_trimesh_shape()
	landing_collision_shape.shape = shape


# Function to calculate terrain height at a point with caching
func calculate_terrain_height(point: Vector3) -> float:
	# Work in unit-sphere space for sampling
	var p: Vector3 = point.normalized()
	
	# Check cache first (quantize position for cache key)
	var cache_key: Vector3i = Vector3i(
		int(p.x * 1000),
		int(p.y * 1000),
		int(p.z * 1000)
	)
	if height_cache.has(cache_key):
		return height_cache[cache_key]
	
	# Lightweight domain warp to break up uniformity
	var warp_amp: float = 0.2
	var pw: Vector3 = p + Vector3(
		noise.get_noise_3d(p.x * 3.1, p.y * 3.1, p.z * 3.1),
		noise.get_noise_3d(p.x * 3.7, p.y * 3.7, p.z * 3.7),
		noise.get_noise_3d(p.x * 4.3, p.y * 4.3, p.z * 4.3)
	) * warp_amp
	
	# Large-scale continents/ridges (ridged FBM)
	var base_raw: float = noise_base.get_noise_3d(pw.x, pw.y, pw.z)
	var ridge: float = 1.0 - absf(base_raw)
	ridge = clampf(ridge, 0.0, 1.0)
	ridge = pow(ridge, 1.5) # sharper crests
	var base_mask: float = clampf(0.5 * (base_raw + 1.0), 0.0, 1.0)
	
	# Finer detail (FBM Perlin)
	var detail_raw: float = noise.get_noise_3d(pw.x, pw.y, pw.z)
	
	# Micro detail (high-frequency FBM)
	var micro_raw: float = noise_micro.get_noise_3d(pw.x, pw.y, pw.z)
	micro_raw = signf(micro_raw) * pow(absf(micro_raw), 1.15)
	var micro_weight: float = 0.3 + 0.7 * base_mask
	
	# Directional mountain ranges (anisotropic, oriented)
	var pr: Vector3 = range_basis * p
	var rn: float = noise.get_noise_3d(
		pr.x * range_frequency_main,
		pr.y * (range_frequency_main * range_anisotropy),
		pr.z * range_frequency_main
	)
	var rr: float = 1.0 - absf(rn)
	rr = pow(clampf(rr, 0.0, 1.0), 3.0)
	var range_term: float = maxf((rr - 0.55) * 2.2, 0.0) # emphasize ridges only
	
	# Combine with hierarchy and bias to carve valleys
	var combined: float = base_raw * 0.5 + detail_raw * 0.25 + ridge * 0.6 - 0.18
	combined += micro_raw * (micro_strength * micro_weight)
	combined += range_term * range_strength
	combined = signf(combined) * pow(absf(combined), 1.25)
	# Apply flattening deadband around zero height to create broader flats
	var db := clampf(flatten_deadband, 0.0, 0.95)
	if db > 0.0:
		var a := absf(combined)
		if a <= db:
			combined = 0.0
		else:
			var remapped := (a - db) / (1.0 - db)
			combined = signf(combined) * remapped
	
	# Terracing for plateaus
	var q: float = clampf(0.5 * (combined + 1.0), 0.0, 1.0)
	var steps: float = float(max(1, terrace_steps))
	var terr_q: float = floor(q * steps) / steps
	var terr_centered: float = terr_q * 2.0 - 1.0
	combined = lerpf(combined, terr_centered, clampf(terrace_strength, 0.0, 1.0))
	
	# Apply polar ice cap flattening for a crisp edge
	var lat: float = absf(p.y) # absolute latitude (0.0=equator, 1.0=pole)
	var ice_transition: float = smoothstep(ice_cap_latitude_start, ice_cap_latitude_full, lat)
	
	if ice_transition > 0.0:
		# Define the target ice cap appearance: mostly flat but with a slight elevation bias
		var flat_ice_height = ice_cap_height_bias
		
		# Reduce the existing terrain variation significantly as we transition to ice
		var smoothed_terrain = combined * lerpf(1.0, 0.05, ice_transition) # Reduce to 5% variation at full ice
		
		# Blend between the smoothed terrain and the target ice cap height
		combined = lerpf(smoothed_terrain, flat_ice_height, ice_transition)
	
	# Scale to world amplitude
	var result = combined * (radius * relief_scale)
	
	# Cache the result
	height_cache[cache_key] = result
	return result

# Get height at a specific point on planet
func get_height_at_position(global_pos: Vector3) -> float:
	var local_pos = global_transform.affine_inverse() * global_pos
	var direction = local_pos.normalized()
	
	# Calculate the height using noise
	var height = calculate_terrain_height(direction)
	
	return radius + height

# Map per-vertex height to a color
func get_color_for_vertex_index(i: int) -> Color:
	var v: Vector3 = vertices[i]
	var height: float = v.length() - radius
	var t: float = 0.5
	if max_terrain_height > 0.0:
		t = clampf(0.5 + 0.5 * (height / max_terrain_height), 0.0, 1.0)
	var dir: Vector3 = v.normalized()
	var lat: float = absf(dir.y)
	
	# Base red palette by height (valleys darkest red, tops deep red but not bright)
	var base: Color = mars_height_to_color(t)
	
	# Subtle color variation (towards darker tint rather than white), fade near poles
	var n: float = noise.get_noise_3d(dir.x * 120.0, dir.y * 120.0, dir.z * 120.0)
	var var_amt: float = 0.03 * (0.5 + 0.5 * n)
	var polar_fade: float = 1.0 - smoothstep(0.86, 0.98, lat)
	base = base.lerp(Color(0.12, 0.07, 0.05), var_amt * polar_fade)
	
	# Ice caps: use a crisp smoothstep transition consistent with terrain generation
	var snow_mix: float = smoothstep(ice_cap_latitude_start, ice_cap_latitude_full, lat)
	
	var snow_color: Color = Color(0.8, 0.84, 0.88) # Darker, less blinding ice color
	return base.lerp(snow_color, snow_mix)

func mars_height_to_color(t: float) -> Color:
	# Mars-like red-orange ramp
	var low = Color(0.24, 0.10, 0.07) # darker red-brown for lowlands
	var mid = Color(0.55, 0.28, 0.14) # rusty red-orange
	var high = Color(0.76, 0.50, 0.32) # dusty orange (not too light)
	if t < 0.5:
		return low.lerp(mid, t / 0.5)
	else:
		return mid.lerp(high, (t - 0.5) / 0.5)

# Creates a shader material with triplanar detail, slope/cavity shading
func create_planet_material() -> ShaderMaterial:
	var shader: Shader = load("res://scenes/Planet/PlanetDetail.gdshader")
	var material := ShaderMaterial.new()
	material.shader = shader
	
	# Wire uniforms
	material.set_shader_parameter("planet_radius", radius)
	material.set_shader_parameter("detail_scale", 24.0)
	material.set_shader_parameter("detail_strength", 0.15)
	material.set_shader_parameter("ground_texture", load("res://art/images/ground.jpg"))
	material.set_shader_parameter("normal_strength", 0.0)
	material.set_shader_parameter("detail_fade_start", radius * 0.6)
	material.set_shader_parameter("detail_fade_end", radius * 3.0)
	material.set_shader_parameter("slope_darkening_strength", 0.20)
	material.set_shader_parameter("cavity_strength", 0.12)
	# Atmosphere rim uniforms for surface shader
	material.set_shader_parameter("atmo_height", radius * atmosphere_height_scale)
	material.set_shader_parameter("atmo_intensity_rayleigh", atmosphere_intensity)
	material.set_shader_parameter("atmo_intensity_mie", atmosphere_mie_intensity)
	material.set_shader_parameter("atmo_g", clampf(atmosphere_g, -0.99, 0.99))
	material.set_shader_parameter("atmo_rayleigh_color", atmosphere_color)
	material.set_shader_parameter("atmo_mie_color", atmosphere_mie_color)
	return material

func _process(_delta: float):
	# In the editor or at runtime, the separate atmosphere mesh needs continuous updates
	# to correctly calculate its appearance based on camera position. This will not
	# reintroduce shadow artifacts as the atmosphere mesh does not cast shadows.
	if use_mesh_atmosphere:
		if not is_instance_valid(atmosphere_material):
			return
		# Only update if the node is visible and in a viewport
		if is_visible_in_tree() and get_viewport():
			_update_atmosphere_params()

func _physics_process(delta: float) -> void:
	if not initialized:
		return
		
	# Rotate planet
	rotate_y(rotation_speed * delta)
	
	# Keep platform motion in sync so landed bodies stick to surface
	if is_instance_valid(landing_static_body):
		landing_static_body.constant_angular_velocity = Vector3(0.0, rotation_speed, 0.0)
	
	# Atmosphere is a separate visual effect and must be updated each frame
	# to work correctly from different camera angles. It does not cast shadows,
	# so this will not reintroduce the rolling shadow artifacts on the surface.
	if use_mesh_atmosphere:
		_update_atmosphere_params()
	
	# Apply gravitational pull only to bodies that aren't too far
	for body in get_tree().get_nodes_in_group("affected_by_gravity"):
		if body is RigidBody3D:
			if not is_instance_valid(body) or body.freeze:
				continue
				
			var direction = global_position - body.global_position
			var distance = direction.length()
				
			var force_magnitude = (gravitational_pull * body.mass) / (distance * distance)
			var force = direction.normalized() * force_magnitude
			
			body.apply_central_force(force)

	# Update local scatter near camera
	if enable_scatter:
		_update_scatter()

# Atmosphere helpers
func _create_or_update_atmosphere() -> void:
	var shell_height: float = max(1.0, radius * atmosphere_height_scale)
	var atm_radius: float = radius + shell_height
	if atmosphere_mesh_instance == null or not is_instance_valid(atmosphere_mesh_instance):
		atmosphere_mesh_instance = MeshInstance3D.new()
		atmosphere_mesh_instance.name = "Atmosphere"
		var sm := SphereMesh.new()
		sm.radius = atm_radius
		sm.height = atm_radius * 2.0
		sm.radial_segments = max(24, atmosphere_segments)
		sm.rings = max(12, int(atmosphere_segments / 2))
		atmosphere_mesh_instance.mesh = sm
		atmosphere_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(atmosphere_mesh_instance)
		
		var shader: Shader = load("res://scenes/Planet/Atmosphere.gdshader")
		atmosphere_material = ShaderMaterial.new()
		atmosphere_material.shader = shader
		atmosphere_mesh_instance.material_override = atmosphere_material
	else:
		# Update sphere size if radius changed
		if atmosphere_mesh_instance.mesh is SphereMesh:
			var sm2: SphereMesh = atmosphere_mesh_instance.mesh
			sm2.radius = atm_radius
			sm2.height = atm_radius * 2.0
	
	_update_atmosphere_params()

func _get_directional_light() -> DirectionalLight3D:
	# Try sibling named DirectionalLight3D
	var n = get_parent()
	if n and n.has_node("DirectionalLight3D"):
		var l = n.get_node("DirectionalLight3D")
		if l is DirectionalLight3D:
			return l
	# Fallback: search the tree (first one)
	for node in get_tree().get_nodes_in_group(""):
		# no dedicated group; skip
		pass
	# Broad fallback: scan root children
	var root = get_tree().current_scene
	if root:
		for c in root.get_children():
			if c is DirectionalLight3D:
				return c
	return null

func _update_atmosphere_params() -> void:
	if atmosphere_material == null:
		return
	var shell_height: float = max(1.0, radius * atmosphere_height_scale)
	atmosphere_material.set_shader_parameter("planet_radius", radius)
	atmosphere_material.set_shader_parameter("atmosphere_height", shell_height)
	atmosphere_material.set_shader_parameter("intensity", atmosphere_intensity)
	atmosphere_material.set_shader_parameter("atmosphere_color", atmosphere_color)
	atmosphere_material.set_shader_parameter("density_falloff", 0.8)
	atmosphere_material.set_shader_parameter("horizon_power", 2.0)
	# Sun direction in world
	var light := _get_directional_light()
	var sun_dir_world: Vector3 = Vector3(0, -1, 0)
	if light:
		# DirectionalLight points towards -Z in its local; light direction is -basis.z
		sun_dir_world = - (light.global_transform.basis.z).normalized()
	# Convert to planet local/object space
	var sun_dir_obj: Vector3 = (global_transform.basis.inverse() * sun_dir_world).normalized()
	atmosphere_material.set_shader_parameter("sun_dir_object", sun_dir_obj)
	# Camera position in planet object space
	var _cam := get_viewport().get_camera_3d()
	if _cam:
		var cam_obj: Vector3 = to_local(_cam.global_transform.origin)
		atmosphere_material.set_shader_parameter("camera_pos_object", cam_obj)

func _update_surface_atmo_params() -> void:
	var smat := mesh_instance.material_override as ShaderMaterial
	if smat == null:
		return
	smat.set_shader_parameter("atmo_height", radius * atmosphere_height_scale)
	smat.set_shader_parameter("atmo_intensity", atmosphere_intensity * 0.4)
	smat.set_shader_parameter("atmo_color", atmosphere_color)
	# Sun direction
	var light := _get_directional_light()
	var sun_dir_world: Vector3 = Vector3(0, -1, 0)
	if light:
		sun_dir_world = - (light.global_transform.basis.z).normalized()
	var sun_dir_obj: Vector3 = (global_transform.basis.inverse() * sun_dir_world).normalized()
	smat.set_shader_parameter("atmo_sun_dir_object", sun_dir_obj)
	# Camera pos in object
	var _cam2 := get_viewport().get_camera_3d()
	if _cam2:
		var cam_obj: Vector3 = to_local(_cam2.global_transform.origin)
		smat.set_shader_parameter("atmo_camera_pos_object", cam_obj)


# Scatter: nodes, materials, and generation
func _project_offset_to_surface(center_world: Vector3, tangent: Vector3, bitangent: Vector3, off: Vector2) -> Dictionary:
	var wpos := center_world + (tangent * off.x + bitangent * off.y)
	var dir := wpos.normalized()
	var h := calculate_terrain_height(dir)
	var surf := dir * (radius + h)
	var n := dir
	return {"pos": surf, "normal": n, "dir": dir, "height": h}

func _precompute_scatter() -> void:
	precomp_pebble.clear()
	precomp_boulder.clear()
	scatter_rng.seed = 13371337
	var _cam := get_viewport().get_camera_3d()
	if _cam == null:
		return
	var cam_local := to_local(_cam.global_transform.origin)
	var center_dir := cam_local.normalized()
	var center_world_radius := radius + calculate_terrain_height(center_dir)
	var center_world := center_dir * center_world_radius
	var up_center := center_dir
	var tangent := up_center.cross(Vector3(0, 1, 0))
	if tangent.length() < 0.01:
		tangent = up_center.cross(Vector3(1, 0, 0))
	tangent = tangent.normalized()
	var bitangent := up_center.cross(tangent).normalized()
	# Boulders with spacing
	var placed_boulders: Array[Vector3] = []
	var idx_b := 0
	var max_attempts_b := boulder_count * 20
	var attempts_b := 0
	while idx_b < boulder_count and attempts_b < max_attempts_b:
		attempts_b += 1
		var r := sqrt(scatter_rng.randf()) * scatter_radius
		var ang := scatter_rng.randf_range(0.0, TAU)
		var off := Vector2(r * cos(ang), r * sin(ang))
		var surf := _project_offset_to_surface(center_world, tangent, bitangent, off)
		var pos: Vector3 = surf.pos
		var n: Vector3 = surf.normal
		var slope_deg := rad_to_deg(acos(clampf(n.dot(pos.normalized()), -1.0, 1.0)))
		if slope_deg > scatter_max_slope_deg:
			continue
		var too_close := false
		for p in placed_boulders:
			if p.distance_to(pos) < boulder_min_spacing:
				too_close = true
				break
		if too_close:
			continue
		placed_boulders.append(pos)
		var s := scatter_rng.randf_range(boulder_scale_range.x, boulder_scale_range.y)
		var x := n.cross(Vector3(0, 1, 0))
		if x.length() < 0.01:
			x = n.cross(Vector3(1, 0, 0))
		x = x.normalized()
		var y := n.cross(x).normalized()
		var b_basis := Basis()
		b_basis.x = x * s
		b_basis.y = y * s
		b_basis.z = n * s
		precomp_boulder.append(Transform3D(b_basis, pos))
		idx_b += 1
	# Pebbles fill
	var idx_p := 0
	var max_attempts_p := pebble_count * 4
	var attempts_p := 0
	while idx_p < pebble_count and attempts_p < max_attempts_p:
		attempts_p += 1
		var r2 := sqrt(scatter_rng.randf()) * scatter_radius
		var ang2 := scatter_rng.randf_range(0.0, TAU)
		var off2 := Vector2(r2 * cos(ang2), r2 * sin(ang2))
		var surf2 := _project_offset_to_surface(center_world, tangent, bitangent, off2)
		var pos2: Vector3 = surf2.pos
		var n2: Vector3 = surf2.normal
		var slope2 := rad_to_deg(acos(clampf(n2.dot(pos2.normalized()), -1.0, 1.0)))
		if slope2 > scatter_max_slope_deg:
			continue
		var s2 := scatter_rng.randf_range(pebble_scale_range.x, pebble_scale_range.y)
		var sx := s2 * scatter_rng.randf_range(0.8, 1.2)
		var sy := s2 * scatter_rng.randf_range(0.8, 1.2)
		var sz := s2 * scatter_rng.randf_range(0.8, 1.2)
		var x2 := n2.cross(Vector3(0, 1, 0))
		if x2.length() < 0.01:
			x2 = n2.cross(Vector3(1, 0, 0))
		x2 = x2.normalized()
		var y2 := n2.cross(x2).normalized()
		var basis2 := Basis()
		basis2.x = x2 * sx
		basis2.y = y2 * sy
		basis2.z = n2 * sz
		precomp_pebble.append(Transform3D(basis2, pos2))
		idx_p += 1
func _ensure_scatter_nodes() -> void:
	if pebbles_mmi == null or not is_instance_valid(pebbles_mmi):
		pebbles_mmi = MultiMeshInstance3D.new()
		pebbles_mmi.name = "Pebbles"
		pebbles_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if scatter_cast_shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(pebbles_mmi)
	if boulders_mmi == null or not is_instance_valid(boulders_mmi):
		boulders_mmi = MultiMeshInstance3D.new()
		boulders_mmi.name = "Boulders"
		boulders_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if scatter_cast_shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(boulders_mmi)
	# Materials and base meshes
	if pebbles_mmi.multimesh == null:
		pebbles_mmi.multimesh = _create_multimesh_sphere(Color8(0, 0, 0), false)
		pebbles_mmi.material_override = _create_simple_albedo_material(scatter_color_pebble)
	if boulders_mmi.multimesh == null:
		boulders_mmi.multimesh = _create_multimesh_icosphere()
		boulders_mmi.material_override = _create_simple_albedo_material(scatter_color_boulder)

func _create_simple_albedo_material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 1.0
	m.metallic = 0.0
	return m

func _create_multimesh_sphere(_unused_color: Color, high_detail: bool) -> MultiMesh:
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.radial_segments = 16 if high_detail else 10
	sphere.rings = 12 if high_detail else 8
	var mm := MultiMesh.new()
	mm.mesh = sphere
	mm.transform_format = MultiMesh.TRANSFORM_3D
	# Leave default formats; color/custom data unused
	return mm

func _create_multimesh_icosphere() -> MultiMesh:
	# Fallback to sphere primitive; fewer segments to look rock-like
	var sphere := SphereMesh.new()
	sphere.radius = 0.7
	sphere.height = 1.4
	sphere.radial_segments = 12
	sphere.rings = 8
	var mm := MultiMesh.new()
	mm.mesh = sphere
	mm.transform_format = MultiMesh.TRANSFORM_3D
	# Leave default formats; color/custom data unused
	return mm

func _update_scatter() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	# Determine current camera nadir direction and rebuild scatter if moved far enough
	var cam_local_dir: Vector3 = to_local(cam.global_transform.origin).normalized()
	if not scatter_initialized_dir:
		last_scatter_center_dir = cam_local_dir
		scatter_initialized_dir = true
		_precompute_scatter()
	else:
		var move_deg := rad_to_deg(acos(clampf(last_scatter_center_dir.dot(cam_local_dir), -1.0, 1.0)))
		if move_deg >= scatter_rebuild_move_deg:
			last_scatter_center_dir = cam_local_dir
			_precompute_scatter()
	# Throttle updates
	scatter_update_accum += get_physics_process_delta_time()
	if scatter_update_accum < scatter_update_interval:
		return
	scatter_update_accum = 0.0
	# Update visibility of precomputed instances by distance to camera (planet-local space)
	var cam_local: Vector3 = to_local(cam.global_transform.origin)
	var zero_basis := Basis()
	zero_basis.x = Vector3.ZERO
	zero_basis.y = Vector3.ZERO
	zero_basis.z = Vector3.ZERO
	var zero_xform := Transform3D(zero_basis, Vector3.ZERO)
	if is_instance_valid(pebbles_mmi) and pebbles_mmi.multimesh:
		var n := precomp_pebble.size()
		pebbles_mmi.multimesh.instance_count = n
		for i in range(n):
			var t: Transform3D = precomp_pebble[i]
			var d := t.origin.distance_to(cam_local)
			if d <= scatter_draw_distance:
				pebbles_mmi.multimesh.set_instance_transform(i, t)
			else:
				pebbles_mmi.multimesh.set_instance_transform(i, zero_xform)
	if is_instance_valid(boulders_mmi) and boulders_mmi.multimesh:
		var nb := precomp_boulder.size()
		boulders_mmi.multimesh.instance_count = nb
		for j in range(nb):
			var tb: Transform3D = precomp_boulder[j]
			var db := tb.origin.distance_to(cam_local)
			if db <= scatter_draw_distance:
				boulders_mmi.multimesh.set_instance_transform(j, tb)
			else:
				boulders_mmi.multimesh.set_instance_transform(j, zero_xform)

func _generate_scatter_for_center(center_dir: Vector3) -> void:
	# Ensure nodes
	_ensure_scatter_nodes()
	# Prepare RNG seed stable per spherical cell to minimize jitter/pop
	var lat: float = asin(center_dir.y)
	var lon: float = atan2(center_dir.x, center_dir.z)
	var cell_arc: float = 0.01
	var q_lat: int = int(floor(lat / cell_arc))
	var q_lon: int = int(floor(lon / cell_arc))
	var seed_i: int = int(((q_lat * 73856093) ^ (q_lon * 19349663)) & 0x7fffffff)
	scatter_rng.seed = seed_i
	# Allocate instances
	if is_instance_valid(pebbles_mmi):
		pebbles_mmi.multimesh.instance_count = pebble_count
	if is_instance_valid(boulders_mmi):
		boulders_mmi.multimesh.instance_count = boulder_count
	# Generate placements in a spherical cap around center_dir
	var _cam := get_viewport().get_camera_3d()
	var center_world_radius := radius + calculate_terrain_height(center_dir)
	var center_world := center_dir * center_world_radius
	var up_center := center_dir
	# Build tangent frame for sampling around the surface point
	var tangent := up_center.cross(Vector3(0, 1, 0))
	if tangent.length() < 0.01:
		tangent = up_center.cross(Vector3(1, 0, 0))
	tangent = tangent.normalized()
	var bitangent := up_center.cross(tangent).normalized()
	
	# Helper is top-level _project_offset_to_surface(center_world, tangent, bitangent, off)

	# Boulders first with Poisson-ish rejection for spacing
	var placed_boulders: Array[Vector3] = []
	var max_attempts := boulder_count * 12
	var attempts := 0
	var idx_b := 0
	while idx_b < boulder_count and attempts < max_attempts:
		attempts += 1
		var r := sqrt(scatter_rng.randf()) * scatter_radius
		var ang := scatter_rng.randf_range(0.0, TAU)
		var off := Vector2(r * cos(ang), r * sin(ang))
		var surf := _project_offset_to_surface(center_world, tangent, bitangent, off)
		var pos: Vector3 = surf.pos
		var n: Vector3 = surf.normal
		# Slope and altitude filters
		var slope_deg := rad_to_deg(acos(clampf(n.dot((pos).normalized()), -1.0, 1.0)))
		if slope_deg > scatter_max_slope_deg:
			continue
		# Altitude filter disabled for simplicity; keep everywhere that passes slope
		# Spacing from existing boulders
		var too_close := false
		for p in placed_boulders:
			if p.distance_to(pos) < boulder_min_spacing:
				too_close = true
				break
		if too_close:
			continue
		# Place boulder
		placed_boulders.append(pos)
		var rock_scale := scatter_rng.randf_range(boulder_scale_range.x, boulder_scale_range.y)
		var rock_basis := Basis()
		# Orient with normal: build orthonormal basis
		var z := n
		var x := z.cross(Vector3(0, 1, 0))
		if x.length() < 0.01:
			x = z.cross(Vector3(1, 0, 0))
		x = x.normalized()
		var y := z.cross(x).normalized()
		rock_basis.x = x * rock_scale
		rock_basis.y = y * rock_scale
		rock_basis.z = z * rock_scale
		boulders_mmi.multimesh.set_instance_transform(idx_b, Transform3D(rock_basis, pos))
		idx_b += 1
	# Fill remaining boulder instances (if any) as hidden at origin
	while idx_b < boulder_count:
		boulders_mmi.multimesh.set_instance_transform(idx_b, Transform3D())
		idx_b += 1

	# Pebbles: dense, cheaper, no spacing check
	var idx_p := 0
	var pebble_total := pebble_count
	for i in range(pebble_total):
		var r2 := sqrt(scatter_rng.randf()) * scatter_radius
		var ang2 := scatter_rng.randf_range(0.0, TAU)
		var off2 := Vector2(r2 * cos(ang2), r2 * sin(ang2))
		var surf2 := _project_offset_to_surface(center_world, tangent, bitangent, off2)
		var pos2: Vector3 = surf2.pos
		var n2: Vector3 = surf2.normal
		# Filters
		var slope2 := rad_to_deg(acos(clampf(n2.dot((pos2).normalized()), -1.0, 1.0)))
		if slope2 > scatter_max_slope_deg:
			continue
		var altitude2 := pos2.length() - radius
		if altitude2 > scatter_max_altitude:
			continue
		var s := scatter_rng.randf_range(pebble_scale_range.x, pebble_scale_range.y)
		# Slight non-uniform scale for visual variety
		var sx := s * scatter_rng.randf_range(0.8, 1.2)
		var sy := s * scatter_rng.randf_range(0.8, 1.2)
		var sz := s * scatter_rng.randf_range(0.8, 1.2)
		# Align to surface normal
		var z2 := n2
		var x2 := z2.cross(Vector3(0, 1, 0))
		if x2.length() < 0.01:
			x2 = z2.cross(Vector3(1, 0, 0))
		x2 = x2.normalized()
		var y2 := z2.cross(x2).normalized()
		var basis2 := Basis()
		basis2.x = x2 * sx
		basis2.y = y2 * sy
		basis2.z = z2 * sz
		pebbles_mmi.multimesh.set_instance_transform(idx_p, Transform3D(basis2, pos2))
		idx_p += 1
		if idx_p >= pebble_count:
			break
	# Clear rest if fewer placed
	while idx_p < pebble_count:
		pebbles_mmi.multimesh.set_instance_transform(idx_p, Transform3D())
		idx_p += 1

# Setter functions for live parameter updates in editor
func _regenerate_in_editor_button(_value: bool):
	if Engine.is_editor_hint():
		print("Regenerating planet in editor...")
		_configure_noise_instances()
		var axis: Vector3 = Vector3(0.42, 0.86, 0.27).normalized()
		range_basis = Basis(axis, deg_to_rad(range_rotation_deg))
		generate_planet()
		if use_mesh_atmosphere:
			_create_or_update_atmosphere()
		print("Regeneration complete.")

func _configure_noise_instances():
	# Configure noise 
	noise.seed = randi()
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.frequency = detail_frequency
	noise.fractal_octaves = detail_octaves
	noise.fractal_lacunarity = detail_lacunarity
	noise.fractal_gain = detail_gain
	
	noise_base.seed = randi() + 1337
	noise_base.noise_type = FastNoiseLite.TYPE_PERLIN
	noise_base.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	noise_base.frequency = base_frequency
	noise_base.fractal_octaves = base_octaves
	noise_base.fractal_lacunarity = base_lacunarity
	noise_base.fractal_gain = base_gain
	
	noise_micro.seed = randi() + 4242
	noise_micro.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise_micro.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise_micro.frequency = micro_frequency
	noise_micro.fractal_octaves = micro_octaves
	noise_micro.fractal_lacunarity = micro_lacunarity
	noise_micro.fractal_gain = micro_gain
