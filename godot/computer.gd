extends Node3D

var max_abs_velocity: float = 1000.0
@export var key: String = "computer";
@onready var array = RedisArray.create(key)

var buffer: Array[int] = []
var control_thruster_nodes: Array[Thruster] = []
var thruster: Thruster

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	array.set_field([0,0,0,0,0,0,0,0])

	for child in get_parent().get_children():
		if child.name.contains("Thruster") and child.name != "Thruster":
			control_thruster_nodes.append(child)
		elif child.name.contains("Thruster"):
			thruster = child

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	var field = array.get_field()

	if field.size() == 0:
		array.set_field([0,0,0,0,0,0,0,0])
		return
		
	var main_thruster_strength = field[0]
	var control_thruster_mask = field[1]
	
	if main_thruster_strength > 0:
		thruster.fire()
	else:
		thruster.stop()


	# Check each bit in control_thrusters bitmask and fire corresponding thrusters
	for i in range(8):
		var thruster_on = (control_thruster_mask & (1 << i)) != 0
		if thruster_on:
			control_thruster_nodes[i].fire()
		else:
			control_thruster_nodes[i].stop()


	# Get acceleration and orientation from parent rigid body
	var velocity: Vector3 = Vector3.ZERO
	var orientation_parent: Quaternion = Quaternion.IDENTITY

	var parent = get_parent()
	if parent is RigidBody3D:
		velocity = parent.linear_velocity
		orientation_parent = parent.quaternion
	else:
		push_error("Parent is not a RigidBody3D")

	
	# Map velocity components to 0-255 range
	# First clamp velocity components to ±100 range, then remap to 0-255
	velocity = velocity.clamp(Vector3(-max_abs_velocity, -max_abs_velocity, -max_abs_velocity), Vector3(max_abs_velocity, max_abs_velocity, max_abs_velocity))
	var vel_x = int(remap(velocity.x, -max_abs_velocity, max_abs_velocity, 0, 255))
	var vel_y = int(remap(velocity.y, -max_abs_velocity, max_abs_velocity, 0, 255))
	var vel_z = int(remap(velocity.z, -max_abs_velocity, max_abs_velocity, 0, 255))

	# Map orientation components to 0-255 range
	# Convert quaternion to euler angles and remap from -PI to PI
	var euler = orientation_parent.get_euler()
	var rot_x = clamp(remap(euler.x, -PI, PI, 0, 255), 0, 255) as int
	var rot_y = clamp(remap(euler.y, -PI, PI, 0, 255), 0, 255) as int
	var rot_z = clamp(remap(euler.z, -PI, PI, 0, 255), 0, 255) as int

	print("Velocity (x,y,z): ", vel_x, ", ", vel_y, ", ", vel_z)
	print("Rotation (x,y,z): ", rot_x, ", ", rot_y, ", ", rot_z)

	# Update field with new values
	array.set_field([
		main_thruster_strength,
		control_thruster_mask,
		vel_x,
		vel_y, 
		vel_z,
		rot_x,
		rot_y,
		rot_z
	])
