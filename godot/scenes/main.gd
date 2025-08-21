extends Node3D

@export var ship_scene: PackedScene
@export var planet: Node3D

var ships: Array[Node] = []
var ship_idx: int = 0

# Property to access the currently active ship
@export var active_ship: Node:
	get:
		if ships.is_empty() or ship_idx >= ships.size():
			return null
		return ships[ship_idx]


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	ships = get_tree().get_nodes_in_group("ships")
	# If no ships exist, spawn one
	if ships.is_empty():
		spawn_ship()

	WebHelper.expose_all(self)

# Get the currently active ship
func spawn_ship(source_code: String = "") -> void:
	if not ship_scene or not planet:
		return
	
	var ship = ship_scene.instantiate()
	add_child(ship)
	ship.planet_node = planet

	# Position randomly around planet
	var angle = randf() * TAU
	var height = randf_range(planet.radius / 2, planet.radius / 2) # Just above planet surface (100-120km)
	var radius = randf_range(planet.radius, planet.radius) # Slightly away from planet surface (200-300km)
	ship.position = Vector3(
		cos(angle) * radius,
		height,
		sin(angle) * radius
	)
	
	ship.set_initial_speed()

	if ship.computer && source_code:
		ship.computer.emulator.load_program_from_string(source_code, 0x600)

	ships.append(ship)


func next_ship() -> void:
	ship_idx += 1

func previous_ship() -> void:
	ship_idx -= 1
	if ship_idx < 0:
		ship_idx = ships.size() - 1

func _process(_delta: float) -> void:
	update_camera()

func update_camera() -> void:
	if ships.is_empty():
		return
		
	var camera = $Camera3D as Camera3D
	if not camera:
		return
		
	if ships.size() > ship_idx:
		var target_ship = ships[ship_idx]
		camera.target_node = target_ship

func js_getCurrentRegisters():
	return active_ship.computer.emulator.get_cpu_state()

func js_respawnShipWithCode(source = ""):
	# Properly free existing ships to prevent memory leaks
	for ship in ships:
		if is_instance_valid(ship):
			ship.queue_free()
	
	# Clear ships array and reset index
	ships = []
	ship_idx = 0
	
	# Wait a frame to ensure ships are properly freed before spawning new one
	await get_tree().process_frame
	
	spawn_ship(source)
	
func js_nextShip():
	next_ship()
	
func js_prevShip():
	previous_ship()
	
func js_getPage(page = -1):
	if page < 0:
		var states = active_ship.computer.emulator.get_cpu_state()
		var current_page = states['pc'] >> 8
		return active_ship.computer.emulator.read_page(current_page)


	return active_ship.computer.emulator.read_page(page)
	
func js_setFrequency(frequency = 10):
	active_ship.computer.emulator.set_frequency(frequency)
		
	return true
