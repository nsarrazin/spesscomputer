extends Node3D

class_name ShipComponent

var emulator: Emulator6502 = null

@export var memory_address: int # The start address of the component in memory
var memory_size: int = 1 # The size of the component in memory
var every_n_frames: int = 1 # How often should the component run


var addressBuffer: Array = []

func _ready() -> void:
	startup()

func startup() -> void:
	var ship = find_ship()
	emulator = ship.computer.emulator
	ship.computer.add_component(self)

	assert(memory_address, "Memory address not set")
	assert(emulator, "Emulator not found")
	print("Component: ", name, " - Memory Address: 0x", "%04X" % memory_address, " - Size: ", memory_size, " bytes")

	addressBuffer.resize(memory_size)
	addressBuffer.fill(0)

	# Check if every address the component will use in memory is set to 0
	for i in range(memory_size):
		assert(emulator.read_memory(memory_address + i) == 0, "Memory address " + str(memory_address + i) + " is not set to 0. Are components using the same memory address?")

	# Set all addresses the component will use in memory to 255
	for i in range(memory_size):
		emulator.set_memory(memory_address + i, 255)

	add_to_group("ship_component")

func run_logic(_delta: float) -> void:
	pass

func _physics_process(delta: float) -> void:
	# Debug print memory address and size
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
	var component = self
	self.memory_address = _memory_address
	return component

func find_ship() -> Ship:
	var parent = get_parent()
	while parent and not parent is Ship:
		parent = parent.get_parent()
	
	if parent is Ship:
		return parent
	
	return null
