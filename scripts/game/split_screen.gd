class_name SplitScreen
extends CanvasLayer

## Draws GameCamera's views when it splits (see there): one viewport per
## view onto the same world, each with its own sky, pieced together by
## shaders/split_screen.gdshader. While split, the main view stops drawing
## the world (nothing would show of it) and its sky is hidden; the HUD
## stays on top as usual.

const SHADER := preload("res://shaders/split_screen.gdshader")
const MAX_VIEWS := 4
## The world node's layer: the main view drops it while split.
const WORLD_LAYER := 2

var camera: GameCamera
var main_background: Background
var _panes: Array = []   # [{"vp": SubViewport, "cam": Camera2D, "bg": Background}]
var _rect := ColorRect.new()
var _mat := ShaderMaterial.new()
var _on := false


## `world` is drawn by every view; give it to the camera's world, not this.
func setup(cam: GameCamera, background: Background, world: Node2D) -> void:
	camera = cam
	main_background = background
	world.visibility_layer = WORLD_LAYER


func _ready() -> void:
	layer = 1   # over the world, under the HUD
	_mat.shader = SHADER
	_rect.material = _mat
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.visible = false
	add_child(_rect)
	for i in MAX_VIEWS:
		var vp := SubViewport.new()
		vp.world_2d = get_viewport().world_2d
		vp.disable_3d = true
		vp.gui_disable_input = true
		vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		var cam := Camera2D.new()
		cam.ignore_rotation = true
		vp.add_child(cam)
		var bg := Background.new()
		bg.camera = cam
		bg.biome_scale = main_background.biome_scale if main_background else 1.0
		bg.visible = false
		vp.add_child(bg)
		add_child(vp)
		_panes.append({"vp": vp, "cam": cam, "bg": bg})
		_mat.set_shader_parameter("view%d" % i, vp.get_texture())
	get_viewport().size_changed.connect(_fit)
	_fit()
	tree_exiting.connect(func(): _show(false))


## Each view renders the full screen at its real resolution (the shader
## picks which one each pixel comes from).
func _fit() -> void:
	var size: Vector2i = get_viewport().get("size")   # (a Window or a SubViewport)
	var visible := get_viewport().get_visible_rect().size
	for p in _panes:
		p.vp.size = size
		p.vp.size_2d_override = Vector2i(visible)
		p.vp.size_2d_override_stretch = true
	_mat.set_shader_parameter("screen", visible)


func set_height(h: float) -> void:
	for p in _panes:
		p.bg.set_height(h)


func set_half_width(w: float) -> void:
	for p in _panes:
		p.bg.set_half_width(w)


func _physics_process(_delta: float) -> void:
	# (After the camera: it's earlier in the tree.)
	var views := camera.views if camera else []
	_show(views.size() >= 2)
	if not _on:
		return
	var n := mini(views.size(), MAX_VIEWS)
	var sites := PackedVector2Array()
	for i in MAX_VIEWS:
		var p: Dictionary = _panes[i]
		var used := i < n
		p.vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if used else SubViewport.UPDATE_DISABLED
		p.bg.visible = used
		if used:
			p.cam.global_position = views[i].pos
			p.cam.zoom = camera.zoom
			p.cam.offset = camera.offset
			sites.append(views[i].site)
		else:
			sites.append(Vector2(1e6, 1e6))
	_mat.set_shader_parameter("sites", sites)
	_mat.set_shader_parameter("count", n)
	_mat.set_shader_parameter("line", camera.split_amount)


func _show(on: bool) -> void:
	if on == _on:
		return
	_on = on
	_rect.visible = on
	if main_background:
		main_background.visible = not on
	var root := get_viewport()
	if root:
		root.canvas_cull_mask = (0xFFFFFFFF & ~WORLD_LAYER) if on else 0xFFFFFFFF
	if not on:
		for p in _panes:
			p.vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
			p.bg.visible = false
