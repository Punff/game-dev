extends BaseBlock
class_name BouncyBlock

@export var bounce_force: float = 800.0
var bounce_tween: Tween

func get_block_group() -> String: return "bouncy_blocks"
func get_default_color() -> Color: return Color(0.15, 0.85, 0.3)

func on_block_built():
	var body = get_block_body(); var _hw = hw(); var _hh = hh()
	add_line(body, [Vector2(-_hw * 0.12, -_hh * 0.1), Vector2(_hw * 0.12, _hh * 0.1)], Color(0.08, 0.5, 0.15), 2.0)
	add_line(body, [Vector2(-_hw * 0.12, _hh * 0.1), Vector2(_hw * 0.12, -_hh * 0.1)], Color(0.08, 0.5, 0.15), 2.0)

	var area = Area2D.new(); area.name = "LandingDetector"
	var acs = CollisionShape2D.new(); var acss = RectangleShape2D.new()
	acss.size = Vector2(block_size.x + 20, block_size.y * 0.2)
	acs.shape = acss; acs.position = Vector2(0, -block_size.y * 0.44)
	area.add_child(acs)
	area.body_entered.connect(_bounce_player); add_child(area)

func _bounce_player(body):
	if not body is CharacterBody2D or not body.has_method("get_jump_force_radius"): return
	if body.global_position.y > global_position.y: return
	body.velocity.y = -bounce_force
	body.jumps_remaining = body.max_jumps
	play_bounce()
	play_interact()

func play_bounce():
	if bounce_tween: bounce_tween.kill()
	bounce_tween = create_tween().set_parallel(true)
	bounce_tween.tween_property(self, "scale", Vector2(1.2, 0.7), 0.1)
	bounce_tween.tween_property(self, "scale", Vector2.ONE, 0.3).set_delay(0.1).set_trans(Tween.TRANS_ELASTIC)
	
	# Add a quick color flash
	var body = get_block_body()
	var surface = body.get_node_or_null("ColorRect")
	if surface:
		bounce_tween.tween_property(surface, "color", Color.WHITE, 0.1)
		bounce_tween.tween_property(surface, "color", block_color, 0.2).set_delay(0.1)
