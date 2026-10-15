extends BaseBlock
class_name MovingBlock

@export var move_distance: float = 500.0
@export var move_speed: float = 150.0
@export var move_direction: Vector2 = Vector2(1, 0)
@export var pause_at_ends: float = 0.5

var start: Vector2; var end: Vector2; var moving_to_end: bool = true
var paused: bool = false
var _tween: Tween

func get_block_group() -> String: return "moving_blocks"
func get_default_color() -> Color: return Color(0.65, 0.2, 0.8)

func _ready():
	add_to_group(get_block_group()); start = global_position; end = start + (move_direction.normalized() * move_distance)
	_build_block(); start_movement()

func _build_block():
	var _hw = hw(); var _hh = hh()
	var body = CharacterBody2D.new(); body.name = "Platform"
	add_collision(body, block_size)
	add_rect(body, block_size, Vector2(-_hw, -_hh + 8), block_color.darkened(0.5))
	add_rect(body, block_size, Vector2(-_hw, -_hh), block_color)
	var hl_h = max(4.0, block_size.y * 0.12)
	add_rect(body, Vector2(block_size.x, hl_h), Vector2(-_hw, -_hh), block_color.lightened(0.25))

	var asz = min(_hw, _hh) * 0.2
	var a_left = Line2D.new(); a_left.width = 2.0; a_left.default_color = Color(1,1,1,0.6); a_left.antialiased = true
	a_left.points = [Vector2(-_hw*0.2, 0), Vector2(-_hw*0.2 - asz, -_hh*0.2), Vector2(-_hw*0.2, 0), Vector2(-_hw*0.2 - asz, _hh*0.2)]
	body.add_child(a_left)

	var a_right = Line2D.new(); a_right.width = 2.0; a_right.default_color = Color(1,1,1,0.6); a_right.antialiased = true
	a_right.points = [Vector2(_hw*0.2, 0), Vector2(_hw*0.2 + asz, -_hh*0.2), Vector2(_hw*0.2, 0), Vector2(_hw*0.2 + asz, _hh*0.2)]
	body.add_child(a_right)

	var border = Line2D.new(); border.width = 3.0; border.default_color = Color(0.08, 0.08, 0.1); border.antialiased = true
	border.points = [Vector2(-_hw, -_hh), Vector2(_hw, -_hh), Vector2(_hw, _hh), Vector2(-_hw, _hh), Vector2(-_hw, -_hh)]
	body.add_child(border); add_child(body)

func start_movement(): move_to_target()

func stop_movement():
	paused = true
	if _tween:
		_tween.kill()
		_tween = null

func move_to_target():
	if paused: return
	var t = end if moving_to_end else start; var dur = global_position.distance_to(t) / move_speed
	_tween = create_tween()
	_tween.tween_property(self, "global_position", t, dur)
	await _tween.finished
	_tween = null
	if pause_at_ends > 0: paused = true; await get_tree().create_timer(pause_at_ends).timeout; paused = false
	moving_to_end = !moving_to_end; move_to_target()

func get_platform_velocity() -> Vector2: return (end - start).normalized() * move_speed * (1 if moving_to_end else -1)

func is_moving() -> bool: return not paused

func on_shockwave(_dir: Vector2, _origin: Vector2, _range: float):
	stop_movement()

func reverse_direction():
	moving_to_end = !moving_to_end
	if _tween:
		_tween.kill()
		_tween = null
	move_to_target()

func _draw():
	if Engine.is_editor_hint():
		draw_line(to_local(start), to_local(end), Color.YELLOW, 2.0); draw_circle(to_local(start), 5, Color.GREEN); draw_circle(to_local(end), 5, Color.RED)
