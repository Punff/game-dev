extends Node2D

var _time: float = 0.0
var _cam: Camera2D
var _vp: Vector2

var _stars_deep: Array = []
var _stars_mid: Array = []
var _stars_bright: Array = []
var _nebula: Array = []
var _moon_phase: float = 0.0
var _moon_base_x: float
var _moon_base_y: float

var _sky_canvas: Node2D
var _nebula_container: Node2D
var _stars_deep_container: Node2D
var _stars_mid_container: Node2D
var _stars_bright_container: Node2D
var _moon: Node2D

func _ready():
	z_index = -35
	_vp = get_viewport_rect().size
	_moon_base_x = _vp.x * 0.25
	_moon_base_y = _vp.y * 0.1

	var rng = RandomNumberGenerator.new()
	rng.seed = 42
	
	_setup_static_layers()
	_init_nebula(rng)
	_init_stars(rng)
	_init_moon()

func _setup_static_layers():
	_sky_canvas = Node2D.new()
	_sky_canvas.draw.connect(_draw_sky_gradient)
	add_child(_sky_canvas)

func _init_nebula(rng):
	_nebula_container = Node2D.new()
	add_child(_nebula_container)
	for i in range(6):
		var n = {
			"ox": rng.randf_range(-_vp.x * 0.5, _vp.x * 1.5),
			"oy": rng.randf_range(-_vp.y, _vp.y * 2),
			"w": rng.randf_range(200, 500),
			"h": rng.randf_range(80, 200),
			"c": Color.from_hsv(rng.randf_range(0.55, 0.75), 0.5, 0.12, 0.08)
		}
		var sprite = Node2D.new()
		sprite.set_meta("config", n)
		sprite.draw.connect(_draw_single_nebula.bind(sprite))
		_nebula_container.add_child(sprite)

func _init_stars(rng):
	_stars_deep_container = Node2D.new()
	_stars_mid_container = Node2D.new()
	_stars_bright_container = Node2D.new()
	add_child(_stars_deep_container)
	add_child(_stars_mid_container)
	add_child(_stars_bright_container)
	
	_create_star_batch(_stars_deep, 300, 0.3, 1.2, _stars_deep_container, rng)
	_create_star_batch(_stars_mid, 120, 1.5, 3.0, _stars_mid_container, rng, true)
	_create_star_batch(_stars_bright, 25, 3.0, 6.0, _stars_bright_container, rng)

func _create_star_batch(stars_array, count, s_min, s_max, container, rng, mid=false):
	for i in range(count):
		var s = {
			"ox": rng.randf_range(-_vp.x, _vp.x * 2),
			"oy": rng.randf_range(-_vp.y * 2, _vp.y * 3),
			"s": rng.randf_range(s_min, s_max),
			"p": rng.randf_range(0, TAU),
			"sp": rng.randf_range(0.3, 1.5)
		}
		if mid:
			s["c"] = Color.from_hsv(rng.randf_range(0.55, 0.7), 0.3, 0.9)
		
		var star_node = Node2D.new()
		star_node.set_meta("config", s)
		star_node.draw.connect(_draw_single_star.bind(star_node))
		container.add_child(star_node)
		stars_array.append(s)

func _init_moon():
	_moon = Node2D.new()
	_moon.draw.connect(_draw_moon_internal)
	add_child(_moon)

func _process(delta):
	_time += delta
	_moon_phase += delta * 0.015
	_cam = get_viewport().get_camera_2d()
	if not _cam: return
	
	var cam_pos = _cam.global_position
	
	_update_nebula(cam_pos)
	_update_stars(_stars_deep_container, 0.01, cam_pos)
	_update_stars(_stars_mid_container, 0.03, cam_pos)
	_update_stars(_stars_bright_container, 0.06, cam_pos)
	_update_moon(cam_pos)

func _update_nebula(cam_pos):
	for sprite in _nebula_container.get_children():
		var n = sprite.get_meta("config")
		var sy = n.oy + cam_pos.y * 0.02
		while sy < -n.h: sy += _vp.y * 2
		while sy > _vp.y + n.h: sy -= _vp.y * 2
		var sx = n.ox + cam_pos.x * 0.02
		while sx < -n.w: sx += _vp.x
		while sx > _vp.x + n.w: sx -= _vp.x
		sprite.position = Vector2(sx, sy)
		sprite.queue_redraw()

