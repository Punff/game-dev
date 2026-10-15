extends BaseBlock


@export var reverse_duration: float = 3.0
@export var effect_radius: float = 80.0

var is_active: bool = false
var affected_players: Array = []
var visual_tween: Tween

func get_block_group() -> String: return "reverse_blocks"
func get_default_color() -> Color: return Color(0.9, 0.15, 0.15)

func on_block_built():
	var body = get_block_body(); var _hw = hw(); var _hh = hh()
	var asz = min(_hw, _hh) * 0.3

	var arrow = Line2D.new(); arrow.width = 2.5; arrow.default_color = Color(1, 1, 1, 0.8); arrow.antialiased = true
	arrow.points = [Vector2(-_hw*0.15, _hh*0.25), Vector2(-_hw*0.15 - asz, _hh*0.25), Vector2(-_hw*0.15 - asz + 4, _hh*0.25 - 4), Vector2(-_hw*0.15 - asz, _hh*0.25), Vector2(-_hw*0.15 - asz + 4, _hh*0.25 + 4)]
	body.add_child(arrow)

	var rarrow = Line2D.new(); rarrow.width = 2.5; rarrow.default_color = Color(1, 1, 1, 0.8); rarrow.antialiased = true
	rarrow.points = [Vector2(_hw*0.15, -_hh*0.25), Vector2(_hw*0.15 + asz, -_hh*0.25), Vector2(_hw*0.15 + asz - 4, -_hh*0.25 - 4), Vector2(_hw*0.15 + asz, -_hh*0.25), Vector2(_hw*0.15 + asz - 4, -_hh*0.25 + 4)]
	body.add_child(rarrow)

	var x = Line2D.new(); x.width = 2.5; x.default_color = Color(1, 0.8, 0); x.antialiased = true
	x.points = [Vector2(-_hw*0.1, -_hh*0.1), Vector2(_hw*0.1, _hh*0.1), Vector2.ZERO, Vector2(-_hw*0.1, _hh*0.1), Vector2(_hw*0.1, -_hh*0.1)]
	body.add_child(x)

	var area = Area2D.new(); area.name = "DetectionArea"
	var acs = CollisionShape2D.new(); var acss = CircleShape2D.new(); acss.radius = effect_radius; acs.shape = acss; area.add_child(acs)
	area.body_entered.connect(_on_player_entered); area.body_exited.connect(_on_player_exited); add_child(area)

func _on_player_entered(body):
	if body is CharacterBody2D and not body in affected_players:
		affected_players.append(body); apply_reverse(body); activate_visual()

func _on_player_exited(body):
	if body is CharacterBody2D and body in affected_players: start_timer(body)

func apply_reverse(p):
	if not p.has_meta("controls_reversed"): p.set_meta("controls_reversed", true)

func start_timer(p):
	var t = Timer.new(); t.wait_time = reverse_duration; t.one_shot = true; t.autostart = true; add_child(t)
	t.timeout.connect(func(): remove_reverse(p); t.queue_free())

func remove_reverse(p):
	if is_instance_valid(p): p.remove_meta("controls_reversed"); affected_players.erase(p)

func activate_visual():
	if not is_active:
		is_active = true
		if visual_tween: visual_tween.kill()
		visual_tween = create_tween().set_loops()
		var border = get_block_body().get_node("Line2D")
		visual_tween.tween_property(border, "default_color", Color(1, 0.8, 0), 0.3)
		visual_tween.tween_property(border, "default_color", Color(0.08, 0.08, 0.1), 0.3)

func receive_force(_o: Vector2, _s: float):
	for p in get_tree().get_nodes_in_group("player"):
		if p.global_position.distance_to(global_position) <= effect_radius and not p in affected_players:
			affected_players.append(p); apply_reverse(p); start_timer(p); activate_visual()

func on_shockwave(_dir: Vector2, _origin: Vector2, _range: float):
	for p in get_tree().get_nodes_in_group("player"):
		if p.global_position.distance_to(_origin) <= _range and not p in affected_players:
			var dot = (p.global_position - _origin).normalized().dot(_dir)
			if dot < 0.3: continue
			affected_players.append(p); apply_reverse(p); start_timer(p)
			activate_visual()

func force_remove_all_effects(): for p in affected_players.duplicate(): remove_reverse(p)

func _draw():
	if Engine.is_editor_hint(): draw_circle(Vector2.ZERO, effect_radius, Color(1, 0, 0, 0.1)); draw_arc(Vector2.ZERO, effect_radius, 0, TAU, 32, Color.RED, 2)
