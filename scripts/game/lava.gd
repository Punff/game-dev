class_name Lava
extends Node2D

## Rising lava. Rubber-banded: it eases off when someone is about to be
## caught and speeds up when everyone is far ahead.

const SHADER := preload("res://shaders/lava.gdshader")
const BASE_SPEED := 36.0
const MAX_SPEED := 180.0
const RAMP := 0.9              ## base speed gained per 10 s of match time
## px between the lowest player and the surface. Closer than NEAR it eases
## off; from CHASE_FROM it speeds up, reaching MAX_SPEED at CHASE_FULL. Tuned
## on a recorded solo climb (~2.7 m/s): it settles ~15 m below a steady
## climber, a few rows down, instead of ~35 m (off screen).
const NEAR := 260.0
const CHASE_FROM := 300.0
const CHASE_FULL := 900.0
const GLOW := 60.0

var surface_y := 0.0
var speed := BASE_SPEED
var active := false
## Extra px/s while a surge (MapEvents) is on. Only applies while nobody is
## already close to being caught, so a surge squeezes, it doesn't snipe.
var surge := 0.0
var _time := 0.0
var _rect := ColorRect.new()
var _mat := ShaderMaterial.new()
var _embers := Node2D.new()
const EMBERS := 18
const EMBER_LIFE := 2.2


func _ready() -> void:
	z_index = 30
	_mat.shader = SHADER
	_rect.material = _mat
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rect)
	_embers.draw.connect(_draw_embers)
	add_child(_embers)


func update_lava(delta: float, lowest_player_y: float, cam: Camera2D) -> void:
	if active:
		_time += delta
		var base := BASE_SPEED + RAMP * _time / 10.0
		var gap := surface_y - lowest_player_y
		var target := base
		if gap < NEAR:
			target = base * 0.45
		elif gap > CHASE_FROM:
			target = lerpf(base, MAX_SPEED, clampf((gap - CHASE_FROM) / (CHASE_FULL - CHASE_FROM), 0.0, 1.0))
		if surge > 0.0 and gap >= NEAR:
			target += surge
		speed = move_toward(speed, minf(target, MAX_SPEED), 60.0 * delta)
		surface_y -= speed * delta
	# Fit the rect to the visible area.
	var vp := get_viewport_rect().size / cam.zoom
	var center := cam.get_screen_center_position()
	var size := Vector2(vp.x + 200.0, maxf(vp.y, 400.0) + 400.0)
	_rect.position = Vector2(center.x - size.x * 0.5, surface_y - GLOW)
	_rect.size = size
	_mat.set_shader_parameter("rect_size", size)
	_mat.set_shader_parameter("surface", GLOW)
	_mat.set_shader_parameter("world_x", _rect.position.x)
	_ember_left = _rect.position.x
	_ember_width = size.x
	_embers.queue_redraw()


var _ember_left := 0.0
var _ember_width := 0.0


## Sparks drifting up off the surface. Each one is a pure function of the
## clock and its index, so there's nothing to simulate or sync.
func _draw_embers() -> void:
	var now := Time.get_ticks_msec() * 0.001
	var n := EMBERS / 2 if Fx.reduced else EMBERS
	for i in n:
		var cycle := now / EMBER_LIFE + i * 0.618
		var gen := floorf(cycle)
		var f := cycle - gen   # 0..1 through this ember's life
		var h := fposmod(sin((gen + i * 13.0) * 12.9898) * 43758.5453, 1.0)
		var x := _ember_left + h * _ember_width + sin(now * 1.7 + i) * 14.0 * f
		var y := surface_y - 10.0 - f * (90.0 + 120.0 * h)
		var a := (1.0 - f) * minf(f * 6.0, 1.0)
		var r := 3.2 * (1.0 - f * 0.6)
		_embers.draw_rect(Rect2(x - r - 1.0, y - r - 1.0, r * 2.0 + 2.0, r * 2.0 + 2.0), Color(Palette.INK, a * 0.7))
		_embers.draw_rect(Rect2(x - r, y - r, r * 2.0, r * 2.0), Color(Palette.MUSTARD if i % 3 else Palette.PAPER, a))
