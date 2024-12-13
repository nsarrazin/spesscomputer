extends ShipComponent

const MAX_ACCEL: float = 25.0
const MAX_ANG_VEL: float = 10.0

var groundObjects
func _init() -> void:
    memory_size = 6

func _ready() -> void:
    groundObjects = get_tree().get_nodes_in_group("Ground")

func run_logic(delta: float) -> void:
    for groundObject in groundObjects:
        if groundObject.is_colliding():
            addressBuffer[0] = 1
        else:
            addressBuffer[0] = 0
