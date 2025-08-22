extends Node3D

@onready var mesh_instance = $MeshInstance3D
@onready var collision_shape_instance = $CollisionShape3D

@export var radius: float = 200000.0
@export var rotation_speed: float = 0.005
@export var gravitational_pull: float = 3e9
@export var segments: int = 96

# Terrain noise controls
@export var relief_scale: float = 0.06
@export var base_frequency: float = 0.08
@export var base_octaves: int = 4
@export var base_lacunarity: float = 2.0
@export var base_gain: float = 0.45
@export var detail_frequency: float = 2.5
@export var detail_octaves: int = 4
@export var detail_lacunarity: float = 2.2
@export var detail_gain: float = 0.48
@export var micro_frequency: float = 6.0
@export var micro_octaves: int = 3
@export var micro_lacunarity: float = 2.4
@export var micro_gain: float = 0.52
@export var micro_strength: float = 0.25

# Feature shaping controls
@export var terrace_steps: int = 7
@export var terrace_strength: float = 0.35
@export var range_strength: float = 0.35
@export var range_frequency_main: float = 2.6
@export var range_anisotropy: float = 0.35
@export var range_rotation_deg: float = 47.0

# Mesh smoothing/triangulation controls
@export var smooth_iterations: int = 1
@export var smooth_lambda: float = 0.5
@export var alternate_quad_diagonals: bool = true

# Atmosphere controls
@export var atmosphere_height_scale: float = 0.3 # fraction of radius
@export var atmosphere_intensity: float = 0.25
@export var atmosphere_mie_intensity: float = 0.05
@export var atmosphere_g: float = 0.8 # mie anisotropy
@export var atmosphere_color: Color = Color(0.55, 0.75, 1.0)
@export var atmosphere_mie_color: Color = Color(1.0, 0.95, 0.9)
@export var atmosphere_segments: int = 64
@export var use_mesh_atmosphere: bool = false

var noise: FastNoiseLite = FastNoiseLite.new() # detail
var noise_base: FastNoiseLite = FastNoiseLite.new()
var noise_micro: FastNoiseLite = FastNoiseLite.new()
var surface_tool = SurfaceTool.new()
var mesh = ArrayMesh.new()
var max_terrain_height = 0.0
var vertices: Array[Vector3] = []
var initialized = false
var range_basis: Basis

# Collision nodes created/managed at runtime
var landing_static_body: StaticBody3D
var landing_collision_shape: CollisionShape3D

# Atmosphere nodes/material
var atmosphere_mesh_instance: MeshInstance3D
var atmosphere_material: ShaderMaterial

func _ready() -> void:
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
	
	initialized = true

func generate_planet() -> void:
	print("Generating planet mesh...")

	generate_planet_mesh()
	

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
					surface_tool.set_uv(uvs[i0])
					surface_tool.set_color(get_color_for_vertex_index(i0))
					surface_tool.set_normal(get_normal_for_vertex_index(i0))
					surface_tool.add_vertex(vertices[i0])
					surface_tool.set_uv(uvs[i2])
					surface_tool.set_color(get_color_for_vertex_index(i2))
					surface_tool.set_normal(get_normal_for_vertex_index(i2))
					surface_tool.add_vertex(vertices[i2])
					surface_tool.set_uv(uvs[i3])
					surface_tool.set_color(get_color_for_vertex_index(i3))
					surface_tool.set_normal(get_normal_for_vertex_index(i3))
					surface_tool.add_vertex(vertices[i3])
					# Second triangle i0, i3, i1
					surface_tool.set_uv(uvs[i0])
					surface_tool.set_color(get_color_for_vertex_index(i0))
					surface_tool.set_normal(get_normal_for_vertex_index(i0))
					surface_tool.add_vertex(vertices[i0])
					surface_tool.set_uv(uvs[i3])
					surface_tool.set_color(get_color_for_vertex_index(i3))
					surface_tool.set_normal(get_normal_for_vertex_index(i3))
					surface_tool.add_vertex(vertices[i3])
					surface_tool.set_uv(uvs[i1])
					surface_tool.set_color(get_color_for_vertex_index(i1))
					surface_tool.set_normal(get_normal_for_vertex_index(i1))
					surface_tool.add_vertex(vertices[i1])
				else:
					# Diagonal (i1-i2)
					surface_tool.set_uv(uvs[i0])
					surface_tool.set_color(get_color_for_vertex_index(i0))
					surface_tool.set_normal(get_normal_for_vertex_index(i0))
					surface_tool.add_vertex(vertices[i0])
					surface_tool.set_uv(uvs[i2])
					surface_tool.set_color(get_color_for_vertex_index(i2))
					surface_tool.set_normal(get_normal_for_vertex_index(i2))
					surface_tool.add_vertex(vertices[i2])
					surface_tool.set_uv(uvs[i1])
					surface_tool.set_color(get_color_for_vertex_index(i1))
					surface_tool.set_normal(get_normal_for_vertex_index(i1))
					surface_tool.add_vertex(vertices[i1])
					# Second triangle i1, i2, i3
					surface_tool.set_uv(uvs[i1])
					surface_tool.set_color(get_color_for_vertex_index(i1))
					surface_tool.set_normal(get_normal_for_vertex_index(i1))
					surface_tool.add_vertex(vertices[i1])
					surface_tool.set_uv(uvs[i2])
					surface_tool.set_color(get_color_for_vertex_index(i2))
					surface_tool.set_normal(get_normal_for_vertex_index(i2))
					surface_tool.add_vertex(vertices[i2])
					surface_tool.set_uv(uvs[i3])
					surface_tool.set_color(get_color_for_vertex_index(i3))
					surface_tool.set_normal(get_normal_for_vertex_index(i3))
					surface_tool.add_vertex(vertices[i3])
	
	surface_tool.index()
	mesh = surface_tool.commit()
	
	# Build/update trimesh collision for landing
	_update_collision_from_mesh()
	
	# Create and apply lunar material
	var material = create_planet_material()
	
	mesh_instance.mesh = mesh
	mesh_instance.material_override = material


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


