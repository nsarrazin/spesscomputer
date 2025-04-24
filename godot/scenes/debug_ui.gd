extends Node
const Computer = preload("res://scenes/Ship/Computer.gd")
const MainCamera = preload("res://scenes/camera_3d.gd")


@export var camera: MainCamera = null
var computer: Computer = null
var follow_pc: bool = true
var active_page: int = 0

func _ready():
	var ship = camera.target_node
	assert(ship.computer)
	computer = ship.computer
	
	
func _process(_delta):
	var isFirstLoad = Engine.get_process_frames() == 0
	var state = computer.emulator.get_cpu_state()
	
	if follow_pc:
		active_page = (state.pc >> 8) & 0xFF
	
	var page_data = computer.emulator.read_page(active_page)

	ImGui.Begin("CPU Debug")
	ImGui.Text("PC: %s" % [state.pc])
	ImGui.Text("A: %s" % [state.a])
	ImGui.Text("X: %s" % [state.x])
	ImGui.Text("Y: %s" % [state.y])
	ImGui.Text("P: %s" % [String.num_uint64(state.p, 2).pad_zeros(8)])
	ImGui.Text("SP: %s" % [state.sp])
	ImGui.End()
	
	if isFirstLoad:
		ImGui.SetNextWindowPos(Vector2(200, 200))
	ImGui.Begin("Page explorer")
	
	# Navigation controls
	if ImGui.Checkbox("Follow PC", [follow_pc]):
		follow_pc = !follow_pc
	
	ImGui.SameLine()
	if ImGui.Button("< Prev"):
		active_page = max(0, active_page - 1)
		follow_pc = false
	
	ImGui.SameLine()
	if ImGui.Button("Next >"):
		active_page = min(0xFF, active_page + 1)
		follow_pc = false
	
	ImGui.Text("Page: 0x%02X" % [active_page])
	
	# Display memory as a hexdump with 16 bytes per row
	var bytes_per_row = 16
	var rows = page_data.size() / bytes_per_row
	var pc_address = state.pc
	var pc_in_current_page = (pc_address >> 8) == active_page
	
	for row in range(rows):
		var offset = row * bytes_per_row
		
		# Display row address
		ImGui.Text("%04X:" % [active_page * 256 + offset])
		ImGui.SameLine()
		
		# Format hex values with spacing
		for col in range(bytes_per_row):
			var byte_index = offset + col
			var byte_value = page_data[byte_index]
			var current_address = active_page * 256 + byte_index
			
			# Highlight the current PC position
			if pc_in_current_page and current_address == pc_address:
				ImGui.PushStyleColor(ImGui.Col.Col_Text, Color(1, 0.5, 0, 1)) # Orange highlight
				ImGui.PushStyleColor(ImGui.Col.Col_FrameBg, Color(1, 1, 1, 1)) # White background

			ImGui.Text("%02X" % byte_value)
			
			if pc_in_current_page and current_address == pc_address:
				ImGui.PopStyleColor()
			
			ImGui.SameLine()
			
			# Add extra space after 8 bytes for readability
			if col == 7:
				ImGui.Text(" ")
				ImGui.SameLine()
		
		# Separator between hex and ASCII
		ImGui.Text("|")
		ImGui.SameLine()
		
		# Create ASCII representation
		for col in range(bytes_per_row):
			var byte_index = offset + col
			var byte_value = page_data[byte_index]
			var current_address = active_page * 256 + byte_index
			var char_to_display = "."
			
			if byte_value >= 32 and byte_value <= 126: # Printable ASCII range
				char_to_display = char(byte_value)
			
			# Highlight the current PC position
			if pc_in_current_page and current_address == pc_address:
				ImGui.PushStyleColor(ImGui.Col.Col_Text, Color(1, 0.5, 0, 1)) # Orange highlight
			
			ImGui.Text(char_to_display)
			
			if pc_in_current_page and current_address == pc_address:
				ImGui.PopStyleColor()
			
			ImGui.SameLine()
		
		# Remove the last SameLine since we're done with this row
		ImGui.NewLine()
	ImGui.End()
