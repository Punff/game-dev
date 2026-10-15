class_name GameCamera
extends Camera2D

## Keeps every living player in frame. Zooms out as players spread apart,
## and when they're too far apart it favours the leader (the lava will
## sort out stragglers). Also handles screen shake.

const MARGIN_TOP := 280.0
const MARGIN_BOTTOM := 170.0
const MIN_ZOOM := 0.5

var targets: Array = []
var lava_y := INF
var _shake := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	SignalBus.screen_shake_requested.connect(shake)
	position_smoothing_enabled = false
	ignore_rotation = true


func shake(strength: float) -> void:
	_shake = maxf(_shake, strength * float(Settings.get_value("screen_shake")))


func snap() -> void:
	_update(1.0, true)


func _physics_process(delta: float) -> void:
	_update(delta, false)


func _update(delta: float, instant: bool) -> void:
	var vp := get_viewport_rect().size
	var width_zoom := vp.x / (MapPlanner.HALF_WIDTH * 2.0 + 160.0)
	var alive := targets.filter(func(t): return is_instance_valid(t) and not t.is_dead)
	if alive.is_empty():
		return
	var top := INF
	var bottom := -INF
	for t in alive:
		top = minf(top, t.global_position.y)
		bottom = maxf(bottom, t.global_position.y)
	top -= MARGIN_TOP
	bottom = minf(bottom + MARGIN_BOTTOM, lava_y + 140.0)
	bottom = maxf(bottom, top + 200.0)
	var need_h := bottom - top
	var z := clampf(minf(width_zoom, vp.y / need_h), MIN_ZOOM, maxf(width_zoom, MIN_ZOOM))
	var visible_h := vp.y / z
	var cy := (top + bottom) * 0.5
	if need_h > visible_h:
		cy = top + visible_h * 0.5   # favour the leader
	var target := Vector2(0.0, cy)
	var k := 1.0 if instant else minf(4.0 * delta, 1.0)
	zoom = zoom.lerp(Vector2(z, z), minf(2.5 * delta, 1.0) if not instant else 1.0)
	global_position = global_position.lerp(target, k)

	_shake = move_toward(_shake, 0.0, 40.0 * delta)
	offset = Vector2(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * _shake if _shake > 0.1 else Vector2.ZERO
