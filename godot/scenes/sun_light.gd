extends DirectionalLight3D

@export var sun_node: Node3D = null

func _process(_delta: float) -> void:
	if sun_node:
		look_at(sun_node.global_transform.origin)
		rotate_object_local(Vector3.UP, PI)
