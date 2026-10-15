class_name Fragment
extends RigidBody2D

## Floating debris from a broken block. Zero gravity, heavily damped:
## it drifts to a stop and becomes a temporary stepping stone.

const LIFETIME := 22.0

var _poly: PackedVector2Array
var _body := Color.WHITE
var _hi := Color.WHITE
var _age := 0.0

# Gravity-field ownership (resolved per physics frame between players).
var claim_frame := -1
var claim_dist := INF
var stun := 0.0


func setup(poly: PackedVector2Array, body: Color, hi: Color) -> void:
	_poly = poly
	_body = body
	_hi = hi
	gravity_scale = 0.0
	mass = 8.0
	linear_damp = 2.5
	angular_damp = 4.0
	collision_layer = 1
	collision_mask = 1
	var cp := CollisionPolygon2D.new()
	cp.polygon = poly
	add_child(cp)
	add_to_group("fragments")


func _physics_process(delta: float) -> void:
	_age += delta
	stun = maxf(stun - delta, 0.0)
	if _age > LIFETIME:
		modulate.a = 1.0 - (_age - LIFETIME)
		if _age > LIFETIME + 1.0:
			queue_free()


func _draw() -> void:
	var shadow := _poly.duplicate()
	for i in shadow.size():
		shadow[i] += Vector2(0, 5)
	draw_colored_polygon(shadow, Color(0, 0, 0, 0.25))
	draw_colored_polygon(_poly, _body)
	var outline := _poly.duplicate()
	outline.append(_poly[0])
	draw_polyline(outline, _hi.darkened(0.1), 2.0, true)
