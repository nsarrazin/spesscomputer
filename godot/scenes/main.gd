extends Node3D

@export var ship_scene: PackedScene
@export var planet: Node3D

var ships: Array[Node3D] = []
var ship_idx: int = 0

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	# Check if there are any ships in the scene
	var existing_ships = get_tree().get_nodes_in_group("ships")
	
	# If no ships exist, spawn one
	if existing_ships.is_empty():
		spawn_ship()

func spawn_ship(source_code: String = "") -> void:
	if not ship_scene or not planet:
		return
	
	var ship = ship_scene.instantiate()
	add_child(ship)
	
	# Position randomly around planet
	var angle = randf() * TAU
	var height = randf_range(100000, 120000) # Just above planet surface (100-120km)
	var radius = randf_range(200000, 300000) # Slightly away from planet surface (200-300km)
	ship.position = Vector3(
		cos(angle) * radius,
		height,
		sin(angle) * radius
	)
	
	ship.planet_node = planet

	if ship.computer && source_code:
		ship.computer.emulator.load_program_from_string(source_code, 0x600)

	ships.append(ship)


func next_ship() -> void:
	ship_idx += 1
	if ship_idx >= ships.size():
		ship_idx = 0

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
