extends Node3D

var shipComponents: Array = []
var emulator: Emulator6502 = Emulator6502.create_cpu("binaries/demo.bin", 5000)


func _ready() -> void:
	shipComponents = Utils.findNodeDescendantsInGroup(get_parent(), "ship_component")
	
func _physics_process(delta: float) -> void:
	emulator.wait_until_done()

	for component in shipComponents:
		component.run_logic(delta)

	emulator.execute_cycles_for_duration(delta)
