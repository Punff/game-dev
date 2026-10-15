extends CanvasLayer

## Global film-grain / grime overlay sitting above every scene.

var _rect := ColorRect.new()
var _mat := ShaderMaterial.new()


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_mat.shader = preload("res://shaders/grit.gdshader")
	_rect.material = _mat
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_rect)
	_apply()
	SignalBus.settings_changed.connect(_apply)


func _apply() -> void:
	_mat.set_shader_parameter("strength", 0.5 if Settings.get_value("reduced_effects") else 1.0)
