
extends Node2D

const HALFTONE_SHADER = preload("res://shaders/halftone.gdshader")
const SKETCHY_SHADER = preload("res://shaders/sketchy_outline.gdshader")

@export var block_size: Vector2 = Vector2(256, 64): set = set_block_size
@export var block_color: Color = Color(0.45, 0.45, 0.48): set = set_block_color
@export var border_color: Color = Color(0.08, 0.08, 0.1): set = set_border_color
@export var border_width: float = 4.0
@export var highlight_amount: float = 0.3

var block_active = true
var _interact_tween: Tween

func _ready():
	block_color = get_default_color(); border_color = get_default_border_color()
	add_to_group(get_block_group())
	_build_block()

func get_block_group() -> String: return "blocks"
func get_default_color() -> Color: return Color(0.45, 0.45, 0.48)
func get_default_border_color() -> Color: return Color(0.08, 0.08, 0.1)

func hw() -> float: return block_size.x / 2
func hh() -> float: return block_size.y / 2

func _build_block():
	var body = StaticBody2D.new(); body.name = "Block"

	var shape = RectangleShape2D.new(); shape.size = block_size
	var collision = CollisionShape2D.new(); collision.shape = shape; body.add_child(collision)

	var _hw = hw(); var _hh = hh()

	# Main Surface
	var surface = ColorRect.new()
	surface.name = "ColorRect"
	surface.size = block_size; surface.position = Vector2(-_hw, -_hh)
	surface.color = block_color
	
	# Apply Halftone Shader
	var mat = ShaderMaterial.new()
	mat.shader = HALFTONE_SHADER
	mat.set_shader_parameter("density", 40.0)
	mat.set_shader_parameter("dot_size", 0.4)
	mat.set_shader_parameter("dot_color", Color(0, 0, 0, 0.15))
	surface.material = mat
	body.add_child(surface)

	# Highlight
	var hl_height = max(4.0, block_size.y * 0.12)
	var highlight = ColorRect.new()
	highlight.name = "Highlight"
	highlight.size = Vector2(block_size.x, hl_height); highlight.position = Vector2(-_hw, -_hh)
	highlight.color = block_color.lightened(highlight_amount)
	body.add_child(highlight)

	# Sketchy Border (using a slightly larger ColorRect with shader)
	var border = ColorRect.new()
	border.name = "Border"
	border.size = block_size + Vector2(border_width * 2, border_width * 2)
	border.position = Vector2(-_hw - border_width, -_hh - border_width)
	border.color = Color(0, 0, 0, 0) # Base color doesn't matter much as shader draws outline
	
	var border_mat = ShaderMaterial.new()
	border_mat.shader = SKETCHY_SHADER
	border_mat.set_shader_parameter("outline_width", border_width)
	border_mat.set_shader_parameter("outline_color", border_color)
	border_mat.set_shader_parameter("noise_strength", 1.5)
	border_mat.set_shader_parameter("speed", 2.0)
	border.material = border_mat
	body.add_child(border)
	
	# Ensure proper draw order
	body.move_child(border, 0)

	add_child(body)
	on_block_built()

func play_interact():
	var body = get_block_body()
	if not body: return
	
	if _interact_tween: _interact_tween.kill()
	_interact_tween = create_tween().set_parallel(true)
	
	_interact_tween.tween_property(body, "scale", Vector2(1.08, 0.85), 0.06)
	_interact_tween.tween_property(body, "scale", Vector2.ONE, 0.18).set_delay(0.06)
	
	# Quick flash
	var surface = body.get_node_or_null("ColorRect")
	if surface:
		var flash_c = surface.color.lightened(0.5)
		_interact_tween.tween_property(surface, "color", flash_c, 0.04)
		_interact_tween.tween_property(surface, "color", block_color, 0.12).set_delay(0.04)
	
	if surface and surface.material is ShaderMaterial:
		var mat = surface.material
		var orig_dot = mat.get_shader_parameter("dot_size")
		_interact_tween.tween_method(func(v): 
			if is_instance_valid(surface) and is_instance_valid(mat):
				mat.set_shader_parameter("dot_size", v), 
			0.8, orig_dot, 0.2)

func on_block_built(): pass

func get_block_body() -> Node: return get_node_or_null("Block")

func set_block_size(v: Vector2):
	block_size = v; _refresh_visuals()
func set_block_color(v: Color):
	block_color = v; _refresh_visuals()
func set_border_color(v: Color):
	border_color = v; _refresh_visuals()

func _refresh_visuals():
	var body = get_block_body(); if not body: return
	var shape_node = body.get_node_or_null("CollisionShape2D")
	if shape_node and shape_node.shape is RectangleShape2D: shape_node.shape.size = block_size
	
	var _hw = hw(); var _hh = hh()
	
	var surface = body.get_node_or_null("ColorRect")
	if surface:
		surface.size = block_size; surface.position = Vector2(-_hw, -_hh); surface.color = block_color
	
	var highlight = body.get_node_or_null("Highlight")
	if highlight:
		var hl_height = max(4.0, block_size.y * 0.12)
		highlight.size = Vector2(block_size.x, hl_height); highlight.position = Vector2(-_hw, -_hh)
		highlight.color = block_color.lightened(highlight_amount)
		
	var border = body.get_node_or_null("Border")
	if border:
		border.size = block_size + Vector2(border_width * 2, border_width * 2)
		border.position = Vector2(-_hw - border_width, -_hh - border_width)

func add_line(parent: Node, pts: Array, color: Color, width: float = 1.5) -> Line2D:
	var l = Line2D.new(); l.points = pts; l.width = width; l.default_color = color; l.antialiased = true; parent.add_child(l); return l

func add_rect(parent: Node, sz: Vector2, pos: Vector2, col: Color) -> ColorRect:
	var r = ColorRect.new(); r.size = sz; r.position = pos; r.color = col; parent.add_child(r); return r

func add_polygon(parent: Node, pts: PackedVector2Array, col: Color) -> Polygon2D:
	var p = Polygon2D.new(); p.polygon = pts; p.color = col; parent.add_child(p); return p

func add_collision(parent: Node, sz: Vector2) -> CollisionShape2D:
	var shape = RectangleShape2D.new(); shape.size = sz
	var c = CollisionShape2D.new(); c.shape = shape; parent.add_child(c); return c

func receive_force(_origin: Vector2, _strength: float): pass
func on_shockwave(_dir: Vector2, _origin: Vector2, _range: float): pass

func play_impact():
	play_interact()
	var body = get_block_body(); if not body: return
	var tween = create_tween().set_parallel(true)
	tween.tween_property(body, "position", Vector2(3, 0), 0.04)
	tween.tween_property(body, "position", Vector2(-3, 0), 0.04).set_delay(0.04)
	tween.tween_property(body, "position", Vector2.ZERO, 0.04).set_delay(0.08)
