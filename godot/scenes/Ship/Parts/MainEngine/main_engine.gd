class_name MainEngine

extends ShipComponent

@export var force_magnitude: float = 100.0

@onready var exhaust: GPUParticles3D = $GPUParticles3D


func _init() -> void:
	memory_size = 1

func run_logic(_delta):
	var buffer = addressBuffer[0]

	exhaust.emitting = buffer & 0b0001

	# Find the parent RigidBody
	var parent = get_parent()
	if parent and parent is RigidBody3D:
		var force = Vector3.ZERO
		# Use the entire buffer value as throttle (0-255 range)
		var throttle_value = buffer
		
		# Check if engine is active (buffer is not 0)
		var engine_active = buffer > 0
		
		# Map the throttle range 0-255 to 0-100%
		var throttle_percentage = float(throttle_value) / 255.0
		
		# Apply force in the forward direction based on throttle percentage
		if engine_active:
			force += global_transform.basis.y * force_magnitude * throttle_percentage
			
		# Update exhaust particles based on engine activity
		exhaust.emitting = engine_active
		
		# Apply force through center of mass to avoid unwanted torque
		parent.apply_central_force(force)
