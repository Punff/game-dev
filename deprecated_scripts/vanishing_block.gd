extends BaseBlock


@export var stable_time: float = 1.5
@export var vanish_time: float = 0.5
@export var reappear_time: float = 6.0

var _players_on: int = 0
var _vanish_tween: Tween
var _is_vanished: bool = false
var _detector: Area2D

func get_block_group() -> String: return "vanishing_blocks"
func get_default_color() -> Color: return Color(1.0, 0.6, 0.1)

func on_block_built():
	var body = get_block_body()
	if not body: return
	var _hw = hw(); var _hh = hh()
	add_line(body, [Vector2(-_hw * 0.2, -_hh * 0.15), Vector2(-_hw * 0.05, _hh * 0.05), Vector2(-_hw * 0.15, _hh * 0.15)], Color(1,1,1,0.2), 1.0)
	add_line(body, [Vector2(_hw * 0.2, -_hh * 0.15), Vector2(_hw * 0.05, _hh * 0.05), Vector2(_hw * 0.15, _hh * 0.15)], Color(1,1,1,0.2), 1.0)

	_detector = Area2D.new(); _detector.name = "VanishDetector"
	var acs = CollisionShape2D.new()
	var acss = RectangleShape2D.new(); acss.size = block_size + Vector2(10, 10)
	acs.shape = acss; acs.position = Vector2(0, -5)
	_detector.add_child(acs)
	_detector.body_entered.connect(_on_body_entered)
	_detector.body_exited.connect(_on_body_exited)
	add_child(_detector)

func _on_body_entered(body):
	if _is_vanished: return
	if not body is CharacterBody2D: return
	_players_on += 1
	if _players_on == 1:
		start_vanish_timer()

func _on_body_exited(body):
	if _is_vanished: return
	if not body is CharacterBody2D: return
	_players_on = max(_players_on - 1, 0)
	if _players_on == 0:
		cancel_vanish()

func start_vanish_timer():
	if _vanish_tween: _vanish_tween.kill()
	_vanish_tween = create_tween().set_parallel()
	_vanish_tween.tween_callback(_do_vanish).set_delay(stable_time)

	var body = get_block_body()
	if body:
		var surface = body.get_node_or_null("ColorRect")
		if surface:
			_vanish_tween.tween_property(surface, "color", Color(1, 0.2, 0.05, 1), stable_time * 0.8)

func cancel_vanish():
	if _vanish_tween:
		_vanish_tween.kill()
		_vanish_tween = null
	var body = get_block_body()
	if body:
		var surface = body.get_node_or_null("ColorRect")
		if surface:
			surface.color = get_default_color()

func _do_vanish():
	if _is_vanished: return
	_is_vanished = true
	_detector.queue_free()
	_detector = null

	var body = get_block_body()
	if body:
		var tween = create_tween().set_parallel()
		tween.tween_property(body, "modulate", Color(1, 1, 1, 0), vanish_time)
		tween.tween_property(body, "position", Vector2(0, -8), vanish_time * 0.5)
		await tween.finished
		body.set_collision_layer(0)
		body.set_collision_mask(0)

	await get_tree().create_timer(reappear_time).timeout
	reappear()

func reappear():
	_is_vanished = false
	var body = get_block_body()
	if body:
		body.modulate = Color(1, 1, 1, 0)
		body.position = Vector2.ZERO
		body.set_collision_layer(1)
		body.set_collision_mask(1)
		var tween = create_tween()
		tween.tween_property(body, "modulate", Color(1, 1, 1, 1), 0.3)
		await tween.finished

	if not _detector:
		_remake_detector()

func _remake_detector():
	_detector = Area2D.new(); _detector.name = "VanishDetector"
	var acs = CollisionShape2D.new()
	var acss = RectangleShape2D.new(); acss.size = block_size + Vector2(10, 10)
	acs.shape = acss; acs.position = Vector2(0, -5)
	_detector.add_child(acs)
	_detector.body_entered.connect(_on_body_entered)
	_detector.body_exited.connect(_on_body_exited)
	add_child(_detector)
