extends ShipComponent

var rigid_body: RigidBody3D
var planet_node: Node3D

const MAX_ACCEL: float = 25.0
const MAX_ANG_VEL: float = 10.0

var v0: Vector3
var acceleration: Vector3

func _init() -> void:
	memory_size = 6

func _ready() -> void:
	var parent = get_parent()
	while parent and not parent is RigidBody3D:
		parent = parent.get_parent()
	
	if parent is RigidBody3D:
		rigid_body = parent
		if rigid_body:
			v0 = rigid_body.linear_velocity
			if rigid_body.has_method("get") and rigid_body.get("planet_node"):
				planet_node = rigid_body.get("planet_node")


func _physics_process(delta: float) -> void:
	if rigid_body and delta > 0:
		var inertial_acceleration = (rigid_body.linear_velocity - v0) / delta
		v0 = rigid_body.linear_velocity
		
		var gravity_acceleration = Vector3.ZERO
		if planet_node:
			var direction = planet_node.global_position - rigid_body.global_position
			var distance_sq = direction.length_squared()
			if distance_sq > 0.0:
				var gravitational_pull = planet_node.get("gravitational_pull")
				var force_magnitude = gravitational_pull / distance_sq
				gravity_acceleration = direction.normalized() * force_magnitude
		
		var proper_acceleration_world = inertial_acceleration - gravity_acceleration
		
		acceleration = rigid_body.global_transform.basis.inverse() * proper_acceleration_world
	
	super._physics_process(delta)


func run_logic(_delta: float) -> void:
	addressBuffer[0] = round(clamp(remap(acceleration.x, -MAX_ACCEL, MAX_ACCEL, 0, 255), 0, 255))
	addressBuffer[1] = round(clamp(remap(acceleration.y, -MAX_ACCEL, MAX_ACCEL, 0, 255), 0, 255))
	addressBuffer[2] = round(clamp(remap(acceleration.z, -MAX_ACCEL, MAX_ACCEL, 0, 255), 0, 255))


	addressBuffer[3] = round(clamp(remap(rigid_body.angular_velocity.x, -MAX_ANG_VEL, MAX_ANG_VEL, 0, 255), 0, 255))
	addressBuffer[4] = round(clamp(remap(rigid_body.angular_velocity.y, -MAX_ANG_VEL, MAX_ANG_VEL, 0, 255), 0, 255))
	addressBuffer[5] = round(clamp(remap(rigid_body.angular_velocity.z, -MAX_ANG_VEL, MAX_ANG_VEL, 0, 255), 0, 255))
