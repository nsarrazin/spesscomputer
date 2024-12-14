
extends ShipComponent

var thruster_nodes: Array = []

func _init() -> void:
	memory_size = 9

func _ready() -> void:
	var main_thruster = null
	for child in get_parent().get_children():
		if child.name.contains("Thruster") and child.name != "Thruster":
			thruster_nodes.append(child)
		elif child.name.contains("Thruster"):
			main_thruster = child

	thruster_nodes.push_front(main_thruster)


		

func run_logic(_delta: float) -> void:
	for i in range(0, memory_size):
		var thrust_command = addressBuffer[i]

		if thrust_command > 0:
			thruster_nodes[i].fire()
		else:
			thruster_nodes[i].stop()
