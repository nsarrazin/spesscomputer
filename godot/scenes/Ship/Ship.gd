extends RigidBody3D

class_name Ship

const Computer = preload("res://scenes/Ship/Computer.gd")
const IMU = preload("res://scenes/Ship/ComputerComponents/IMU/IMU.gd")
const StarTracker = preload("res://scenes/Ship/ComputerComponents/StarTracker/StarTracker.gd")

@export var planet_node: Node3D = null
@export var source_code: SourceCode = null
# Crash parameters
@export var crash_vertical_speed_threshold: float = 30.0
@export var crash_altitude_margin: float = 50.0

var computer: Computer = null
var _has_exploded: bool = false

func _init() -> void:
	computer = Computer.new()
	computer.name = "Computer"
	add_child(computer)

	add_computer_component(IMU, 0x200)
	add_computer_component(StarTracker, 0x206)
	

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	# Set center of mass to ship's geometric center to prevent unwanted torque
	center_of_mass = Vector3.ZERO
	
	set_initial_speed()

	if source_code:
		computer.emulator.load_program_from_string(source_code.value, 0x600)
	
	for address in range(0x200, 0x300):
		computer.emulator.set_memory(address, 0)

func set_initial_speed() -> void:
	if not planet_node:
		return
		
	# Get gravitational parameter and radius vector
	var mu = planet_node.gravitational_pull
	var radius_vector = global_position - planet_node.global_position
	var r = radius_vector.length()
	
	# Semi-major axis a = r/(1-e) at periapsis
	var e = 0.3 # eccentricity
	var a = r / (1 - e)
	
	# Calculate velocity magnitude using vis-viva equation
	var v = sqrt(mu * (2 / r - 1 / a))
	
	var orbit_direction = radius_vector.cross(Vector3.UP).normalized()
	linear_velocity = orbit_direction * v

func add_computer_component(component, memory_address):
	component = component.new()
	component.memory_address = memory_address
	add_child(component)
	component.startup()

func _physics_process(_delta: float) -> void:
	if _has_exploded or planet_node == null:
		return
	# Estimate proximity to surface using planet heightfield and check descent speed
	if not planet_node.has_method("get_height_at_position"):
		return
	var to_center: Vector3 = global_position - planet_node.global_position
	var radial_dir: Vector3 = to_center.normalized()
	var surface_radius: float = planet_node.get_height_at_position(global_position)
	var altitude: float = to_center.length() - surface_radius
	# Positive when moving toward planet (descending)
	var descent_speed: float = - linear_velocity.dot(radial_dir)
	if altitude <= crash_altitude_margin and descent_speed > crash_vertical_speed_threshold:
		_explode()

func _explode() -> void:
	if _has_exploded:
		return
	_has_exploded = true
	# TODO: Replace with a proper particle/FX scene. For now, just free the ship.
	print("Ship exploded! Descent speed too high.")
	queue_free()
