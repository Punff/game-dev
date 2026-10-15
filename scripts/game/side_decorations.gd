extends Node2D

var _cam: Camera2D
var _vp: Vector2
var _time: float = 0.0

var side_colors = [
	Color(0.01, 0.01, 0.05),
	Color(0.02, 0.03, 0.06),
	Color(0.03, 0.02, 0.04)
]

var _layer_containers: Array = []

func _ready():
	z_index = -20
	_vp = get_viewport_rect().size
	var rng = RandomNumberGenerator.new()
	rng.seed = 888
	# Generate silhouettes for both sides
	for side in [-1, 1]:
		for layer in range(2): # Reduced from 3
			var container = Node2D.new()
			add_child(container)

			var count = 6 # Reduced from 12
			var start_x = side * (850 + layer * 200)

			for i in range(count):
				var h = rng.randf_range(300, 700)
				var w = rng.randf_range(200, 450)
				var pos_y = rng.randf_range(-1200, 1200)

				var s_config = {
					"ox": start_x + rng.randf_range(-100, 100),
					"oy": pos_y,
					"w": w,
					"h": h,
					"color": side_colors[layer],
					"parallax": 0.15 + layer * 0.2,
					"side": side,
					"has_light": (rng.randi() % 10 > 8)
				}

				var structure_node = Node2D.new()
				structure_node.set_meta("config", s_config)
				structure_node.draw.connect(_draw_structure.bind(structure_node))
				container.add_child(structure_node)

				_layer_containers.append(structure_node)

func _process(delta):
	_time += delta
	_cam = get_viewport().get_camera_2d()
	if not _cam: return

	var cam_pos = _cam.global_position

	for node in _layer_containers:
		var s = node.get_meta("config")
		var sy = s.oy - cam_pos.y * s.parallax
		while sy < -s.h - 500: sy += 2500
		while sy > _vp.y + 500: sy -= 2500
		var sx = s.ox - cam_pos.x * s.parallax
		node.position = Vector2(sx, sy)
		# OPTIMIZATION: Removed per-frame queue_redraw()

func _draw_structure(node):
	var s = node.get_meta("config")
	var points = PackedVector2Array([
		Vector2(-s.w/2, s.h * 2),
		Vector2(-s.w/2, 20),
		Vector2(-s.w/4, 0),
		Vector2(s.w/4, 0),
		Vector2(s.w/2, 40),
		Vector2(s.w/2, s.h * 2)
	])
	node.draw_colored_polygon(points, s.color)

	if s.has_light:
		# Static lights for performance
		var l_col = Color(1.0, 0.9, 0.2, 0.3)
		node.draw_rect(Rect2(-5, 100, 10, 15), l_col)
