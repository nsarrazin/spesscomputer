extends Node

@export var main_scene_path: NodePath
var main_scene: Node

# ---- Thruster memory + bit flags ----
const REG := [523, 524, 525, 526] # 4 quad thrusters
const RIGHT := 1
const LEFT := 2
const TOP := 4
const BOTTOM := 8

# Per-action bitmasks for the 4 quads (in REG order).
# Keeps your translate_* mappings; adds torque patterns for yaw/pitch/roll.
var ACTION_MAP := {
	# --- Translation (from your snippet) ---
	"translate_forward": [BOTTOM, BOTTOM, BOTTOM, BOTTOM],
	"translate_backward": [TOP, TOP, TOP, TOP],
	"translate_left": [LEFT, 0, RIGHT, 0],
	"translate_right": [RIGHT, 0, LEFT, 0],
	"translate_up": [0, LEFT, 0, RIGHT],
	"translate_down": [0, RIGHT, 0, LEFT],

	# --- Rotation (torques) ---
	# If the sign is inverted for your ship, swap these two arrays or flip TOP/BOTTOM per side.
	"yaw_left": [TOP, BOTTOM, BOTTOM, TOP],
	"yaw_right": [BOTTOM, TOP, TOP, BOTTOM],
	"pitch_up": [TOP, TOP, BOTTOM, BOTTOM], # nose up
	"pitch_down": [BOTTOM, BOTTOM, TOP, TOP], # nose down
	
	"roll_left": [LEFT, LEFT, LEFT, LEFT],
	"roll_right": [RIGHT, RIGHT, RIGHT, RIGHT],
}

var actions := [
	"translate_forward", "translate_backward",
	"translate_left", "translate_right",
	"translate_up", "translate_down",
	"yaw_left", "yaw_right",
	"pitch_up", "pitch_down",
	"roll_left", "roll_right",
]

# Track which actions are currently pressed
var pressed_actions := {}

func _ready() -> void:
	main_scene = get_node_or_null(main_scene_path)
	if main_scene == null:
		main_scene = get_tree().current_scene
	_ensure_default_actions()
	
	# Initialize pressed actions tracking
	for action in actions:
		pressed_actions[action] = false

func _input(event: InputEvent) -> void:
	var ship := _get_active_ship()
	if ship == null:
		return
	
	# Handle primary action (spacebar) - immediate response
	if event.is_action_pressed("action_primary"):
		ship.computer.emulator.set_memory(0x020A, 255)
		get_viewport().set_input_as_handled()
		return
	elif event.is_action_released("action_primary"):
		ship.computer.emulator.set_memory(0x020A, 0)
		get_viewport().set_input_as_handled()
		return
	
	# Handle movement actions
	var action_changed := false
	for action in actions:
		if event.is_action_pressed(action):
			if not pressed_actions[action]:
				pressed_actions[action] = true
				action_changed = true
		elif event.is_action_released(action):
			if pressed_actions[action]:
				pressed_actions[action] = false
				action_changed = true
	
	# Only update thrusters if an action state changed
	if action_changed:
		_update_thrusters(ship)
		get_viewport().set_input_as_handled()

func _update_thrusters(ship: Node) -> void:
	# Check if any movement actions are pressed
	var has_movement_input := false
	for action in actions:
		if pressed_actions[action]:
			has_movement_input = true
			break
	
	# If no movement inputs, clear thrusters
	if not has_movement_input:
		ship.computer.emulator.set_memory(REG[0], 0)
		ship.computer.emulator.set_memory(REG[1], 0)
		ship.computer.emulator.set_memory(REG[2], 0)
		ship.computer.emulator.set_memory(REG[3], 0)
		return
	
	# Compute thruster masks from pressed actions
	var masks := _compute_thruster_masks()
	
	# Write thrusters
	for i in range(4):
		ship.computer.emulator.set_memory(REG[i], masks[i])

func _compute_thruster_masks() -> Array:
	var masks := [0, 0, 0, 0]

	# OR all pressed action patterns together
	for action in actions:
		if pressed_actions[action]:
			var pattern: Array = ACTION_MAP[action]
			for i in range(4):
				masks[i] |= int(pattern[i])

	# Cancel opposed bits per quad (don't fire LEFT & RIGHT or TOP & BOTTOM together)
	for i in range(4):
		var m: Variant = masks[i]
		if (m & RIGHT) != 0 and (m & LEFT) != 0:
			m &= ~(RIGHT | LEFT)
		if (m & TOP) != 0 and (m & BOTTOM) != 0:
			m &= ~(TOP | BOTTOM)
		masks[i] = m

	return masks

func _get_active_ship() -> Node:
	if main_scene and "active_ship" in main_scene:
		var ship: Node = main_scene.active_ship
		if is_instance_valid(ship):
			return ship
	return null

# ================= Key bindings =================

static func _ensure_default_actions() -> void:
	var to_make := [
		"translate_up", "translate_down", "translate_left", "translate_right", "translate_forward", "translate_backward",
		"roll_left", "roll_right", "pitch_up", "pitch_down", "yaw_left", "yaw_right",
		"action_primary", "action_secondary"
	]
	for a in to_make:
		if not InputMap.has_action(a):
			InputMap.add_action(a)

	# Pitch/Yaw/Roll on WASDQE
	_bind_key("pitch_up", KEY_W)
	_bind_key("pitch_down", KEY_S)
	_bind_key("yaw_left", KEY_A)
	_bind_key("yaw_right", KEY_D)
	_bind_key("roll_left", KEY_Q)
	_bind_key("roll_right", KEY_E)

	# Primary/secondary actions
	_bind_key("action_primary", KEY_SPACE)
	_bind_key("action_secondary", KEY_SHIFT)

	# IJKLHN for translate
	_bind_key("translate_up", KEY_I)
	_bind_key("translate_down", KEY_K)
	_bind_key("translate_left", KEY_J)
	_bind_key("translate_right", KEY_L)
	_bind_key("translate_forward", KEY_H)
	_bind_key("translate_backward", KEY_N)

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
