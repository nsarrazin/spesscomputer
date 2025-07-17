extends Node3D

@onready var mesh_instance = $MeshInstance3D
@onready var collision_shape_instance = $CollisionShape3D

@export var radius: float = 200000.0
@export var rotation_speed: float = 0.005
@export var gravitational_pull: float = 3e9

var noise = FastNoiseLite.new()
var surface_tool = SurfaceTool.new()
var mesh = ArrayMesh.new()
var max_terrain_height = 0.0
var vertices = []
var initialized = false

func _ready() -> void:
	# Configure noise 
	noise.seed = randi()
	noise.frequency = 0.05 * radius
	noise.fractal_octaves = 3
	noise.fractal_gain = 0.5
	
	# Optimize global physics
	Engine.physics_ticks_per_second = 30
	Engine.max_physics_steps_per_frame = 4
	
	# Generate mesh with collision
	generate_planet()
	
	initialized = true

func generate_planet() -> void:
	print("Generating planet mesh...")

	generate_planet_mesh()
	

func generate_planet_mesh() -> void:
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	# Generate sphere vertices
	var segments = 32
	vertices.clear()
	var uvs = []
	
	# Reset height tracker
	max_terrain_height = 0.0
	
	# Generate vertices first
	for lat in range(segments + 1):
		var theta = lat * PI / segments
		var sin_theta = sin(theta)
		var cos_theta = cos(theta)
		
		for lon in range(segments * 2 + 1):
			var phi = lon * PI * 2 / (segments * 2)
			var sin_phi = sin(phi)
			var cos_phi = cos(phi)
			
			var x = sin_theta * cos_phi
			var y = cos_theta
			var z = sin_theta * sin_phi
			
			var point = Vector3(x, y, z)
			
			# Calculate height at this point
			var height = calculate_terrain_height(point)
			
			# Track maximum terrain height
			if abs(height) > max_terrain_height:
				max_terrain_height = abs(height)

			point = point * (radius + height)
			vertices.append(point)
			
			var uv = Vector2(float(lon) / (segments * 2), float(lat) / segments)
			uvs.append(uv)

	# Create triangles
	for lat in range(segments):
		for lon in range(segments * 2):
			var i = lat * (segments * 2 + 1) + lon
			
			# First triangle
			surface_tool.set_uv(uvs[i])
			surface_tool.add_vertex(vertices[i])
			
			surface_tool.set_uv(uvs[i + (segments * 2 + 1)])
			surface_tool.add_vertex(vertices[i + (segments * 2 + 1)])
			
			surface_tool.set_uv(uvs[i + 1])
			surface_tool.add_vertex(vertices[i + 1])
			
			# Second triangle
			surface_tool.set_uv(uvs[i + 1])
			surface_tool.add_vertex(vertices[i + 1])
			
			surface_tool.set_uv(uvs[i + (segments * 2 + 1)])
			surface_tool.add_vertex(vertices[i + (segments * 2 + 1)])
			
			surface_tool.set_uv(uvs[i + (segments * 2 + 2)])
			surface_tool.add_vertex(vertices[i + (segments * 2 + 2)])
	
	surface_tool.generate_normals()
	surface_tool.index()
	mesh = surface_tool.commit()
	
	# Create and apply lunar material
	var material = create_lunar_material()
	
	mesh_instance.mesh = mesh
	mesh_instance.material_override = material


# Function to calculate terrain height at a point
func calculate_terrain_height(point: Vector3) -> float:
	var noise_scale = radius * 0.03
	var noise_val = noise.get_noise_3d(point.x, point.y, point.z) * noise_scale
	return noise_val

# Get height at a specific point on planet
func get_height_at_position(global_pos: Vector3) -> float:
	var local_pos = global_transform.affine_inverse() * global_pos
	var direction = local_pos.normalized()
	
	# Calculate the height using noise
	var height = calculate_terrain_height(direction)
	
	return radius + height

# Creates a realistic moon material
func create_lunar_material() -> StandardMaterial3D:
	var material = StandardMaterial3D.new()
	
	# Simple dark grey color
	material.albedo_color = Color(0.2, 0.2, 0.21)
	
	# Create a basic noise texture for minimal variation
	var albedo_noise = NoiseTexture2D.new()
	albedo_noise.seamless = true
	albedo_noise.width = 256
	albedo_noise.height = 256
	
	var noise_for_albedo = FastNoiseLite.new()
	noise_for_albedo.seed = randi()
	noise_for_albedo.frequency = 0.005
	noise_for_albedo.fractal_octaves = 1
	albedo_noise.noise = noise_for_albedo
	
	material.albedo_texture = albedo_noise
	
	# Simple roughness settings
	material.roughness = 0.95
	material.metallic = 0.0
	material.specular = 0.1
	
	# Disable other features for simplicity
	material.normal_enabled = false
	material.ao_enabled = false
	material.heightmap_enabled = false
	
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
