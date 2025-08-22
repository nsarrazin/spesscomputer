extends Node3D

@export var ship_scene: PackedScene
@export var planet: Node3D

var ships: Array[Node] = []
var ship_idx: int = 0

# Property to access the currently active ship
@export var active_ship: Node:
	get:
		if ships.is_empty():
			return null
		if ship_idx < 0:
			ship_idx = 0
		var tries := 0
		while tries < ships.size():
			if ship_idx >= ships.size():
				ship_idx = 0
			var s = ships[ship_idx]
			if is_instance_valid(s):
				return s
			else:
				ships.remove_at(ship_idx)
				if ships.is_empty():
					return null
			tries += 1
		return null


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	ships = get_tree().get_nodes_in_group("ships")
	# If no ships exist, spawn one
	# if ships.is_empty():
	# 	spawn_ship()

	WebHelper.expose_all(self)

# Get the currently active ship
func spawn_ship(source_code: String = "") -> void:
	if not ship_scene or not planet:
		return
	
	var ship = ship_scene.instantiate()
	add_child(ship)
	ship.planet_node = planet

	var radius = randf_range(planet.radius * 1.2, planet.radius * 2) # Slightly away from planet surface (200-300km)
	# Use spherical coordinates: convert to Cartesian
	var theta = randf() * PI # Polar angle (0 to PI)
	var phi = randf() * TAU # Azimuthal angle (0 to 2*PI)
	
	ship.position = Vector3(
		radius * sin(theta) * cos(phi),
		radius * cos(theta),
		radius * sin(theta) * sin(phi)
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
	var camera = $Camera3D as Camera3D
	if not camera:
		return
	
	# If no ships, orbit the planet at 2x its radius
	if ships.is_empty():
		if planet:
			if camera.target_node != planet:
				camera.orbit_radius = planet.radius * 2.0
				camera.target_node = planet
		return
	
	# If we have a valid ship at the current index, track it
	if ship_idx >= 0 and ship_idx < ships.size():
		var target_ship = ships[ship_idx]
		if is_instance_valid(target_ship):
			if camera.target_node != target_ship:
				camera.target_node = target_ship
			return
	
	# Fallback: index invalid or ship freed, orbit planet
	if planet:
		if camera.target_node != planet:
			camera.orbit_radius = planet.radius * 2.0
			camera.target_node = planet

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

func js_pause():
	active_ship.computer.pause_emulator()
	return true

func js_resume():
	active_ship.computer.resume_emulator()
	return true

func js_step():
	active_ship.computer.step()
	return true
