class_name MovingPlatform extends Block

@export var move_distance: float = 300.0
@export var move_speed: float = 150.0
@export var move_direction: Vector2 = Vector2(1, 0)
@export var pause_at_ends: float = 0.5

var _start: Vector2
var _end: Vector2
var _moving_to_end: bool = true
var _tween: Tween

func _ready() -> void:
	super._ready()
	block_id = "moving_platform"
	block_category = "static"
	spawn_weight = 1.0
	
	# Randomize properties for variety
	move_speed *= randf_range(0.8, 1.2)
	pause_at_ends *= randf_range(0.7, 1.3)
	
	_start = global_position
	_end = _start + (move_direction.normalized() * move_distance)
	
	# Start at a random point along the path to de-sync
	var start_progress = randf()
	global_position = _start.lerp(_end, start_progress)
	_moving_to_end = randf() > 0.5
	
	_move_cycle()

func _move_cycle():
	var target = _end if _moving_to_end else _start
	var dur = global_position.distance_to(target) / move_speed
	
	if _tween: _tween.kill()
	_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_property(self, "global_position", target, dur)
	
	_tween.finished.connect(func():
		if pause_at_ends > 0:
			await get_tree().create_timer(pause_at_ends).timeout
		_moving_to_end = !_moving_to_end
		_move_cycle()
	, CONNECT_ONE_SHOT)
