extends Node3D

@export var ship_scene: PackedScene
@export var planet: Node3D

var ships: Array[Node3D] = []
var ship_idx: int = 0

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	spawn_ship("""
THRUSTER_ZERO = $020A

.org $0600

main_loop:
	LDA #24                  ; Load thruster value 8
	STA THRUSTER_ZERO       ; Set thruster to 8
	JSR delay               ; Call delay subroutine
	
	LDA #0                  ; Load thruster value 0
	STA THRUSTER_ZERO       ; Set thruster to 0
	JSR delay               ; Call delay subroutine

	LDA #12                  ; Load thruster value 4
	STA THRUSTER_ZERO       ; Set thruster to 4
	JSR delay               ; Call delay subroutine

	LDA #0                  ; Load thruster value 8
	STA THRUSTER_ZERO       ; Set thruster to 8
	JSR delay               ; Call delay subroutine

	JMP main_loop           ; Repeat forever

; Delay subroutine - nested loops for shorter delay
delay:
	LDX #10                 ; Initialize outer loop counter (10 instead of 255)
outer_loop:
	LDY #$FF                ; Initialize inner loop counter
inner_loop:
	NOP                     ; Waste some cycles
	DEY                     ; Decrement inner counter
	BNE inner_loop          ; Loop until inner counter = 0
	DEX                     ; Decrement outer counter
	BNE outer_loop          ; Loop until outer counter = 0
	RTS                     ; Return from subroutine
	""")
func spawn_ship(source_code: String = "") -> void:
	if not ship_scene or not planet:
		return
	
	var ship = ship_scene.instantiate()
	add_child(ship)
	
	# Position randomly around planet
	var angle = randf() * TAU
	var height = randf_range(100000, 120000) # Just above planet surface (100-120km)
	var radius = randf_range(200000, 300000) # Slightly away from planet surface (200-300km)
	ship.position = Vector3(
		cos(angle) * radius,
		height,
		sin(angle) * radius
	)
	
	ship.planet_node = planet

	if ship.computer && source_code:
		ship.computer.emulator.load_program_from_string(source_code, 0x600)

	ships.append(ship)


func next_ship() -> void:
	ship_idx += 1
	if ship_idx >= ships.size():
		ship_idx = 0

func previous_ship() -> void:
	ship_idx -= 1
	if ship_idx < 0:
		ship_idx = ships.size() - 1

func _process(_delta: float) -> void:
	update_camera()

func update_camera() -> void:
	if ships.is_empty():
		return
		
	var camera = $Camera3D as Camera3D
	if not camera:
		return
		
	if ships.size() > ship_idx:
		var target_ship = ships[ship_idx]
		camera.target_node = target_ship
