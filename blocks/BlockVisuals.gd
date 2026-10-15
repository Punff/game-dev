extends Node2D

@onready var block = get_parent()
@onready var sprite = get_parent().get_node_or_null("Sprite2D")

var _noir_shader = preload("res://shaders/block_noir.gdshader")

func _ready():
	if not block is Block:
		queue_free()
		return
	
	z_index = 1
	
	if sprite:
		# Use the stabilized optimized shader
		var mat = ShaderMaterial.new()
		mat.shader = _noir_shader
		mat.set_shader_parameter("outline_width", 2.0)
		mat.set_shader_parameter("outline_color", Color.BLACK)
		mat.set_shader_parameter("shadow_offset", Vector2(6.0, 6.0))
		mat.set_shader_parameter("rim_color", Color(1, 1, 1, 0.4))
		mat.set_shader_parameter("rim_width", 2.0)
		sprite.material = mat
		
		# Set color based on block type and noir palette
		sprite.modulate = _get_block_color()
		
	queue_redraw()

func _get_block_color() -> Color:
	match block.block_id:
		"static_platform": return Color(0.1, 0.1, 0.15)
		"bounce_pad": return Color(0.1, 0.5, 0.2)
		"speed_block": return Color(0.8, 0.6, 0.1)
		"breakable_block": return Color(0.4, 0.2, 0.1)
		"conveyor_block": return Color(0.15, 0.1, 0.3)
		"push_zone": return Color(0.5, 0.3, 0.1)
		"vanishing_block": return Color(0.2, 0.4, 0.5)
		"ice_block": return Color(0.6, 0.8, 0.9)
		"moving_platform": return Color(0.2, 0.2, 0.25)
		"reverse_block": return Color(0.5, 0.1, 0.1)
	return block.tint

func _update_rect_size():
	pass

func _draw():
	var size = Vector2(128, 64)
	var collision = block.get_node_or_null("CollisionShape2D")
	if collision and collision.shape is RectangleShape2D:
		size = collision.shape.size
	
	_draw_symbol(size)

func _draw_symbol(size: Vector2):
	var color = Color.WHITE
	color.a = 0.5
	
	match block.block_id:
		"bounce_pad":
			# Thick zigzag spring
			var points = []
			for i in range(5):
				points.append(Vector2(-20 + i * 10, 10 if i % 2 == 0 else -10))
			draw_polyline(points, color, 3.0)
		"speed_block":
			# Triple chevrons
			for i in range(3):
				var ox = -30 + i * 30
				draw_polyline([Vector2(ox-12, -15), Vector2(ox+12, 0), Vector2(ox-12, 15)], color, 4.0)
		"breakable_block":
			# Stable, thick crack icon
			draw_line(Vector2(-25, -15), Vector2(0, 5), color, 3.0)
			draw_line(Vector2(0, 5), Vector2(25, -20), color, 3.0)
		"conveyor_block":
			# Moving belt dots - SMOOTH
			var dir = block.direction if "direction" in block else 1.0
			var x_off = fmod(Time.get_ticks_msec() * 0.05 * dir, 30)
			for i in range(int(size.x / 30) + 1):
				var x = -size.x/2 - 30 + i * 30 + x_off
				draw_rect(Rect2(x, -18, 12, 4), color)
				draw_rect(Rect2(x, 14, 12, 4), color)
		"push_zone":
			# Thick wave lines - SMOOTH
			var x_off = sin(Time.get_ticks_msec() * 0.005) * 15
			for i in range(2):
				var y = -15 + i * 30
				draw_polyline([Vector2(-30 + x_off, y), Vector2(x_off, y-10), Vector2(30 + x_off, y)], color, 3.0)
		"vanishing_block":
			# Thick dotted frame
			draw_rect(Rect2(-size/2 + Vector2(6,6), size - Vector2(12,12)), color, false, 3.0)
		"ice_block":
			# Large X highlight
			draw_line(Vector2(-20, -20), Vector2(20, 20), color, 3.0)
			draw_line(Vector2(20, -20), Vector2(-20, 20), color, 3.0)
		"static_platform":
			# 4 industrial bolts
			var r = 3.5
			draw_circle(Vector2(-size.x/2 + 15, -size.y/2 + 15), r, color)
			draw_circle(Vector2(size.x/2 - 15, -size.y/2 + 15), r, color)
			draw_circle(Vector2(-size.x/2 + 15, size.y/2 - 15), r, color)
			draw_circle(Vector2(size.x/2 - 15, size.y/2 - 15), r, color)

func _process(_delta):
	# Redraw every frame for smooth, flicker-free movement of symbols
	if block.block_id in ["conveyor_block", "push_zone"]:
		queue_redraw()
