extends RigidBody3D

# Array of thruster nodes
var thrusters: Array[Node3D] = []

# Timer to handle thruster firing
var thruster_timer = 0.0
var current_thruster = 0

func _ready():
	# Gather thrusters dynamically
	for child in get_children():
		if child is Node3D and child.has_method("fire"): # Ensure it's a Thruster instance
			thrusters.append(child)

func _process(delta: float):
	if thrusters.size() == 0:
		return

	thruster_timer -= delta
	if thruster_timer <= 0:
		# Switch to the next thruster
		thrusters[current_thruster].stop() # Stop the current thruster
		current_thruster = (current_thruster + 1) % thrusters.size()
		thruster_timer = 1.0  # Fire each thruster for 1 second
		thrusters[current_thruster].fire() # Start the next thruster

	# Apply force to the rigid body from the firing thruster
	thrusters[current_thruster].apply_force(self)
