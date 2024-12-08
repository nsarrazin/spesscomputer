extends RigidBody3D

@export var gravity_strength: float = 100.0

@onready var thruster = $Thruster

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	# Calculate initial velocity for an elliptical orbit with e=0.5
	# Using vis-viva equation and orbital mechanics
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

# Called every physics frame to apply gravity
func _physics_process(delta: float) -> void:
	# Calculate direction to center (0,0,0)
	var direction_to_center = -global_position.normalized()
	
	# Apply force towards center
	apply_central_force(direction_to_center * gravity_strength * mass)
	
	# Handle thruster input
	if Input.is_action_pressed("ui_select"): # Spacebar
		if thruster:
			thruster.fire()
	else:
		if thruster:
			thruster.stop()
