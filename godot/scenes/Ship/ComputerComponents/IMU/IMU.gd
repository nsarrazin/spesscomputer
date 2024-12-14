extends ShipComponent

var rigid_body: RigidBody3D

const MAX_ACCEL: float = 25.0
const MAX_ANG_VEL: float = 10.0

var v0: Vector3

func _init() -> void:
	memory_size = 6

func _ready() -> void:
	var parent = get_parent()
	while parent and not parent is RigidBody3D:
		parent = parent.get_parent()
	
	if parent is RigidBody3D:
		rigid_body = parent


func run_logic(delta: float) -> void:
	var acceleration = (rigid_body.linear_velocity - v0) / delta
	v0 = rigid_body.linear_velocity

	addressBuffer[0] = round(clamp(remap(acceleration.x, -MAX_ACCEL, MAX_ACCEL, 0, 255), 0, 255))
	addressBuffer[1] = round(clamp(remap(acceleration.y, -MAX_ACCEL, MAX_ACCEL, 0, 255), 0, 255))
	addressBuffer[2] = round(clamp(remap(acceleration.z, -MAX_ACCEL, MAX_ACCEL, 0, 255), 0, 255))


	addressBuffer[3] = round(clamp(remap(rigid_body.angular_velocity.x, -MAX_ANG_VEL, MAX_ANG_VEL, 0, 255), 0, 255))
	addressBuffer[4] = round(clamp(remap(rigid_body.angular_velocity.y, -MAX_ANG_VEL, MAX_ANG_VEL, 0, 255), 0, 255))
	addressBuffer[5] = round(clamp(remap(rigid_body.angular_velocity.z, -MAX_ANG_VEL, MAX_ANG_VEL, 0, 255), 0, 255))