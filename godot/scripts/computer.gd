extends Node3D

var max_abs_velocity: float = 1000.0
var emulator: Emulator6502

var buffer: Array[int] = []
var control_thruster_nodes: Array[Thruster] = []
var thruster: Thruster

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	emulator = Emulator6502.create_cpu("binaries/demo.bin", 5000)

	for child in get_parent().get_children():
		if child.name.contains("Thruster") and child.name != "Thruster":
			control_thruster_nodes.append(child)
		elif child.name.contains("Thruster"):
			thruster = child

func _physics_process(_delta: float) -> void:
	emulator.wait_until_done()
	var mmio = emulator.get_mmio()

	var main_thruster_strength = mmio[0]
	var control_thruster_mask = mmio[1]
	
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

	emulator.set_memory(0x203, vel_x)
	emulator.set_memory(0x204, vel_y)
	emulator.set_memory(0x205, vel_z)
	emulator.set_memory(0x206, rot_x)
	emulator.set_memory(0x207, rot_y)
	emulator.set_memory(0x208, rot_z)

	emulator._process(_delta)
