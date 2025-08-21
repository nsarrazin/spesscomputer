extends Node3D


var shipComponents: Array = []
var emulator: Emulator6502

var pause: bool = false

func _init() -> void:
	emulator = Emulator6502.create_cpu(10)

func _process(delta: float) -> void:
	if (Engine.get_process_frames() == 0):
		# Initialize memory page 0x200-0x2FF to zero
		for addr in range(0x200, 0x300):
			emulator.set_memory(addr, 0)

	if !pause:
		emulator.wait_until_done()
		
	for component in shipComponents:
		component.run_logic(delta)

	if !pause:
		emulator.execute_cycles_for_duration(delta)
		
func pause_emulator() -> void:
	pause = true

func resume_emulator() -> void:
	pause = false

func step() -> void:
	emulator.step()

func add_component(component: Node3D) -> void:
	shipComponents.append(component)
