class_name Fragment
extends RigidBody2D

## A chunk of broken concrete. Zero gravity and damped: it drifts to a stop
## and hangs in the air as a stepping stone. Fast-moving chunks are
## projectiles - they knock players around and smash other breakable blocks.

const LIFETIME := 30.0
const IMPACT_SPEED := 420.0

var _poly: PackedVector2Array
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

# Online: the server numbers every chunk; clients get frozen puppets that
# glide to the positions it sends.
var net_id := 0
var net_announced := false
var net_sent := Vector3.INF      ## x, y, rotation last put in a snapshot
var puppet := false
var _net_from := Vector3.ZERO
var _net_to := Vector3.ZERO
var _net_t := 1.0
var _net_vel := Vector2.ZERO


func setup(poly: PackedVector2Array, body: Color, hi: Color) -> void:
	_poly = poly
	_body = body
	_hi = hi
	gravity_scale = 0.0
	mass = 10.0
	linear_damp = 1.6
	angular_damp = 3.0
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


## Client side: no physics of its own, just a picture of the server's chunk.
func make_puppet(id: int) -> void:
	net_id = id
	puppet = true
	freeze_mode = RigidBody2D.FREEZE_MODE_KINEMATIC
	freeze = true
	collision_layer = 0
	collision_mask = 0
	contact_monitor = false


func set_net_target(pos: Vector2, rot: float, vel: Vector2) -> void:
	if _net_t >= 1.0 and _net_to == Vector3.ZERO:
		global_position = pos   # first sighting: appear in place
		rotation = rot
	_net_from = Vector3(global_position.x, global_position.y, rotation)
	_net_to = Vector3(pos.x, pos.y, rot)
	_net_t = 0.0
	_net_vel = vel


func _ready() -> void:
	if Net.is_server():
		net_id = Net.next_id()
		tree_exiting.connect(func(): if Net.game: Net.game.fragment_gone(net_id))


func _velocity() -> Vector2:
	return _net_vel if puppet else linear_velocity


func throw(by: Player, velocity: Vector2) -> void:
	thrown_by = by
	_thrown_time = 0.35
	linear_velocity = velocity
	angular_velocity = randf_range(-8, 8)


func _physics_process(delta: float) -> void:
	_age += delta
	if puppet:
		_net_t = minf(_net_t + delta / Net.snapshot_interval(), 1.0)
		global_position = Vector2(lerpf(_net_from.x, _net_to.x, _net_t), lerpf(_net_from.y, _net_to.y, _net_t))
		rotation = lerp_angle(_net_from.z, _net_to.z, _net_t)
	stun = maxf(stun - delta, 0.0)
	_thrown_time = maxf(_thrown_time - delta, 0.0)
	if _age > LIFETIME:
		modulate.a = 1.0 - (_age - LIFETIME)
		if _age > LIFETIME + 1.0:
			queue_free()
	var fast := _velocity().length_squared() > IMPACT_SPEED * IMPACT_SPEED
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
		body.hit_by_chunk(linear_velocity * 0.55, self)
		linear_velocity *= 0.35


func _draw() -> void:
	var fast := _velocity().length() > IMPACT_SPEED
	if fast:
		# comic speed streaks behind a flying chunk
		var back := -_velocity().normalized().rotated(-rotation) * 26.0
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