# Function to calculate terrain height at a point
func calculate_terrain_height(point: Vector3) -> float:
	# Work in unit-sphere space for sampling
	var p: Vector3 = point.normalized()
	
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
	
	# Terracing for plateaus
	var q: float = clampf(0.5 * (combined + 1.0), 0.0, 1.0)
	var steps: float = float(max(1, terrace_steps))
	var terr_q: float = floor(q * steps) / steps
	var terr_centered: float = terr_q * 2.0 - 1.0
	combined = lerpf(combined, terr_centered, clampf(terrace_strength, 0.0, 1.0))
	
	# Scale to world amplitude
	return combined * (radius * relief_scale)

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
	
	# Ice caps: latitude-driven, smoother and more consistent
	var snow_lat_mask: float = smoothstep(0.86, 0.98, lat)
	var snow_mix: float = clampf(pow(snow_lat_mask, 1.7) * 0.5, 0.0, 0.6)
	var snow_color: Color = Color(0.82, 0.88, 0.92)
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

func _physics_process(delta: float) -> void:
	if not initialized:
		return
		
	# Rotate planet
	rotate_y(rotation_speed * delta)
	
	# Keep platform motion in sync so landed bodies stick to surface
	if is_instance_valid(landing_static_body):
		landing_static_body.constant_angular_velocity = Vector3(0.0, rotation_speed, 0.0)
	
	# Update atmosphere params each frame (sun direction may change)
	if use_mesh_atmosphere:
		_update_atmosphere_params()
	else:
		_update_surface_atmo_params()
	
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
		sm.rings = max(12, atmosphere_segments / 2)
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
	var atm_radius: float = radius + shell_height
	atmosphere_material.set_shader_parameter("planet_radius", radius)
	atmosphere_material.set_shader_parameter("atmosphere_height", shell_height)
	atmosphere_material.set_shader_parameter("intensity_rayleigh", atmosphere_intensity)
	atmosphere_material.set_shader_parameter("intensity_mie", atmosphere_mie_intensity)
	atmosphere_material.set_shader_parameter("g", clampf(atmosphere_g, -0.99, 0.99))
	atmosphere_material.set_shader_parameter("rayleigh_color", atmosphere_color)
	atmosphere_material.set_shader_parameter("mie_color", atmosphere_mie_color)
	# Sun direction in world
	var light := _get_directional_light()
	var sun_dir_world: Vector3 = Vector3(0, -1, 0)
	if light:
		# DirectionalLight points towards -Z in its local; light direction is -basis.z
		sun_dir_world = - (light.global_transform.basis.z).normalized()
	# Convert to planet local/object space
	var sun_dir_obj: Vector3 = (global_transform.basis.inverse() * sun_dir_world).normalized()
	atmosphere_material.set_shader_parameter("sun_dir_object", sun_dir_obj)
	# Visual tweaks
	atmosphere_material.set_shader_parameter("outer_radius", atm_radius)
	# Camera position in planet object space
	var cam := get_viewport().get_camera_3d()
	if cam:
		var cam_obj: Vector3 = to_local(cam.global_transform.origin)
		atmosphere_material.set_shader_parameter("camera_pos_object", cam_obj)

func _update_surface_atmo_params() -> void:
	var smat := mesh_instance.material_override as ShaderMaterial
	if smat == null:
		return
	smat.set_shader_parameter("atmo_height", radius * atmosphere_height_scale)
	smat.set_shader_parameter("atmo_intensity_rayleigh", atmosphere_intensity)
	smat.set_shader_parameter("atmo_intensity_mie", atmosphere_mie_intensity)
	smat.set_shader_parameter("atmo_g", clampf(atmosphere_g, -0.99, 0.99))
	smat.set_shader_parameter("atmo_rayleigh_color", atmosphere_color)
	smat.set_shader_parameter("atmo_mie_color", atmosphere_mie_color)
	# Sun direction
	var light := _get_directional_light()
	var sun_dir_world: Vector3 = Vector3(0, -1, 0)
	if light:
		sun_dir_world = - (light.global_transform.basis.z).normalized()
	var sun_dir_obj: Vector3 = (global_transform.basis.inverse() * sun_dir_world).normalized()
	smat.set_shader_parameter("atmo_sun_dir_object", sun_dir_obj)
	# Camera pos in object
	var cam := get_viewport().get_camera_3d()
	if cam:
		var cam_obj: Vector3 = to_local(cam.global_transform.origin)
		smat.set_shader_parameter("atmo_camera_pos_object", cam_obj)
