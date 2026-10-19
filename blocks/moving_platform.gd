class_name MovingPlatform
extends Block

## Slides back and forth inside the lane the map generator gave it.

var travel := 120.0      ## half of the horizontal range
var speed := 1.0         ## radians / second of the sine motion
var _origin := Vector2.ZERO
var _phase := 0.0


func _init() -> void:
	super._init()
	block_id = "moving_platform"


func _ready() -> void:
	super._ready()
	_origin = position
	_phase = posmod(_seed, 6283) / 1000.0


func _physics_process(_delta: float) -> void:
	position.x = _origin.x + sin(_phase + Block.clock * speed) * travel


func _draw_icon() -> void:
	var col := _icon_color()
	var hx := minf(size.x * 0.5 - 20.0, 50.0)
	_ink_line(PackedVector2Array([Vector2(-hx, 0), Vector2(hx, 0)]), col, 4.0)
	_ink_line(PackedVector2Array([Vector2(-hx + 10, -10), Vector2(-hx, 0), Vector2(-hx + 10, 10)]), col, 4.0)
	_ink_line(PackedVector2Array([Vector2(hx - 10, -10), Vector2(hx, 0), Vector2(hx - 10, 10)]), col, 4.0)