func _update_stars(container, parallax, cam_pos):
	var x_par = cam_pos.x * parallax
	var y_par = cam_pos.y * parallax
	for star_node in container.get_children():
		var s = star_node.get_meta("config")
		var sx = s.ox + x_par
		var sy = s.oy + y_par
		while sx < -10: sx += _vp.x * 2
		while sx > _vp.x + 10: sx -= _vp.x * 2
		while sy < -10: sy += _vp.y * 2
		while sy > _vp.y + 10: sy -= _vp.y * 2
		star_node.position = Vector2(sx, sy)
		star_node.queue_redraw()

func _update_moon(cam_pos):
	var mx = _moon_base_x + cam_pos.x * 0.03
	var my = _moon_base_y + cam_pos.y * 0.03
	while mx < -100: mx += _vp.x
	while mx > _vp.x + 100: mx -= _vp.x
	while my < -100: my += _vp.y * 2
	while my > _vp.y + 100: my -= _vp.y * 2
	my += sin(_moon_phase) * 40
	mx += cos(_moon_phase * 0.6) * 25
	_moon.position = Vector2(mx, my)

func _draw_sky_gradient():
	var top = Color(0.02, 0.02, 0.08)
	var mid = Color(0.04, 0.03, 0.05)
	var bot = Color(0.15, 0.08, 0.05)
	var bands = 60
	var band_h = _vp.y / bands
	for y in range(bands):
		var t = (y + 0.5) / bands
		var c = top.lerp(mid, t * 1.5) if t < 0.6 else mid.lerp(bot, (t - 0.6) * 2.5)
		_sky_canvas.draw_rect(Rect2(0, y * band_h, _vp.x, ceil(band_h) + 1), c)

func _draw_single_nebula(sprite):
	var n = sprite.get_meta("config")
	for i in 3:
		var c = n.c
		if hash(Vector2(n.ox, n.oy)) > 0.5:
			c = Color(0.04, 0.12, 0.1, 0.05)
		else:
			c = Color(0.2, 0.05, 0.05, 0.05)
		var off = Vector2(sin(_time * 0.1 + i) * 40, cos(_time * 0.08 + i * 2) * 20)
		sprite.draw_set_transform(off, 0, Vector2(n.w * 0.4, n.h * 0.15))
		sprite.draw_circle(Vector2.ZERO, 1.0, c)

func _draw_single_star(star_node):
	var s = star_node.get_meta("config")
	var twinkle = 0.4 + sin(_time * s.sp + s.p) * 0.6
	var c = Color(0.7, 0.8, 1.0)
	if hash(Vector2(s.ox, s.oy)) > 0.7:
		c = Color(1.0, 0.8, 0.4)
	c.a = twinkle * 0.6
	var r = s.s * (0.5 + twinkle * 0.5)
	star_node.draw_circle(Vector2.ZERO, r, c)

func _draw_moon_internal():
	_moon.draw_circle(Vector2.ZERO, 80, Color(0.2, 0.25, 0.4, 0.03))
	_moon.draw_circle(Vector2.ZERO, 55, Color(0.3, 0.35, 0.5, 0.05))
	_moon.draw_circle(Vector2.ZERO, 35, Color(0.5, 0.55, 0.7, 0.1))
	_moon.draw_circle(Vector2.ZERO, 22, Color(0.7, 0.75, 0.85, 0.8))
	_moon.draw_circle(Vector2.ZERO, 20, Color(0.85, 0.88, 0.95, 0.5))
	var rng = RandomNumberGenerator.new()
	rng.seed = 7
	for i in range(8):
		var cx = rng.randf_range(-14, 14)
		var cy = rng.randf_range(-14, 14)
		if Vector2(cx, cy).length() > 16: continue
		_moon.draw_circle(Vector2(cx, cy), rng.randf_range(1.5, 4), Color(0.3, 0.35, 0.45, 0.4))
