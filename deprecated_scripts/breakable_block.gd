extends BaseBlock


@export_range(4, 16) var fragment_count: int = 6
@export var gravity_scale: float = 0.0
@export var break_threshold: float = 100.0
@export var destruction_timeout: float = 60.0
@export var fragment_collision_layer: int = 1

var _rng = RandomNumberGenerator.new()
var fragments = []

func get_block_group() -> String: return "destructible_blocks"
func get_default_color() -> Color: return Color(0.85, 0.45, 0.2)

func _ready():
	_rng.randomize()
	add_to_group(get_block_group())
	super._ready()

func on_block_built():
	var body = get_block_body()
	var _hw = hw(); var _hh = hh()
	var crack = Line2D.new(); crack.width = 2.5; crack.default_color = Color(0, 0, 0, 0.4)
	crack.antialiased = true
	crack.points = [Vector2(-_hw * 0.3, -_hh * 0.5), Vector2(_rng.randf_range(-_hw*0.1, _hw*0.1), _rng.randf_range(-_hh*0.1, _hh*0.1)), Vector2(_hw * 0.35, _hh * 0.4)]
	body.add_child(crack)

	var surface = body.get_node_or_null("ColorRect")
	if surface and surface.material is ShaderMaterial:
		surface.material.set_shader_parameter("dot_size", 0.5)
		surface.material.set_shader_parameter("dot_color", Color(0, 0, 0, 0.25))

func receive_force(o: Vector2, s: float):
	if not block_active: return
	if s >= break_threshold:
		break_apart(o, s)

func break_apart(o: Vector2, s: float):
	if not block_active: return

	var orig = get_node_or_null("Block")
	if orig: orig.queue_free(); block_active = false

	var hw = block_size.x / 2
	var hh = block_size.y / 2

	var points = []
	for i in range(fragment_count):
		points.append(Vector2(
			_rng.randf_range(-hw + 8, hw - 8),
			_rng.randf_range(-hh + 8, hh - 8)
		))

	var base_radius = sqrt(block_size.x * block_size.y / fragment_count / PI) * 1.5
	for idx in range(points.size()):
		var c = points[idx]
		var is_platform = idx == 0
		var radius = base_radius * (1.1 if is_platform else 0.9)
		var verts = _rng.randi_range(8, 12) if is_platform else _rng.randi_range(5, 8)
		var pts = []
		for j in range(verts):
			var a = TAU * j / verts
			var rv = _rng.randf_range(0.85, 1.15) if is_platform else _rng.randf_range(0.7, 1.3)
			var pt = c + Vector2(cos(a), sin(a)) * radius * rv
			pt.x = clamp(pt.x, -hw, hw)
			pt.y = clamp(pt.y, -hh, hh)
			pts.append(pt)
		pts.sort_custom(func(a, b): return atan2(a.y - c.y, a.x - c.x) < atan2(b.y - c.y, b.x - c.x))
		if pts.size() >= 3:
			create_fragment(PackedVector2Array(pts), o, s, is_platform)

	var tween = create_tween()
	tween.tween_property(self, "modulate", Color.CYAN, 0.04)
	tween.tween_property(self, "modulate", Color.MAGENTA, 0.04)
	tween.tween_property(self, "modulate", Color.WHITE, 0.04)

func create_fragment(pts, o: Vector2, s: float, is_platform: bool = false):
	var f = RigidBody2D.new()
	f.gravity_scale = gravity_scale
	f.collision_layer = 0
	f.collision_mask = 1
	f.add_to_group("fragments")

	if is_platform:
		f.mass = 30.0
		f.lock_rotation = true
		f.linear_damp = 4.0
		f.angular_damp = 20.0
	else:
		f.mass = 5.0
		f.linear_damp = 2.0
		f.angular_damp = 12.0

	for ef in get_tree().get_nodes_in_group("fragments"):
		if ef != f:
			f.add_collision_exception_with(ef)

	add_polygon(f, pts, block_color.darkened(0.5)).position = Vector2(0, 3)
	if is_platform:
		var face = add_polygon(f, pts, block_color); face.name = "Polygon2D"
		var hl = PackedVector2Array(); for p in pts: hl.append(p * 0.8)
		add_polygon(f, hl, Color(1, 1, 1, 0.25))
		var cp = PackedVector2Array(pts); cp.append(pts[0]); add_line(f, cp, Color(0.08,0.08,0.1), 2.0)
	else:
		var tint = randf_range(0.8, 1.0)
		var face = add_polygon(f, pts, block_color * Color(tint, tint, tint)); face.name = "Polygon2D"
		var hl = PackedVector2Array(); for p in pts: hl.append(p * 0.6)
		add_polygon(f, hl, Color(1, 1, 1, 0.1))
		var cp = PackedVector2Array(pts); cp.append(pts[0]); add_line(f, cp, Color(0.08,0.08,0.1), 1.0)
	var col = CollisionPolygon2D.new(); col.polygon = pts; f.add_child(col)
	var wp = global_position + get_polygon_center(pts)
	get_tree().current_scene.add_child(f); f.global_position = wp
	f.set_deferred("collision_layer", fragment_collision_layer)
	f.set_meta("source_pos", global_position)

	fragments.append(f)

	var dir = (wp - o).normalized()
	var impulse = Vector2(dir.x * randf_range(0.03, 0.08), -randf_range(0.03, 0.08)) * s
	f.apply_central_impulse(impulse)

	if is_platform:
		f.angular_velocity = 0.0
	else:
		f.angular_velocity = randf_range(-3.0, 3.0)
		get_tree().create_timer(destruction_timeout * 0.3).timeout.connect(func(): fade_out_fragment(f))

	get_tree().create_timer(destruction_timeout).timeout.connect(func(): fade_out_fragment(f))

func fade_out_fragment(f):
	if not is_instance_valid(f): return
	if f.has_meta("controlling_player"):
		get_tree().create_timer(5.0).timeout.connect(func(): fade_out_fragment(f))
		return

	var tween = create_tween()
	var poly = f.get_node_or_null("Polygon2D")
	if poly: tween.tween_property(poly, "modulate:a", 0.0, 1.0)
	await tween.finished
	fragments.erase(f)
	if is_instance_valid(f): f.queue_free()

func get_polygon_center(pts):
	var s = Vector2.ZERO; for p in pts: s += p; return s / pts.size()
