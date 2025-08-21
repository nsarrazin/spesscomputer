extends Node

@export var main_scene_path: NodePath
@export var linear_accel: float = 12.0
@export var linear_speed: float = 10.0
@export var roll_accel: float = 3.0
@export var roll_speed: float = 1.8
var main_scene: Node

func _ready() -> void:
	main_scene = get_node_or_null(main_scene_path)
	if main_scene == null:
		main_scene = get_tree().current_scene
	_ensure_default_actions()
#
#func _physics_process(delta: float) -> void:
	#var ship := _get_active_ship()
	#if ship == null:
		#return

	# Continuous inputs mapped to controller methods

	
	#if Input.is_action_pressed("move_backward"): 
		#moved=true
	#if Input.is_action_pressed("move_left"): 
		#moved=true
	#if Input.is_action_pressed("roll_left"): 
		#moved=true
	#if Input.is_action_pressed("roll_right"): 
		#moved=true
#
	#if !moved:
		#ship.computer.emulator.set_memory(523, 0)
		#ship.computer.emulator.set_memory(524, 0)
		#ship.computer.emulator.set_memory(525, 0)
		#ship.computer.emulator.set_memory(526, 0)


func _unhandled_input(event: InputEvent) -> void:
	var ship := _get_active_ship()
	if ship == null:
		return
		
	if event.is_action_pressed("move_forward"):
		ship.computer.emulator.set_memory(523, 1)
	elif event.is_action_released("move_forward"):
		ship.computer.emulator.set_memory(523, 0)
	
	if event.is_action_pressed("action_primary"):
		ship.computer.emulator.set_memory(0x020A, 255)
	elif event.is_action_released("action_primary"):
		ship.computer.emulator.set_memory(0x020A, 0)
func _get_active_ship() -> Node:
	if main_scene and "active_ship" in main_scene:
		return main_scene.active_ship
	return null

# ================= Controller Methods =================
# These live in the controller and try multiple strategies depending on the ship type.

static func _ensure_default_actions() -> void:
	var to_make := [
		"move_forward", "move_backward", "move_left", "move_right",
		"move_up", "move_down", "roll_left", "roll_right",
		"action_primary", "action_secondary"
	]
	for a in to_make:
		if not InputMap.has_action(a):
			InputMap.add_action(a)

	# WASD + arrows
	_bind_key("move_forward", KEY_W)
	_bind_key("move_backward", KEY_S)
	_bind_key("move_left", KEY_A)
	_bind_key("move_right", KEY_D)
	_bind_key("move_forward", KEY_UP)
	_bind_key("move_backward", KEY_DOWN)
	_bind_key("move_left", KEY_LEFT)
	_bind_key("move_right", KEY_RIGHT)

	# Roll (Z/C)
	_bind_key("roll_left", KEY_Q)
	_bind_key("roll_right", KEY_E)

	# Primary/secondary actions
	_bind_key("action_primary", KEY_SPACE)
	_bind_key("action_secondary", KEY_SHIFT)

	# Basic gamepad defaults
	_bind_button("action_primary", JOY_BUTTON_A)
	_bind_button("action_secondary", JOY_BUTTON_B)

static func _bind_key(action: String, keycode: Key) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = keycode
	for e in InputMap.action_get_events(action):
		if e is InputEventKey and e.physical_keycode == keycode:
			return
	InputMap.action_add_event(action, ev)

static func _bind_button(action: String, button: JoyButton) -> void:
	var jb := InputEventJoypadButton.new()
	jb.button_index = button
	for e in InputMap.action_get_events(action):
		if e is InputEventJoypadButton and e.button_index == button:
			return
	InputMap.action_add_event(action, jb)
