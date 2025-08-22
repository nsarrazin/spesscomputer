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
	
	# Base Mars-like palette by height
	var base: Color = mars_height_to_color(t)
	
	# Subtle color variation (towards darker tint rather than white)
	var n: float = noise.get_noise_3d(dir.x * 120.0, dir.y * 120.0, dir.z * 120.0)
	var var_amt: float = 0.04 * (0.5 + 0.5 * n)
	base = base.lerp(Color(0.10, 0.05, 0.04), var_amt)
	
	# Polar caps: narrower and less bright
	var snow_lat_mask: float = smoothstep(0.84, 0.98, lat)
	var snow_height_mask: float = smoothstep(0.65, 0.90, t)
	var snow_mix: float = clampf(0.6 * snow_lat_mask * maxf(0.35, snow_height_mask), 0.0, 1.0)
	var snow_color: Color = Color(0.92, 0.94, 0.96)
	return base.lerp(snow_color, snow_mix)

func mars_height_to_color(t: float) -> Color:
	var low = Color(0.28, 0.12, 0.08) # dark basaltic red-brown
	var mid = Color(0.58, 0.30, 0.16) # rusty orange
	var high = Color(0.86, 0.62, 0.40) # light dusty tan
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
	return material

func _physics_process(delta: float) -> void:
	if not initialized:
		return
		
	# Rotate planet
	rotate_y(rotation_speed * delta)
	
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
