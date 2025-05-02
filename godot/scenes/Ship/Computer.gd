extends Node3D

var shipComponents: Array = []
var emulator: Emulator6502

var pause: bool = false

func _init() -> void:
	var arguments = OS.get_cmdline_args()

	var source_path = ""
	
	# Check for --source argument in command line
	for arg in arguments:
		if arg.begins_with("--source="):
			source_path = arg.substr(9) # Remove the "--source=" prefix
			print("Using custom source path: " + source_path)
	
	# Load the assembly source file
	var source_code =  "LDA #$00\nRTS"
	if source_path:
		var file = FileAccess.open(source_path, FileAccess.READ)
		source_code = file.get_as_text()
		file.close()
		print("Successfully loaded assembly source from: " + source_path)
	
	emulator = Emulator6502.create_cpu_from_string(source_code, 5000)
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
