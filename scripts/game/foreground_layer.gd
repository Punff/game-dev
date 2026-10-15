extends Node2D

var _time: float = 0.0
var _cam: Camera2D
var _vp: Vector2
var _debris: Array = []
var _cliffs: Array = []

func _ready():
	z_index = -10
	_vp = get_viewport_rect().size
	var rng = RandomNumberGenerator.new()
	rng.seed = 99
	for i in range(30):
		_debris.append({
			"ox": rng.randf_range(0, _vp.x),
			"oy": rng.randf_range(-_vp.y, _vp.y),
			"s": rng.randf_range(2, 5),
			"sp": rng.randf_range(0.5, 2.0),
			"p": rng.randf_range(0, TAU),
			"drift": rng.randf_range(-10, 10),
		})
	rng.seed = 55
	for ci in range(6):
		var pts = []
		var cx = rng.randf_range(0, _vp.x)
		for vi in range(5):
			pts.append(Vector2(
				vi * 40 - 80 + rng.randf_range(-10, 10),
				rng.randf_range(-60, -10)
			))
		_cliffs.append({"x": cx, "pts": pts, "phase": rng.randf_range(0, TAU)})

func _process(delta):
	_time += delta
	_cam = get_viewport().get_camera_2d()
	_vp = get_viewport_rect().size
	for d in _debris:
		d.oy += d.drift * delta
		if d.oy > _vp.y:
			d.oy = -_vp.y * 0.2
			d.ox = randf_range(0, _vp.x)
	queue_redraw()

func _draw():
	if not _cam: return
	var cam_pos = _cam.global_position
	var cx = cam_pos.x * 0.7
	var cy = cam_pos.y * 0.7

	# Dark Jade Cliff Silhouettes
	var cliff_color = Color(0.01, 0.04, 0.03, 0.6)
	for c in _cliffs:
		var bx = c.x - cx
		var by = _vp.y - cy
		while bx < -200: bx += _vp.x
		while bx > _vp.x + 200: bx -= _vp.x
		var poly = PackedVector2Array()
		poly.append(Vector2(bx - 80, _vp.y + 30))
		for pt in c.pts:
			poly.append(Vector2(bx + pt.x, by + pt.y))
		poly.append(Vector2(bx + 80, _vp.y + 30))
		draw_colored_polygon(poly, cliff_color)

	# Muted Sepia Debris
	for d in _debris:
		var sx = d.ox - cx
		var sy = d.oy - cy
		while sx < -10: sx += _vp.x
		while sx > _vp.x + 10: sx -= _vp.x
		while sy < -10: sy += _vp.y
		while sy > _vp.y + 10: sy -= _vp.y
		var c = Color(0.2, 0.15, 0.1, 0.3 + sin(_time * d.sp + d.p) * 0.15)
		draw_circle(Vector2(sx, sy), d.s, c)
