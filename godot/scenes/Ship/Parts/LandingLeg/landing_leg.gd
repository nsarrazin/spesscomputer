extends Node3D

@export var stiffness: float = 2500.0
@export var damping: float = 300.0
@export var friction: float = 1.0

@onready var raycast: RayCast3D = $RayCast
@onready var mesh: MeshInstance3D = $Mesh

var ship_body: RigidBody3D
var rest_length: float

func _ready() -> void:
	# The parent of the LandingLeg should be the Ship (RigidBody3D)
	ship_body = get_parent() as RigidBody3D
	if not ship_body:
		push_error("LandingLeg must be a child of a RigidBody3D.")
		return
	rest_length = - raycast.target_position.y


func _physics_process(delta: float) -> void:
	if not ship_body:
		return

	var force: Vector3 = Vector3.ZERO
	if raycast.is_colliding():
		var collider = raycast.get_collider()
		var collision_point: Vector3 = raycast.get_collision_point()
		var collision_normal: Vector3 = raycast.get_collision_normal()

		# The raycast is in global space, so the distance is just the distance.
		var distance = global_position.distance_to(collision_point)
		var compression_distance = rest_length - distance

		if compression_distance > 0:
			# Spring force
			var spring_force_magnitude: float = stiffness * compression_distance
			
			# Damping force
			var leg_world_velocity = ship_body.linear_velocity + ship_body.angular_velocity.cross(global_transform.origin - ship_body.global_transform.origin)
			var leg_up_dir = global_transform.basis.y
			var velocity_along_leg: float = leg_world_velocity.dot(leg_up_dir)
			var damping_force_magnitude: float = damping * velocity_along_leg
			
			var total_force_magnitude = spring_force_magnitude - damping_force_magnitude
			var up_force = leg_up_dir * total_force_magnitude

			# Friction force
			var tangential_velocity = leg_world_velocity - leg_world_velocity.project(collision_normal)
			var friction_force = Vector3.ZERO
			if tangential_velocity.length_squared() > 0.001:
				var max_friction = total_force_magnitude * friction
				var friction_magnitude = min(max_friction, tangential_velocity.length() * ship_body.mass / delta)
				friction_force = - tangential_velocity.normalized() * friction_magnitude

			var total_force = up_force + friction_force
			
			# Apply force at the leg's position relative to the ship's center of mass
			ship_body.apply_force(total_force, global_transform.origin - ship_body.global_transform.origin)

			# Visual compression
			var compression_ratio = (rest_length - compression_distance) / rest_length
			mesh.scale.y = compression_ratio
	else:
		# Reset visual compression when not on ground
		mesh.scale.y = 1.0
