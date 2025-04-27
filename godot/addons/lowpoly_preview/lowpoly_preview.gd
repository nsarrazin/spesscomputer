@tool
# addons/lowpoly_preview/lowpoly_preview.gd
extends EditorPlugin

var overlay: ColorRect

func _enter_tree() -> void:
	# make a full-screen transparent canvas layer
	overlay = ColorRect.new()
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	overlay.size_flags_vertical = Control.SIZE_EXPAND_FILL
	overlay.color = Color(0, 0, 0, 0) # fully transparent

	var mat := ShaderMaterial.new()
	mat.shader = load("res://addons/lowpoly_preview/poly-shader.gdshader")
	overlay.material = mat

	# add it on top of the editor root
	var root := get_editor_interface().get_base_control()
	root.add_child(overlay)
	overlay.z_index = 10_000 # make sure it stays in front
	overlay.owner = root # keeps it from showing in the scene tree

func _exit_tree() -> void:
	overlay.queue_free()
