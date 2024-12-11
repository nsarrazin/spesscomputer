extends RigidBody3D


@export var planet_node: Node3D = null
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	set_initial_speed()

func set_initial_speed() -> void:
	if not planet_node:
		return
		
	# Get gravitational parameter and radius vector
	var mu = planet_node.gravitational_pull
	var radius_vector = global_position - planet_node.global_position
	var r = radius_vector.length()
	
	# Semi-major axis a = r/(1-e) at periapsis
	var e = 0.5 # eccentricity
	var a = r/(1-e)
	
	# Calculate velocity magnitude using vis-viva equation
	var v = sqrt(mu * (2/r - 1/a))
	
	var orbit_direction = radius_vector.cross(Vector3.UP).normalized()
	linear_velocity = orbit_direction * v
