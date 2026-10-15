extends BaseBlock


@export var ice_friction: float = 0.2
@export var ice_acceleration: float = 5.0
@export var effect_duration: float = 1.0
@export var effect_radius: float = 30.0

var affected_players: Array = []
var ice_tween: Tween

func get_block_group() -> String: return "ice_blocks"
func get_default_color() -> Color: return Color(0.5, 0.9, 1.0)

func on_block_built():
	var body = get_block_body(); var _hw = hw(); var _hh = hh()
	var surface = body.get_node("ColorRect"); surface.color.a = 0.75

	var crystal = Line2D.new(); crystal.width = 1.5; crystal.default_color = Color(1, 1, 1, 0.6); crystal.antialiased = true
	crystal.points = [Vector2(-_hw * 0.3, _hh * 0.15), Vector2(-_hw * 0.12, -_hh * 0.25), Vector2(_hw * 0.2, -_hh * 0.15), Vector2(_hw * 0.3, _hh * 0.2)]
	body.add_child(crystal)

	var frost = Line2D.new(); frost.width = 0.8; frost.default_color = Color(1, 1, 1, 0.2); frost.antialiased = true
	frost.points = [Vector2(-_hw * 0.4, -_hh * 0.3), Vector2(-_hw * 0.25, _hh * 0.1), Vector2(_hw * 0.1, -_hh * 0.2), Vector2(_hw * 0.35, _hh * 0.3)]
	body.add_child(frost)

func receive_force(_o: Vector2, _s: float):
	for p in get_tree().get_nodes_in_group("player"):
		if p.global_position.distance_to(global_position) <= effect_radius and not p in affected_players:
			affected_players.append(p); apply_ice(p); start_timer(p); pulse()

func _physics_process(_delta: float):
	var _hw = hw(); var _hh = hh()
	for p in get_tree().get_nodes_in_group("player"):
		if not is_instance_valid(p): continue
		var dx = abs(p.global_position.x - global_position.x)
		var dy = abs(p.global_position.y - global_position.y)
		if dx < _hw and dy < _hh + 20 and not p in affected_players:
			affected_players.append(p); apply_ice(p); start_timer(p); pulse()

func apply_ice(p):
	if p.has_meta("original_friction"): return
	p.set_meta("original_friction", p.friction); p.set_meta("original_acceleration", p.acceleration)
	p.friction = ice_friction; p.acceleration = ice_acceleration

func start_timer(p):
	var t = Timer.new(); t.wait_time = effect_duration; t.one_shot = true; t.autostart = true; add_child(t)
	t.timeout.connect(func(): remove_ice(p); t.queue_free())

func remove_ice(p):
	if is_instance_valid(p) and p.has_meta("original_friction"):
		p.friction = p.get_meta("original_friction"); p.acceleration = p.get_meta("original_acceleration")
		p.remove_meta("original_friction"); p.remove_meta("original_acceleration"); affected_players.erase(p)

func pulse():
	if ice_tween: ice_tween.kill()
	ice_tween = create_tween().set_loops()
	var surface = get_block_body().get_node("ColorRect")
	ice_tween.tween_property(surface, "color:a", 0.9, 0.8); ice_tween.tween_property(surface, "color:a", 0.6, 0.8)

func force_remove_all_effects(): for p in affected_players.duplicate(): remove_ice(p)

func _draw():
	if Engine.is_editor_hint(): draw_circle(Vector2.ZERO, effect_radius, Color(0, 0.5, 1, 0.1)); draw_arc(Vector2.ZERO, effect_radius, 0, TAU, 32, Color(0, 0.5, 1), 2)
