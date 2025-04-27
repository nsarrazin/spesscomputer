extends Node3D

var shipComponents: Array = []
var emulator: Emulator6502 = Emulator6502.create_cpu_from_string("""
THRUSTER_ZERO = $0212

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
""", 5000)
var pause: bool = false
	
func _process(delta: float) -> void:
	if (Engine.get_process_frames() == 0):
		# Initialize memory page 0x200-0x2FF to zero
		for addr in range(0x200, 0x300):
			emulator.set_memory(addr, 0)

	if !pause:
		emulator.wait_until_done()
		
	for component in shipComponents:
		component.run_logic(delta)

	if !pause:
		emulator.execute_cycles_for_duration(delta)
		
func pause_emulator() -> void:
	pause = true

func resume_emulator() -> void:
	pause = false

func step() -> void:
	emulator.step()

func add_component(component: Node3D) -> void:
	shipComponents.append(component)
