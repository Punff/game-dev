class_name GameCamera
extends Camera2D

## Keeps every living player in frame. Zooms out as players spread apart,
## and when they're too far apart it favours the leader (the lava will
## sort out stragglers). Also handles screen shake.

const MARGIN_TOP := 300.0
const MARGIN_BOTTOM := 170.0
const MARGIN_SIDE := 220.0
const MIN_ZOOM := 0.5
const MAX_ZOOM := 1.0

var targets: Array = []
var lava_y := INF
## How far the view may go either side of the centre (INF: no limit).
var wall_half_width := MapPlanner.HALF_WIDTH + 400.0
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
	var alive := targets.filter(func(t): return is_instance_valid(t) and not t.is_dead)
	if alive.is_empty():
		return
	var box := Rect2(alive[0].global_position, Vector2.ZERO)
	for t in alive:
		box = box.expand(t.global_position)
	var top := box.position.y - MARGIN_TOP
	var bottom := minf(box.end.y + MARGIN_BOTTOM, lava_y + 160.0)
	bottom = maxf(bottom, top + 300.0)
	var left := box.position.x - MARGIN_SIDE
	var right := box.end.x + MARGIN_SIDE
	var z := clampf(minf(vp.x / (right - left), vp.y / (bottom - top)), MIN_ZOOM, MAX_ZOOM)
	var visible := vp / z
	var cy := (top + bottom) * 0.5
	if bottom - top > visible.y:
		cy = top + visible.y * 0.5   # favour the leader
	var cx := (left + right) * 0.5
	if right - left > visible.x:
		# Too spread: follow whoever is highest horizontally too.
		var lead: Node2D = alive[0]
		for t in alive:
			if t.global_position.y < lead.global_position.y:
				lead = t
		cx = clampf(lead.global_position.x, left + visible.x * 0.5, right - visible.x * 0.5)
	# Don't show much beyond the arena walls.
	var wall := wall_half_width
	if wall == INF:
		pass
	elif visible.x < wall * 2.0:
		cx = clampf(cx, -wall + visible.x * 0.5, wall - visible.x * 0.5)
	else:
		cx = 0.0
	var target := Vector2(cx, cy)
	var k := 1.0 if instant else minf(3.5 * delta, 1.0)
	zoom = zoom.lerp(Vector2(z, z), 1.0 if instant else minf(2.0 * delta, 1.0))
	global_position = global_position.lerp(target, k)

	_shake = move_toward(_shake, 0.0, 40.0 * delta)
	offset = Vector2(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * _shake if _shake > 0.1 else Vector2.ZERO
