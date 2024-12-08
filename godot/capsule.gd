extends RigidBody3D

@export var gravity_strength: float = 100.0
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	set_initial_speed()

# Called every physics frame to apply gravity
func _physics_process(delta: float) -> void:
	# Calculate direction to center (0,0,0)
	var direction_to_center = -global_position.normalized()
	
	# Apply force towards center
	apply_central_force(direction_to_center * gravity_strength * mass)


func set_initial_speed() -> void:
	var r = global_position.length()
	var mu = gravity_strength # gravitational parameter
	
	# Semi-major axis a = r/(1-e) at periapsis
	var e = 0.5 # eccentricity
	var a = r/(1-e)
	
	# Calculate velocity magnitude using vis-viva equation
	var v = sqrt(mu * (2/r - 1/a))
	
	# Set velocity perpendicular to radius vector for circular-like orbit
	var orbit_direction = global_position.cross(Vector3.UP).normalized()
	linear_velocity = orbit_direction * v * 1000
