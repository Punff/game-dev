class_name Background
extends CanvasLayer

## Full-screen procedural sky that tracks a camera and blends palettes
## between biomes as players climb.

const SHADER := preload("res://shaders/background.gdshader")

## [sky_top, sky_bottom, islands, accent] per biome, matching MapPlanner.BIOMES.
const PALETTES := [
	[Color("1a1a3a"), Color("3d2b5e"), Color("2b2552"), Color("ffb36b")],
	[Color("2a0f22"), Color("5e2030"), Color("3f1729"), Color("ff7a3d")],
	[Color("0e0a22"), Color("2b1754"), Color("1f1344"), Color("b07bff")],
	[Color("0b1624"), Color("1f3b55"), Color("16293d"), Color("6fd3ff")],
]
const BLEND_PX := 2500.0

var camera: Camera2D
var auto_scroll := 0.0         ## px/s, used by menus with no camera
var _rect := ColorRect.new()
var _mat := ShaderMaterial.new()
var _scroll := 0.0


func _ready() -> void:
	layer = -10
	_mat.shader = SHADER
	_rect.material = _mat
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rect)
	set_height(0.0)
	_apply_detail()
	SignalBus.settings_changed.connect(_apply_detail)


func _apply_detail() -> void:
	_mat.set_shader_parameter("detail", 0.0 if Settings.get_value("reduced_effects") else 1.0)


## Blend palettes by climbed height (px above the start floor).
func set_height(h: float) -> void:
	var idx := 0
	for i in MapPlanner.BIOMES.size():
		if h >= MapPlanner.BIOMES[i].from:
			idx = i
	var t := 0.0
	if idx + 1 < MapPlanner.BIOMES.size():
		var next_from: float = MapPlanner.BIOMES[idx + 1].from
		t = clampf((h - (next_from - BLEND_PX)) / BLEND_PX, 0.0, 1.0)
	var a: Array = PALETTES[idx]
	var b: Array = PALETTES[mini(idx + 1, PALETTES.size() - 1)]
	_mat.set_shader_parameter("sky_top", a[0].lerp(b[0], t))
	_mat.set_shader_parameter("sky_bottom", a[1].lerp(b[1], t))
	_mat.set_shader_parameter("island_color", a[2].lerp(b[2], t))
	_mat.set_shader_parameter("accent", a[3].lerp(b[3], t))


func set_half_width(w: float) -> void:
	_mat.set_shader_parameter("half_width", w)


func _process(delta: float) -> void:
	var vp := get_viewport().get_visible_rect().size
	if camera:
		var z := camera.zoom.x
		_mat.set_shader_parameter("cam_pos", camera.get_screen_center_position())
		_mat.set_shader_parameter("view_size", vp / z)
	else:
		_scroll -= auto_scroll * delta
		_mat.set_shader_parameter("cam_pos", Vector2(0, _scroll))
		_mat.set_shader_parameter("view_size", vp)
		_mat.set_shader_parameter("half_width", 100000.0)
