extends Node3D

@export var capsule_scene: PackedScene
@export var planet: Node3D

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	#spawn_capsules()
	pass

func spawn_capsules() -> void:
	if not capsule_scene or not planet:
		return
		
	for i in range(10):
		var capsule = capsule_scene.instantiate()
		add_child(capsule)
		
		# Position randomly around planet
		var angle = randf() * TAU
		var height = randf_range(10, 20)
		var radius = randf_range(20, 30)
		
		capsule.position = Vector3(
			cos(angle) * radius,
			height,
			sin(angle) * radius
		)
		
		capsule.planet_node = planet
