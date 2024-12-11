
extends Node3D

class_name ShipComponent
var memory_address: int # The start address of the component in memory
var memory_size: int # The size of the component in memory
var every_n_frames: int = 1 # How often should the component run

@onready var emulator: Emulator6502 = get_parent().get_node("Computer").emulator

var addressBuffer: Array = []

func _init(_memory_address: int) -> void:
	memory_address = _memory_address

func _ready() -> void:
	addressBuffer.resize(memory_size)
	addressBuffer.fill(0)

	# Check if every address the component will use in memory is set to 0
	for i in range(memory_size):
		if emulator.read_memory(memory_address + i) != 0:
			push_error("Memory address " + str(memory_address + i) + " is not set to 0. Are components using the same memory address?")
			return

	# Set all addresses the component will use in memory to 255
	for i in range(memory_size):
		emulator.set_memory(memory_address + i, 255)

	add_to_group("ship_component")
	

func run_logic(delta: float) -> void:
	pass

func _physics_process(delta: float) -> void:
	addressBuffer.resize(memory_size)
	addressBuffer.fill(0)
	# run logic every n frames
	if Engine.get_process_frames() % every_n_frames == 0:
		# read memory into buffer
		for i in range(memory_size):
			addressBuffer[i] = emulator.read_memory(memory_address + i)
		
		# run the component logic, potentially modifying the buffer
		run_logic(delta)
		# write the buffer back to memory
		for i in range(memory_size):
			emulator.set_memory(memory_address + i, int(addressBuffer[i]))

func with_memory_address(_memory_address: int) -> ShipComponent:
	memory_address = _memory_address
	return self
