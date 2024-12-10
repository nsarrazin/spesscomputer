extends Node3D

@onready var mesh_instance = $MeshInstance3D
@onready var collision_shape_instance = $CollisionShape3D

@export var radius: float = 250.0
@export var rotation_speed: float = 0.05
@export var gravitational_pull: float = 1e9

var noise = FastNoiseLite.new()
var surface_tool = SurfaceTool.new()
var mesh = ArrayMesh.new()

func _ready() -> void:
	# Configure noise
	noise.seed = randi()
	noise.frequency = 0.1
	
	# Generate planet mesh
	generate_planet_mesh()
	
	# Set up collision shape to match mesh
	var collision_shape = ConcavePolygonShape3D.new()
	collision_shape.set_faces(mesh.get_faces())
	collision_shape_instance.shape = collision_shape

func generate_planet_mesh() -> void:
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	# Generate sphere vertices with noise displacement
	var segments = 32
	for lat in range(segments):
		var theta = lat * PI / segments
		for lon in range(segments * 2):
			var phi = lon * PI * 2 / (segments * 2)
			
			# Calculate vertices for two triangles forming a quad
			var points = []
			var uvs = []
			
			# Calculate 4 corner points of the quad
			for i in range(4):
				var p_lat = theta + (PI / segments) * (i / 2)
				var p_lon = phi + (PI * 2 / (segments * 2)) * (i % 2)
				
				var x = sin(p_lat) * cos(p_lon)
				var y = cos(p_lat)
				var z = sin(p_lat) * sin(p_lon)
				
				var point = Vector3(x, y, z)
				var noise_val = noise.get_noise_3d(point.x, point.y, point.z) * 250
				point = point * (radius + noise_val)
				points.append(point)
				
				uvs.append(Vector2(p_lon / (PI * 2), p_lat / PI))
			
			# Create two triangles from the quad
			# First triangle
			surface_tool.set_uv(uvs[0])
			surface_tool.add_vertex(points[0])
			
			surface_tool.set_uv(uvs[1])
			surface_tool.add_vertex(points[1])
			
			surface_tool.set_uv(uvs[2])
			surface_tool.add_vertex(points[2])
			
			# Second triangle
			surface_tool.set_uv(uvs[1])
			surface_tool.add_vertex(points[1])
			
			surface_tool.set_uv(uvs[3])
			surface_tool.add_vertex(points[3])
			
			surface_tool.set_uv(uvs[2])
			surface_tool.add_vertex(points[2])
	
	surface_tool.generate_normals() # Generate smooth normals after all vertices
	surface_tool.index()
	mesh = surface_tool.commit()
	
	# Create and apply material
	var material = StandardMaterial3D.new()
	material.albedo_color = Color(0.7, 0.5, 0.3) # Brownish base color
	material.roughness = 0.8
	material.metallic = 0.1
	
	# You can also load a texture from a file:
	# var texture = load("res://path_to_your_texture.png")
	# material.albedo_texture = texture
	
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
