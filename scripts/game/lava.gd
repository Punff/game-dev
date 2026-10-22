class_name Lava
extends Node2D

## Rising lava. It gets faster the higher it has climbed, so every run ends:
## the faster you climb, the higher you are when its pace passes yours.
##
## Around you it's rubber-banded, but a lead is yours to keep: while you're
## ahead it only creeps at LEAD_CHASE x its pace, so climbing faster banks a
## buffer (for detours, mistakes). Past LEAD_MAX it races to catch up, so the
## lead has a ceiling. Just behind you it eases off (NEAR, EASE), less so the
## higher it gets.
##
## Modelled for a steady climber: 1.5 m/s is caught around 290 m, 2.6 m/s
## (a good run) around 540 m, 3.2 m/s around 650 m - all after about three
## and a half minutes, so climbing faster is what gets you higher. The lead
## is kept short (14 m) so a real mistake (a 10 m fall) brings it right up
## behind you. (Before: 25 m, and a good climber sat at the cap for minutes
## with the lava just following; live runs never came near it.)

const SHADER := preload("res://shaders/lava.gdshader")
const BASE_SPEED := 55.0
const RISE_PER_M := 0.22       ## px/s of pace per metre the lava has climbed
const RAMP := 1.5              ## and per 10 s of match time
const MAX_SPEED := 180.0       ## catch-up speed (plus RISE_PER_M x height)
const LEAD_CHASE := 1.25       ## x pace while you're ahead
const CHASE_FROM := 300.0      ## px ahead before it counts as a lead
const LEAD_MAX := 700.0        ## px (14 m): beyond this it races to catch up...
const LEAD_RACE := 400.0       ## ...reaching full catch-up speed this much further
const NEAR := 260.0            ## px: closer than this it eases off...
const NEAR_HIGH := 140.0       ## ...a smaller zone up high
const EASE := 0.45             ## x pace while easing off...
const EASE_HIGH := 0.8         ## ...barely at all up high
const HIGH_M := 700.0          ## "up high": where NEAR and EASE reach their high values
const GLOW := 60.0

var surface_y := 0.0
var speed := BASE_SPEED
var active := false
## Extra px/s while a surge (MapEvents) is on. Only applies while nobody is
## already close to being caught, so a surge squeezes, it doesn't snipe.
var surge := 0.0
var _glow := 0.0   # 0..1, eases with the surge
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


## How far up the lava has climbed (m above the start floor).
func height_m() -> float:
	return maxf(0.0, -surface_y / 50.0)


func update_lava(delta: float, lowest_player_y: float, cam: Camera2D) -> void:
	if active:
		_time += delta
		var h := height_m()
		var high := clampf(h / HIGH_M, 0.0, 1.0)
		var base := BASE_SPEED + RISE_PER_M * h + RAMP * _time / 10.0
		var max_speed := MAX_SPEED + RISE_PER_M * h
		var gap := surface_y - lowest_player_y
		var near := lerpf(NEAR, NEAR_HIGH, high)
		var target := base
		if gap < near:
			target = base * lerpf(EASE, EASE_HIGH, high)
		elif gap > LEAD_MAX:
			target = lerpf(base * LEAD_CHASE, max_speed, clampf((gap - LEAD_MAX) / LEAD_RACE, 0.0, 1.0))
		elif gap > CHASE_FROM:
			target = base * LEAD_CHASE
		target = minf(target, max_speed)
		# A surge rides on top of all that (it used to be clamped away when
		# the lava was already catching up, so some surges did nothing).
		if surge > 0.0 and gap >= near:
			target += surge
		speed = move_toward(speed, target, 60.0 * delta)
		surface_y -= speed * delta
	# A surge shows: the slag flares hotter while it's on.
	_glow = move_toward(_glow, 1.0 if surge > 0.0 else 0.0, delta * 2.5)
	_rect.modulate = Color(1, 1, 1).lerp(Color(1.45, 1.2, 0.85), _glow)
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
