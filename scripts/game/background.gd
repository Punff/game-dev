class_name Background
extends CanvasLayer

## Full-screen procedural sky that tracks a camera and blends palettes
## between biomes as players climb.

const SHADER := preload("res://shaders/background.gdshader")

## [sky_top, sky_bottom, islands, accent] per biome, matching MapPlanner.BIOMES.
const PALETTES := [
	[Color("162130"), Color("5a2622"), Color("0b0a0a"), Color("e3a92c")],   # Rubble: dusk over the slums
	[Color("230c0e"), Color("9a3a1c"), Color("100707"), Color("f0c050")],   # Inferno: burning refinery
	[Color("0b1517"), Color("1f4a48"), Color("060c0c"), Color("ece2c8")],   # Void: cold orbit
	[Color("141416"), Color("44444e"), Color("08080a"), Color("d2532a")],   # Storm: static and rain
]
const BLEND_PX := 2500.0

var camera: Camera2D
var auto_scroll := 0.0         ## px/s, used by menus with no camera
var biome_scale := 1.0         ## see MapPlanner.biome_scale
var _mat := ShaderMaterial.new()
var _scroll := 0.0
var _height := -INF


func _ready() -> void:
	layer = -10
	_mat.shader = SHADER
	# Soft and painterly: rendered at ~720p and stretched, whatever the screen.
	var art := LowResLayer.new()
	art.setup(_mat, 1280 * 720)
	add_child(art)
	set_height(0.0)
	_apply_detail()
	SignalBus.settings_changed.connect(_apply_detail)


func _apply_detail() -> void:
	_mat.set_shader_parameter("detail", 0.0 if Settings.get_value("reduced_effects") else 1.0)


## Blend palettes by climbed height (px above the start floor).
func set_height(h: float) -> void:
	if absf(h - _height) < 4.0:
		return   # nothing visible would change
	_height = h
	var idx := 0
	for i in MapPlanner.BIOMES.size():
		if h >= MapPlanner.biome_from(i, biome_scale):
			idx = i
	var t := 0.0
	if idx + 1 < MapPlanner.BIOMES.size():
		var next_from := MapPlanner.biome_from(idx + 1, biome_scale)
		var blend := BLEND_PX * biome_scale
		t = clampf((h - (next_from - blend)) / blend, 0.0, 1.0)
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
