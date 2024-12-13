extends Node3D

var shipComponents: Array = []
var emulator: Emulator6502 = Emulator6502.create_cpu("binaries/demo.bin", 5000)
var pause: bool = false


func _ready() -> void:
	shipComponents = Utils.findNodeDescendantsInGroup(get_parent(), "ship_component")
	
func _physics_process(delta: float) -> void:
	# if !pause:
	# 	emulator.wait_until_done()

	for component in shipComponents:
		component.run_logic(delta)

	if !pause:
		emulator.execute_cycles_for_duration(delta)

		emulator.wait_until_done()

func pause_emulator() -> void:
	pause = true

func resume_emulator() -> void:
	pause = false

func step() -> void:
	emulator.step()
