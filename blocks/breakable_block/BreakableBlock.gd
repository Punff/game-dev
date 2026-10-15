class_name BreakableBlock extends Block

@export_range(4, 16) var fragment_count: int = 6
@export var break_threshold: float = 100.0
@export var destruction_timeout: float = 60.0
@export var fragment_collision_layer: int = 1

var _rng = RandomNumberGenerator.new()
var fragments = []
var _block_size: Vector2 = Vector2(128, 64)
var _block_active = true

static var _break_count_this_window: int = 0
static var _chain_timer: Timer

func _ready() -> void:
	super._ready()
	_rng.randomize()
	block_id = "breakable_block"
	block_category = "trigger"
	spawn_weight = 1.0
	add_to_group("destructible_blocks")

func receive_force(o: Vector2, s: float) -> void:
	if not _block_active: return
	if s >= break_threshold:
		break_apart(o, s)

func on_shockwave(_dir: Vector2, _origin: Vector2, _range: float) -> void:
	break_apart(_origin, 1000.0)

func set_block_size(new_size: Vector2) -> void:
	super.set_block_size(new_size)
	_block_size = new_size

func break_apart(o: Vector2, s: float) -> void:
	if not _block_active: return
	_block_active = false
	
	SignalBus.block_broken.emit(global_position)
	_track_chain_reaction()
	
	# Hide the main block
	visible = false
	# Disable collision
	set_collision_layer_value(1, false)

	var hw = _block_size.x / 2
	var hh = _block_size.y / 2

	var points = []
	for i in range(fragment_count):
		points.append(Vector2(
			_rng.randf_range(-hw + 8, hw - 8),
			_rng.randf_range(-hh + 8, hh - 8)
		))

	var base_radius = sqrt(_block_size.x * _block_size.y / fragment_count / PI) * 1.5
	for idx in range(points.size()):
		var c = points[idx]
		var radius = base_radius * _rng.randf_range(0.85, 1.15)
		var verts = _rng.randi_range(5, 9)
		var pts = []
		for j in range(verts):
			var a = TAU * j / verts
			var rv = _rng.randf_range(0.7, 1.3)
			var pt = c + Vector2(cos(a), sin(a)) * radius * rv
			pt.x = clamp(pt.x, -hw, hw)
			pt.y = clamp(pt.y, -hh, hh)
			pts.append(pt)
		pts.sort_custom(func(a, b): return atan2(a.y - c.y, a.x - c.x) < atan2(b.y - c.y, b.x - c.x))
		if pts.size() >= 3:
			create_fragment(PackedVector2Array(pts), o, s)

	# Small delay before full removal
	get_tree().create_timer(destruction_timeout + 5.0).timeout.connect(queue_free)

func create_fragment(pts: PackedVector2Array, o: Vector2, s: float) -> void:
	var f = RigidBody2D.new()
	f.gravity_scale = 0.0
	f.mass = 8.0
	f.linear_damp = 2.5
	f.angular_damp = 4.0
	f.collision_layer = 0
	f.collision_mask = 1
	f.add_to_group("fragments")
	f.set_meta("rideable", true)

	# Cinematic Drop Shadow: A solid black poly offset by a few pixels
	var shadow = Polygon2D.new()
	shadow.polygon = pts
	shadow.color = Color.BLACK
	shadow.position = Vector2(4, 4) # Hard-edged offset
	f.add_child(shadow)

	var face = Polygon2D.new()
	face.polygon = pts
	var tint_v = _rng.randf_range(0.82, 1.0)
	# Use the noir palette burgundy/sepia
	var base_col = Color(0.4, 0.2, 0.1) # Muted Sepia
	face.color = base_col * Color(tint_v, tint_v, tint_v)
	f.add_child(face)
	
	var col = CollisionPolygon2D.new()
	col.polygon = pts
	f.add_child(col)

	var wp = global_position + _get_polygon_center(pts)
	get_tree().current_scene.add_child(f)
	f.global_position = wp
	f.set_deferred("collision_layer", fragment_collision_layer)
	
	var away = (wp - o).normalized()
	f.linear_velocity = Vector2(
		away.x * _rng.randf_range(30.0, 70.0),
		-_rng.randf_range(60.0, 140.0)
	)
	f.angular_velocity = _rng.randf_range(-5.0, 5.0)

	get_tree().create_timer(destruction_timeout).timeout.connect(func(): _fade_out_fragment(f))

func _track_chain_reaction() -> void:
	_break_count_this_window += 1
	
	if not _chain_timer:
		_chain_timer = Timer.new()
		_chain_timer.wait_time = 0.2
		_chain_timer.one_shot = true
		Engine.get_main_loop().current_scene.add_child(_chain_timer)
		_chain_timer.timeout.connect(_on_chain_window_finished)
	
	_chain_timer.start()

func _on_chain_window_finished() -> void:
	if _break_count_this_window >= 3:
		SignalBus.chain_reaction_occurred.emit(_break_count_this_window)
	_break_count_this_window = 0

func _fade_out_fragment(f: RigidBody2D) -> void:
	if not is_instance_valid(f): return
	var tween = f.create_tween()
	tween.tween_property(f, "modulate:a", 0.0, 1.0)
	tween.finished.connect(f.queue_free)

func _get_polygon_center(pts: PackedVector2Array) -> Vector2:
	var sum = Vector2.ZERO
	for p in pts: sum += p
	return sum / pts.size()
