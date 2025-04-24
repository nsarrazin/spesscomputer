class_name ThrusterQuad

extends ShipComponent

@export var force_magnitude: float = 1.0
var x_pos_active: bool = false
var x_neg_active: bool = false
var y_pos_active: bool = false
var y_neg_active: bool = false


# Reference to visual elements
@onready var x_pos_effect = $"GPUParticles3D - X+"
@onready var x_neg_effect = $"GPUParticles3D - X-"
@onready var y_pos_effect = $"GPUParticles3D - Y+"
@onready var y_neg_effect = $"GPUParticles3D - Y-"

func _init() -> void:
	memory_size = 1

func run_logic(_delta: float) -> void:
	var buffer = addressBuffer[0]

	x_pos_active = buffer & 0b0001
	x_neg_active = buffer & 0b0010
	y_pos_active = buffer & 0b0100
	y_neg_active = buffer & 0b1000


	# print(String.num_int64(buffer, 2), x_pos_active, x_neg_active, y_pos_active, y_neg_active)

	x_pos_effect.emitting = x_pos_active
	x_neg_effect.emitting = x_neg_active
	y_pos_effect.emitting = y_pos_active
	y_neg_effect.emitting = y_neg_active
		
	# Find the parent RigidBody
	var parent = get_parent()
	if parent and parent is RigidBody3D:
		var force = Vector3.ZERO
		if x_pos_active:
			force += global_transform.basis.x * force_magnitude
		if x_neg_active:
			force -= global_transform.basis.x * force_magnitude
		if y_pos_active:
			force += global_transform.basis.y * force_magnitude
		if y_neg_active:
			force -= global_transform.basis.y * force_magnitude

		var position_force = global_position - parent.global_position

		parent.apply_force(
			force, # Force direction in global coordinates
			position_force # Force position relative to parent's center
		)
