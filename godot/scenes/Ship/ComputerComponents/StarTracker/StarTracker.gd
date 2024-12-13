extends ShipComponent

var rigid_body: RigidBody3D


func _init() -> void:
    memory_size = 4

func _ready() -> void:
    var parent = get_parent()
    while parent and not parent is RigidBody3D:
        parent = parent.get_parent()
    
    if parent is RigidBody3D:
        rigid_body = parent


func run_logic(delta: float) -> void:
    var angular_velocity = rigid_body.angular_velocity
    var magnitude = clamp(angular_velocity.length(), 0, 25)
    
    # Calculate deviation based on angular velocity magnitude
    # Use exponential function to make it increase non-linearly
    var base_deviation = 1.5
    var deviation_multiplier = exp(magnitude) - 1
    var deviation = base_deviation * deviation_multiplier
    
    # Cap the maximum deviation to avoid extreme values
    deviation = min(deviation, 10.0)
    
    var rng = RandomNumberGenerator.new()
    rng.randomize()
    
    var base_x = fmod(rigid_body.rotation.x + rng.randfn(0, deviation) + PI, 2 * PI) - PI
    var base_y = fmod(rigid_body.rotation.y + rng.randfn(0, deviation) + PI, 2 * PI) - PI 
    var base_z = fmod(rigid_body.rotation.z + rng.randfn(0, deviation) + PI, 2 * PI) - PI

    addressBuffer[0] = round(clamp(remap(base_x, -PI, PI, 0, 255), 0, 255))
    addressBuffer[1] = round(clamp(remap(base_y, -PI, PI, 0, 255), 0, 255))
    addressBuffer[2] = round(clamp(remap(base_z, -PI, PI, 0, 255), 0, 255))
    addressBuffer[3] = round(clamp(remap(deviation, 0, 10, 0, 255), 0, 255))