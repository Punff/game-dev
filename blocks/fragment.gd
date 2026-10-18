class_name Fragment
extends RigidBody2D

## A chunk of broken concrete. Zero gravity and damped: it drifts to a stop
## and hangs in the air as a stepping stone. Fast-moving chunks are
## projectiles - they knock players around and smash other breakable blocks.

const LIFETIME := 30.0
const IMPACT_SPEED := 420.0
const REF_AREA := 3600.0         ## a shard this big weighs MASS
const MASS := 10.0

var _poly: PackedVector2Array
## Local bounding box as cut (rotation 0): lets a gravity field line chunks up.
var extent := Rect2()
var _body := Color.WHITE
var _hi := Color.WHITE
var _age := 0.0

# Gravity-field ownership (resolved per physics frame between players).
var claim_frame := -1
var claim_dist := INF
var held_by: Player = null
var thrown_by: Player = null
var _thrown_time := 0.0
var stun := 0.0
var _was_fast := false


func setup(poly: PackedVector2Array, body: Color, hi: Color) -> void:
	_poly = poly
	extent = Rect2(poly[0], Vector2.ZERO)
	for v in poly:
		extent = extent.expand(v)
	_body = body
	_hi = hi
	gravity_scale = 0.0
	# Heavier the bigger it is: big slabs carry momentum and hit hard,
	# slivers flutter.
	mass = clampf(MASS * BreakableBlock._area(poly) / REF_AREA, 3.0, 30.0)
	linear_damp = 1.1
	angular_damp = 2.0
	collision_layer = 1
	collision_mask = 1
	contact_monitor = true
	max_contacts_reported = 3
	continuous_cd = RigidBody2D.CCD_MODE_CAST_RAY
	var cp := CollisionPolygon2D.new()
	cp.polygon = poly
	add_child(cp)
	add_to_group("fragments")
	body_entered.connect(_on_body_entered)


func throw(by: Player, velocity: Vector2) -> void:
	thrown_by = by
	_thrown_time = 0.35
	linear_velocity = velocity
	angular_velocity = randf_range(-8, 8)


func _physics_process(delta: float) -> void:
	_age += delta
	stun = maxf(stun - delta, 0.0)
	_thrown_time = maxf(_thrown_time - delta, 0.0)
	if _age > LIFETIME:
		modulate.a = 1.0 - (_age - LIFETIME)
		if _age > LIFETIME + 1.0:
			queue_free()
	var fast := linear_velocity.length_squared() > IMPACT_SPEED * IMPACT_SPEED
	if fast or _was_fast:
		queue_redraw()
	_was_fast = fast


func _on_body_entered(body: Node) -> void:
	var speed := linear_velocity.length()
	if speed < IMPACT_SPEED:
		return
	if body is BreakableBlock:
		body.break_apart(global_position, speed * 0.6)
	elif body is Player:
		if body == thrown_by and _thrown_time > 0.0:
			return
		var weight := clampf(mass / MASS, 0.5, 2.0)
		body.hit_by_chunk(linear_velocity * 0.55 * weight, self)
		linear_velocity *= lerpf(0.2, 0.65, (weight - 0.5) / 1.5)   # heavy ones plough on


func _draw() -> void:
	var fast := linear_velocity.length() > IMPACT_SPEED
	if fast:
		# comic speed streaks behind a flying chunk
		var back := -linear_velocity.normalized().rotated(-rotation) * 26.0
		for k in 3:
			var o := Vector2(0, (k - 1) * 8.0).rotated(back.angle())
			draw_line(o + back * 0.4, o + back * 1.4, Color(Palette.PAPER, 0.5), 2.0)
	var shadow := _poly.duplicate()
	for i in shadow.size():
		shadow[i] += Vector2(6, 6).rotated(-rotation)
	draw_colored_polygon(shadow, Color(Palette.INK, 0.5))
	var outline := _poly.duplicate()
	outline.append(_poly[0])
	draw_colored_polygon(Block._shifted(_poly, Block.MISREG), _body.lightened(0.12) if fast else _body)
	draw_polyline(outline, Palette.INK, 2.5)
	# a crack across the chunk
	if _poly.size() >= 4:
		draw_line(_poly[0].lerp(_poly[2], 0.3), _poly[1].lerp(_poly[3], 0.6), Color(Palette.INK, 0.5), 2.0)
	else:
		draw_line(_poly[0].lerp(_poly[1], 0.5), _poly[2].lerp(_poly[0], 0.4), Color(Palette.INK, 0.5), 2.0)
