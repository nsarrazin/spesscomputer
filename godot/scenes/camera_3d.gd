extends Camera3D

# Node that the camera should track
@export var target_node: Node3D = null
@export var orbit_radius: float = 20.0
@export var orbit_sensitivity: float = 0.01
@export var zoom_sensitivity: float = 0.1
@export var min_zoom: float = 5.0
@export var max_zoom: float = 50.0

var orbit_angles = Vector2.ZERO # Stores pitch and yaw angles

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	# Initialize with no target
	if target_node:
		# Set initial position with slight offset to avoid look_at alignment issues
		position = target_node.global_position + Vector3(0, 1, orbit_radius)
		look_at(target_node.global_position, Vector3.UP)

# Set the target node for the camera to track
func set_target(node: Node3D) -> void:
	target_node = node
	if target_node:
		# Clamp radius to sensible limits for this target
		var limits := _get_zoom_limits()
		orbit_radius = clamp(orbit_radius, limits.x, limits.y)
		position = target_node.global_position + Vector3(0, 0, orbit_radius)
		look_at(target_node.global_position)

func _unhandled_input(event: InputEvent) -> void:
	if not target_node:
		return
		
	if event is InputEventMouseMotion and event.button_mask == MOUSE_BUTTON_LEFT:
		# Update orbit angles based on mouse movement
		orbit_angles.x += event.relative.y * orbit_sensitivity # Reversed y movement
		orbit_angles.y -= event.relative.x * orbit_sensitivity
		
		# Clamp vertical rotation to avoid flipping
		orbit_angles.x = clamp(orbit_angles.x, -PI / 2, PI / 2)
		
		_update_camera_position()
	
	elif event is InputEventMouseButton:
		if not event.pressed:
			return
		var limits := _get_zoom_limits()
		var eff := zoom_sensitivity
		if target_node and "radius" in target_node:
			# Much smaller per-notch change when zooming a planet-scale target
			eff = min(zoom_sensitivity, 0.01)
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			# Zoom in multiplicatively and clamp to target-aware limits
			orbit_radius = clamp(orbit_radius * (1.0 - eff), limits.x, limits.y)
			_update_camera_position()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			# Zoom out multiplicatively and clamp to target-aware limits
			orbit_radius = clamp(orbit_radius * (1.0 + eff), limits.x, limits.y)
			_update_camera_position()

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	if target_node:
		_update_camera_position()

# Updates camera position based on target position and current orbit angles
func _update_camera_position() -> void:
	# Calculate new position relative to target
	var new_pos = Vector3()
	new_pos.x = orbit_radius * cos(orbit_angles.x) * sin(orbit_angles.y)
	new_pos.y = orbit_radius * sin(orbit_angles.x)
	new_pos.z = orbit_radius * cos(orbit_angles.x) * cos(orbit_angles.y)
	
	# Update camera position and look at target
	position = target_node.global_position + new_pos
	
	if abs(new_pos.x) < 0.001 and abs(new_pos.z) < 0.001:
		return
	else:
		look_at(target_node.global_position, Vector3.UP)

# Compute sensible zoom limits depending on the target's scale (e.g., planet vs ship)
func _get_zoom_limits() -> Vector2:
	var min_r: float = min_zoom
	var max_r: float = max_zoom
	if target_node and "radius" in target_node:
		# Assume large body like a planet
		var r: float = target_node.radius
		# Don't allow zooming inside the surface; allow generous far distance
		min_r = max(min_zoom, r * 1.05)
		max_r = max(max_zoom, r * 12.0)
	return Vector2(min_r, max_r)
