class_name Lava
extends Node2D

## Rising lava. Rubber-banded: it eases off when someone is about to be
## caught and speeds up when everyone is far ahead.

const SHADER := preload("res://shaders/lava.gdshader")
const BASE_SPEED := 42.0
const MAX_SPEED := 170.0
const RAMP := 0.9              ## base speed gained per 10 s of match time
const GLOW := 60.0

var surface_y := 0.0
var speed := BASE_SPEED
var active := false
var _time := 0.0
var _rect := ColorRect.new()
var _mat := ShaderMaterial.new()


func _ready() -> void:
	z_index = 30
	_mat.shader = SHADER
	_rect.material = _mat
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rect)


func update_lava(delta: float, lowest_player_y: float, cam: Camera2D) -> void:
	if active:
		_time += delta
		var base := BASE_SPEED + RAMP * _time / 10.0
		var gap := surface_y - lowest_player_y
		var target := base
		if gap < 260.0:
			target = base * 0.45
		elif gap > 900.0:
			target = lerpf(base, MAX_SPEED, clampf((gap - 900.0) / 900.0, 0.0, 1.0))
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
