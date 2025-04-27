class_name MainEngine

extends ShipComponent

@export var force_magnitude: float = 100.0

@onready var exhaust: GPUParticles3D = $GPUParticles3D


func _init() -> void:
	memory_size = 1

func run_logic(delta):
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
			force -= global_transform.basis.z * force_magnitude * throttle_percentage
			
		# Update exhaust particles based on engine activity
		exhaust.emitting = engine_active
		
		# Apply force at the position of the engine relative to the parent's center
		var position_force = global_position - parent.global_position
		
		parent.apply_force(
			force, # Force direction in global coordinates
			position_force # Force position relative to parent's center
		)