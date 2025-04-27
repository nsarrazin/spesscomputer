extends ShipComponent


func _init() -> void:
	memory_size = 2

func run_logic(_delta: float) -> void:
	var buffer = addressBuffer[0]

	var clamped_buffer = clamp(buffer, -127, 127)
	var mapped_angle = float(clamped_buffer) / 127.0 * 90.0
	
	# Apply rotation to the solar panel
	rotation.z = deg_to_rad(mapped_angle)

	# Set the generated power in the second memory address
	addressBuffer[1] = 255 # TODO: actually calculate power based on angle and sun intensity
