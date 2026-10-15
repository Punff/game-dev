extends BaseBlock


@export var speed_mult: float = 1.8
var is_boost: bool
var _active: bool = false
var _glow_tween: Tween

func get_block_group() -> String: return "speed_blocks"

func _ready():
	is_boost = randi() % 2 == 0
	super._ready() # Calls _build_block via BaseBlock

func get_default_color() -> Color:
	return Color(0.15, 0.85, 0.2) if is_boost else Color(0.9, 0.15, 0.15)

func update_colors():
	block_color = get_default_color()

func on_block_built():
	var body = get_block_body(); var _hw = hw(); var _hh = hh()
	var z = 1.0 if is_boost else -1.0
	var bolt = Line2D.new(); bolt.name = "Bolt"; bolt.width = 3.0; bolt.default_color = Color(1, 1, 1, 0.8); bolt.antialiased = true
	bolt.points = [Vector2(-_hw * 0.15 + z * 8, -_hh * 0.4), Vector2(_hw * 0.3, 0), Vector2(-_hw * 0.15 + z * 8, _hh * 0.4)]
	body.add_child(bolt)
	
	# Add speed lines shader effect to the surface if possible
	var surface = body.get_node_or_null("ColorRect")
	if surface and surface.material is ShaderMaterial:
		surface.material.set_shader_parameter("density", 60.0)

func _physics_process(_delta: float):
	var _hw = hw(); var _hh = hh()
	var any_on = false
	for p in get_tree().get_nodes_in_group("player"):
		if not is_instance_valid(p): continue
		var dx = abs(p.global_position.x - global_position.x)
		var dy = abs(p.global_position.y - global_position.y)
		var on_block = dx < _hw and dy < _hh + 20
		var key = "on_speed_block_%d" % get_instance_id()
		if on_block:
			any_on = true
			if not p.has_meta(key):
				p.set_meta(key, true)
				p.set_meta("speed_orig_%d" % get_instance_id(), p.speed)
			var orig_key = "speed_orig_%d" % get_instance_id()
			if p.has_meta(orig_key):
				p.speed = p.get_meta(orig_key) * (speed_mult if is_boost else 1.0 / speed_mult)
		elif p.has_meta(key):
			p.remove_meta(key)
			var orig_key = "speed_orig_%d" % get_instance_id()
			if p.has_meta(orig_key):
				p.speed = p.get_meta(orig_key)
				p.remove_meta(orig_key)
	if any_on != _active:
		_active = any_on
		if _active: _start_glow()
		else: _stop_glow()

func _start_glow():
	var surface = get_block_body().get_node_or_null("ColorRect")
	if not surface: return
	if _glow_tween: _glow_tween.kill()
	_glow_tween = create_tween().set_loops()
	var glow = block_color.lightened(0.6)
	var dim = block_color
	_glow_tween.tween_property(surface, "color", glow, 0.4)
	_glow_tween.tween_property(surface, "color", dim, 0.4)

func _stop_glow():
	if _glow_tween: _glow_tween.kill()
	_glow_tween = null
	var surface = get_block_body().get_node_or_null("ColorRect")
	if surface: surface.color = block_color

func on_shockwave(_dir: Vector2, _origin: Vector2, _range: float):
	is_boost = !is_boost
	update_colors()
	set_block_color(block_color)
	play_interact()
	
	var body = get_block_body()
	if not body: return
	var bolt = body.get_node_or_null("Bolt")
	if bolt: bolt.queue_free()
	
	var _hw = hw(); var _hh = hh(); var z = 1.0 if is_boost else -1.0
	var nb = Line2D.new(); nb.name = "Bolt"; nb.width = 3.0; nb.default_color = Color(1, 1, 1, 0.8); nb.antialiased = true
	nb.points = [Vector2(-_hw * 0.15 + z * 8, -_hh * 0.4), Vector2(_hw * 0.3, 0), Vector2(-_hw * 0.15 + z * 8, _hh * 0.4)]
	body.add_child(nb)
