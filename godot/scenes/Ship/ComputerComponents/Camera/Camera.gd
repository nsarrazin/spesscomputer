extends ShipComponent

@onready var camera: Camera3D = find_ship_camera()

# camera spec
# $00 -> Settings byte #FFBBCCMM
# FF -> FOV Mode, 0 = 30, 1 = 60, 2 = 90, 3 = 120
# BB -> Brightness level, 00 -> -1 stop, 01 -> 0 stops, 10 -> 1 stop, 11 -> 2 stops
# CC -> Color wheel, 00 -> B&W, 01 -> Red, 10 -> Green, 11 -> Blue
# MM -> Bits per pixel, 00 -> 1, 01 -> 2, 10 -> 4, 11 -> 8

# $01 -> Camera status & control #LDMEXXXP
# L -> Taking picture
# D -> Data ready 
# M -> More data available <-- set to 0 to pull more data
# E -> Error
# X -> Undefined
# X -> Undefined
# X -> Undefined
# P -> Take a picture

# $02 -> Camera data
# 8 bytes of data

func run_logic(delta: float) -> void:
    
    pass



func find_ship_camera() -> Camera3D:
    var parent = get_parent()
    for child in parent.get_children():
        if child is Camera3D:
            return child
    return null