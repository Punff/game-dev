class_name MovingPlatform
extends Block

## Slides back and forth inside the lane the map generator gave it.

var travel := 120.0      ## half of the horizontal range
var speed := 1.0         ## radians / second of the sine motion
var _origin := Vector2.ZERO
var _t := 0.0


func _init() -> void:
	super._init()
	block_id = "moving_platform"


func _ready() -> void:
	super._ready()
	_origin = position
	_t = randf() * TAU


func _physics_process(delta: float) -> void:
	_t += delta * speed
	position.x = _origin.x + sin(_t) * travel


func _draw_icon() -> void:
	var col := _icon_color(0.8)
	var hx := minf(size.x * 0.5 - 14.0, 40.0)
	draw_line(Vector2(-hx, -3), Vector2(hx, -3), Color(col, 0.4), 3.0)
	draw_polyline(PackedVector2Array([Vector2(-hx + 7, -10), Vector2(-hx, -3), Vector2(-hx + 7, 4)]), col, 3.0, true)
	draw_polyline(PackedVector2Array([Vector2(hx - 7, -10), Vector2(hx, -3), Vector2(hx - 7, 4)]), col, 3.0, true)
