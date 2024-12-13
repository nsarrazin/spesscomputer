extends Node3D

@onready var mesh_instance = $MeshInstance3D
@onready var collision_shape_instance = $CollisionShape3D
@onready var ocean_mesh_instance = $OceanMeshInstance3D

@export var radius: float = 250.0
@export var rotation_speed: float = 0.05
@export var gravitational_pull: float = 1e9

var noise = FastNoiseLite.new()
var noise2 = FastNoiseLite.new() 
var noise3 = FastNoiseLite.new()
var noise4 = FastNoiseLite.new()
var surface_tool = SurfaceTool.new()
var ocean_surface_tool = SurfaceTool.new()
var mesh = ArrayMesh.new()
var ocean_mesh = ArrayMesh.new()

func _ready() -> void:
	# Configure noise layers
	noise.seed = randi()
	noise.frequency = 0.0001*radius
	
	noise2.seed = randi()
	noise2.frequency = 0.0005*radius
	
	noise3.seed = randi()
	noise3.frequency = 0.001*radius

	noise4.seed = randi()
	noise4.frequency = 0.01*radius
	
	# Generate planet mesh
	generate_planet_mesh()
	generate_ocean_mesh()
	
	# Set up collision shape to match mesh
	var collision_shape = ConcavePolygonShape3D.new()
	collision_shape.set_faces(mesh.get_faces())
	collision_shape_instance.shape = collision_shape

func generate_ocean_mesh() -> void:
	ocean_surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	# Generate smooth sphere for ocean
	var segments = 32
	for lat in range(segments + 1):  # Add one more to close the sphere
		var theta = lat * PI / segments
		for lon in range(segments * 2 + 1):  # Add one more to wrap around
			var phi = lon * PI * 2 / (segments * 2)
			
			var x = sin(theta) * cos(phi)
			var y = cos(theta)
			var z = sin(theta) * sin(phi)
			
			var point = Vector3(x, y, z) * (radius + 5.0)
			var uv = Vector2(float(lon) / (segments * 2), float(lat) / segments)
			
			ocean_surface_tool.set_uv(uv)
			ocean_surface_tool.add_vertex(point)
			
			# Create triangles (except for last row and column)
			if lat < segments and lon < segments * 2:
				var i = lat * (segments * 2 + 1) + lon
				
				# First triangle
				ocean_surface_tool.add_index(i)
				ocean_surface_tool.add_index(i + (segments * 2 + 1))
				ocean_surface_tool.add_index(i + 1)
				
				# Second triangle
				ocean_surface_tool.add_index(i + 1)
				ocean_surface_tool.add_index(i + (segments * 2 + 1))
				ocean_surface_tool.add_index(i + (segments * 2 + 2))
	
	ocean_surface_tool.generate_normals()
	ocean_surface_tool.index()
	ocean_mesh = ocean_surface_tool.commit()
	
	# Create transparent ocean material
	var ocean_material = StandardMaterial3D.new()
	ocean_material.albedo_color = Color(0.2, 0.5, 0.8, 0.9)
	ocean_material.roughness = 0.3
	ocean_material.metallic = 0.3
	ocean_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	
	ocean_mesh_instance.mesh = ocean_mesh
	ocean_mesh_instance.material_override = ocean_material

func generate_planet_mesh() -> void:
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	# Generate sphere vertices with multiple noise layers
	var segments = 32
	var vertices = []
	var uvs = []
	
	# Generate vertices first
	for lat in range(segments + 1):  # Add one more to close the sphere
		var theta = lat * PI / segments
		for lon in range(segments * 2 + 1):  # Add one more to wrap around
			var phi = lon * PI * 2 / (segments * 2)
			
			var x = sin(theta) * cos(phi)
			var y = cos(theta)
			var z = sin(theta) * sin(phi)
			
			var point = Vector3(x, y, z)
			
			# Combine multiple noise layers, scaled by radius
			var noise_scale = radius * 0.2
			var noise_val = noise.get_noise_3d(point.x, point.y, point.z) * noise_scale
			noise_val += noise2.get_noise_3d(point.x * 2, point.y * 2, point.z * 2) * (noise_scale * 0.1)
			noise_val += noise3.get_noise_3d(point.x * 4, point.y * 4, point.z * 4) * (noise_scale * 0.01)

			# Add mountain ranges using clipped noise
			var mountain_noise = noise4.get_noise_3d(point.x/100, point.y/100, point.z/100)
			# Clip low values and offset to create distinct ranges
			if mountain_noise <= 0.1:
				mountain_noise = 0
			
			point = point * (radius + noise_val + mountain_noise)

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
	
	# Create and apply material
	var material = StandardMaterial3D.new()
	material.albedo_color = Color(0.7, 0.5, 0.3)
	material.roughness = 0.8
	material.metallic = 0.1
	
	mesh_instance.mesh = mesh
	mesh_instance.material_override = material

func _physics_process(delta: float) -> void:
	# Rotate planet
	rotate_y(rotation_speed * delta)
	
	# Apply gravitational pull to nearby bodies
	for body in get_tree().get_nodes_in_group("affected_by_gravity"):
		if body is RigidBody3D:
			# Check if body is ready and active
			if not is_instance_valid(body) or body.freeze:
				continue
				
			var direction = global_position - body.global_position
			var distance = direction.length()
			
			# Calculate force with more controlled magnitude
			var force_magnitude = (gravitational_pull * body.mass) / (distance * distance)
			var force = direction.normalized() * force_magnitude
			
			# Apply force directly to the body's physics state
			body.apply_central_force(force)
