
extends ShipComponent

var control_thruster_nodes: Array = []
var thruster: Node3D

func _init() -> void:
	memory_size = 2

func _ready() -> void:
	for child in get_parent().get_children():
		if child.name.contains("Thruster") and child.name != "Thruster":
			control_thruster_nodes.append(child)
		elif child.name.contains("Thruster"):
			thruster = child

func run_logic(_delta: float) -> void:
	var main_thruster_strength = addressBuffer[0]
	var control_thruster_mask = addressBuffer[1]

	if main_thruster_strength > 0:
		thruster.fire()
	else:
		thruster.stop()

	for i in range(8):
		var thruster_on = (control_thruster_mask & (1 << i)) != 0
		if thruster_on:
			control_thruster_nodes[i].fire()
		else:
			control_thruster_nodes[i].stop()
