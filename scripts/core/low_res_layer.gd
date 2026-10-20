class_name LowResLayer
extends Control

## Draws a full-screen shader at a capped resolution and stretches it over
## the screen. For soft, painterly layers (the backdrop, the film grain) the
## difference doesn't show, but the cost does: a browser on a high-DPI screen
## renders 4-9x the pixels of 720p, and these shaders run once per pixel.

var _svp := SubViewport.new()
var _rect := ColorRect.new()
var _view := TextureRect.new()
var _max_pixels := 1280 * 720


## `material` is drawn over the whole layer; `max_pixels` caps its resolution.
func setup(material: Material, max_pixels: int, transparent := false) -> void:
	_max_pixels = max_pixels
	_rect.material = material
	_svp.transparent_bg = transparent


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_svp.disable_3d = true
	_svp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_svp.add_child(_rect)
	add_child(_svp)
	_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view.stretch_mode = TextureRect.STRETCH_SCALE
	_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_view.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_view.texture = _svp.get_texture()
	if _svp.transparent_bg:
		# What lands in a transparent viewport is premultiplied by its alpha.
		var m := CanvasItemMaterial.new()
		m.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
		_view.material = m
	add_child(_view)
	get_viewport().size_changed.connect(_fit)
	_fit()


func _fit() -> void:
	# Real pixels on screen (window size; on the web it includes the DPI scale).
	var px := Vector2(DisplayServer.window_get_size())
	if px.x <= 0.0 or px.y <= 0.0:
		px = get_viewport_rect().size
	var scale := minf(1.0, sqrt(_max_pixels / (px.x * px.y)))
	_svp.size = Vector2i(maxi(16, roundi(px.x * scale)), maxi(16, roundi(px.y * scale)))
