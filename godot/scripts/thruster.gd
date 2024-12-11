class_name Thruster

extends Node3D

@export var force_magnitude: float = 100.0
@export var is_active: bool = true  # Enable or disable the thruster

# Reference to visual elements
@onready var visual_effect = $GPUParticles3D

func _physics_process(delta: float):		
	# Update visual effects
	if visual_effect:
		visual_effect.emitting = is_active
		
	if not is_active:
		return
		
	# Find the parent RigidBody
	var parent = get_parent()
	if parent and parent is RigidBody3D:
		parent.apply_force(
			global_transform.basis.y * force_magnitude,  # Force direction in global coordinates
			global_position - parent.global_position      # Force position relative to parent's center
		)

func fire():
	is_active = true
	
func stop():
	is_active = false
