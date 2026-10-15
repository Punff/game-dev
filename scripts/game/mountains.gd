extends Node2D

var _time: float = 0.0
var _cam: Camera2D
var _vp: Vector2

var _layer_nodes: Array = []

const LAYER_CONFIG = [
	{"peaks": 25, "smooth": 1, "max_h": 140,  "min_h": 40,  "seg_w": 40, "parallax": 0.06, "color_idx": 0},
	{"peaks": 18, "smooth": 0, "max_h": 320,  "min_h": 90,  "seg_w": 90, "parallax": 0.26, "color_idx": 2},
	{"peaks": 10, "smooth": 0, "max_h": 280,  "min_h": 80,  "seg_w": 150, "parallax": 0.55, "color_idx": 4},
]

func _ready():
	z_index = -25
	_vp = get_viewport_rect().size
	var rng = RandomNumberGenerator.new()
	for li in range(LAYER_CONFIG.size()):
		var cfg = LAYER_CONFIG[li]
		rng.seed = 100 + li
		var profiles = []
		for pi in range(2):
			profiles.append(_generate_profile(cfg, rng, pi))
		
		var layer_node = Node2D.new()
		var layer_data = {
			"parallax": cfg.parallax,
			"color": _layer_color(cfg.color_idx),
			"profiles": profiles,
			"offset": rng.randf_range(-_vp.x * 0.3, _vp.x * 0.3)
		}
		layer_node.set_meta("config", layer_data)
		layer_node.draw.connect(_draw_layer.bind(layer_node))
		add_child(layer_node)
		_layer_nodes.append(layer_node)

func _layer_color(idx: int) -> Color:
	match idx:
		0: return Color(0.01, 0.01, 0.04)
		1: return Color(0.02, 0.06, 0.05)
		2: return Color(0.08, 0.02, 0.02)
		3: return Color(0.04, 0.04, 0.05)
		4: return Color(0.02, 0.02, 0.03)
	return Color.BLACK

func _generate_profile(cfg: Dictionary, rng: RandomNumberGenerator, _pi: int) -> Array:
	var total_w = _vp.x + 800
	var count = int(total_w / cfg.seg_w) + 2
	var raw = []
	for i in range(count):
		if rng.randf() > 0.7:
			raw.append(raw[-1] if not raw.is_empty() else rng.randf())
		else:
			raw.append(rng.randf())
			
	for p in range(cfg.smooth):
		var smoothed = [raw[0]]
		for i in range(1, raw.size() - 1):
			smoothed.append((raw[i - 1] + raw[i] + raw[i + 1]) / 3.0)
		smoothed.append(raw[raw.size() - 1])
		raw = smoothed
		
	var heights = []
	for i in range(count):
		var x = i * cfg.seg_w - 400
		var h = raw[i] * (cfg.max_h - cfg.min_h) + cfg.min_h
		heights.append(Vector2(x, h))
	return heights

func _process(delta):
	_time += delta
	_cam = get_viewport().get_camera_2d()
	if not _cam: return
	
	_vp = get_viewport_rect().size
	var cam_pos = _cam.global_position

	for layer_node in _layer_nodes:
		var layer = layer_node.get_meta("config")
		var base_y = _vp.y - cam_pos.y * layer.parallax
		var base_x = layer.offset - cam_pos.x * layer.parallax
		layer_node.position = Vector2(base_x, base_y)

func _draw_layer(layer_node):
	var layer = layer_node.get_meta("config")
	for profile in layer.profiles:
		var poly = PackedVector2Array()
		# Use local coordinates for drawing
		poly.append(Vector2(-1000, 2000)) 
		poly.append(Vector2(-1000, profile[0].y))

		for pt in profile:
			poly.append(pt)

		poly.append(Vector2(2000, 2000))
		layer_node.draw_colored_polygon(poly, layer.color)
