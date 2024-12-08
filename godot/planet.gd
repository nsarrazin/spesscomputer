extends RigidBody3D

@export var rotation_speed: float = 0.5

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	# Fix position at origin
	global_position = Vector3.ZERO
	# Lock all movement except Y rotation
	freeze = true
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	# Rotate around Y axis
	rotate_y(rotation_speed * delta)
