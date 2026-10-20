extends CanvasLayer

## Global film-grain / grime overlay sitting above every scene.

var _mat := ShaderMaterial.new()


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_mat.shader = preload("res://shaders/grit.gdshader")
	# Up to 1080p it's drawn per pixel as before; past that (high-DPI screens,
	# where the browser renders several times the pixels) it's stretched.
	var grain := LowResLayer.new()
	grain.setup(_mat, 1920 * 1080, true)
	add_child(grain)
	_apply()
	SignalBus.settings_changed.connect(_apply)


func _apply() -> void:
	_mat.set_shader_parameter("strength", 0.5 if Settings.get_value("reduced_effects") else 1.0)
