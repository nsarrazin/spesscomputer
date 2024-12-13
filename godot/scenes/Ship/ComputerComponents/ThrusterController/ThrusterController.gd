
extends ShipComponent

var thruster_nodes: Array = []

func _init() -> void:
	memory_size = 1

func _ready() -> void:
	var main_thruster = null
	for child in get_parent().get_children():
		if child.name.contains("Thruster") and child.name != "Thruster":
			thruster_nodes.append(child)
		elif child.name.contains("Thruster"):
			main_thruster = child

	thruster_nodes.push_front(main_thruster)


		

func run_logic(_delta: float) -> void:
	var comm_address = addressBuffer[0]

	# comm message look like this
	# SSAAAAAA
	# SS -> Strength of the force (if applicable)
	# AAAAAA -> Address of the thruster to fire (63 possible thrusters, starts at 1 with 1 main thruster)
	# save the 0th address for special messages

	# 00000000 -> idle
	# 01000000 -> fired thruster succesfully
	# 10000000 -> stopped thruster succesfully
	# 11000000 -> error processing message

	var thruster_address = comm_address & 0x3F
	var thruster_strength = (comm_address & 0xC0) >> 6

	if thruster_address == 0:
		return
	
	if (thruster_address - 1) > thruster_nodes.size():
		addressBuffer[0] = 0b11000000
		return

	if thruster_strength > 0:
		thruster_nodes[thruster_address - 1].fire()
		addressBuffer[0] = 0b01000000
	else:
		thruster_nodes[thruster_address - 1].stop()
		addressBuffer[0] = 0b10000000
		
