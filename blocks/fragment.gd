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
## Who to credit for what this chunk hits (Telemetry): its last thrower, or
## whoever broke the block it came from.
var credit: Player = null
var _thrown_time := 0.0
var stun := 0.0
## Falling things (a slab): once slower than this, it damps like any chunk and
## floats where it ended up. 0: off.
var settle_speed := 0.0
var _was_fast := false
## A slab (MapEvents): one big piece of concrete. It shatters on a player it
## hits (a knock, not a long fall), and once it floats it breaks like any
## concrete: jump off it or pound it.
var concrete := false
const SLAB_KNOCK := 0.3           ## of its speed passed on to whoever it hits
var _shatter_in := -1             # physics ticks until it shatters (-1: not due)
var _shatter_args := []
var _step_velocity := Vector2.ZERO  # before this physics step (a heavy slab stops dead on a ball)

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


## Client side: no physics of its own, just a picture of the server's chunk.
var _phasing_for_us := false


func make_puppet(id: int) -> void:
	net_id = id
	puppet = true
	freeze_mode = RigidBody2D.FREEZE_MODE_KINEMATIC
	freeze = true
	collision_layer = 1   # solid, so our own (predicted) ball can stand on it
	collision_mask = 0
	contact_monitor = false


## Guest: let our predicted ball pass through while the host says this chunk
## is being pulled through it by a gravity field.
func phase_through(p: Player, on: bool) -> void:
	if on == _phasing_for_us:
		return
	_phasing_for_us = on
	if on:
		add_collision_exception_with(p)
	else:
		remove_collision_exception_with(p)


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
	credit = by
	_thrown_time = 0.35
	linear_velocity = velocity
	# Spin from where it is, not the global random: replays come out the same.
	var r := RandomNumberGenerator.new()
	r.seed = hash(Vector2i(global_position)) + int(velocity.x)
	angular_velocity = r.randf_range(-8, 8)


## Let go of by a gravity field without a throw: the same short grace a
## throw gets, so it doesn't knock the player who was just holding it.
func release(by: Player) -> void:
	held_by = null
	thrown_by = by
	_thrown_time = 0.35


func _physics_process(delta: float) -> void:
	_age += delta
	if puppet:
		_net_t = minf(_net_t + delta / Net.snapshot_interval(), 1.0)
		global_position = Vector2(lerpf(_net_from.x, _net_to.x, _net_t), lerpf(_net_from.y, _net_to.y, _net_t))
		rotation = lerp_angle(_net_from.z, _net_to.z, _net_t)
	stun = maxf(stun - delta, 0.0)
	if settle_speed > 0.0 and linear_velocity.length() < settle_speed and _age > 0.2:
		settle_speed = 0.0
		linear_damp = 1.1
	_thrown_time = maxf(_thrown_time - delta, 0.0)
	_step_velocity = linear_velocity
	if _shatter_in > 0:
		_shatter_in -= 1
	elif _shatter_in == 0:
		_shatter_in = -1
		_shatter()
		return
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
	if concrete and body is Player and _step_velocity.length() >= IMPACT_SPEED:
		if body != held_by and not (body == thrown_by and _thrown_time > 0.0):
			body.hit_by_chunk(_step_velocity * SLAB_KNOCK, self)
			schedule_shatter(0, body.global_position, 240.0, body)
		return
	if speed < IMPACT_SPEED:
		return
	if body is BreakableBlock:
		# On the block's next physics tick: this runs inside the physics step,
		# which won't let the new chunks switch on their contact reports (they'd
		# break nothing more, cutting chain reactions short).
		body.schedule_break(0, global_position, speed * 0.6, "chunk", credit)
	elif body is Player:
		# Never the player whose gravity field is carrying it, nor right after
		# they let go (live data: most chunk hits were players' own fields
		# pulling debris into them).
		if body == held_by or body == thrown_by and _thrown_time > 0.0:
			return
		var weight := clampf(mass / MASS, 0.5, 2.0)
		body.hit_by_chunk(linear_velocity * 0.55 * weight, self)
		linear_velocity *= lerpf(0.2, 0.65, (weight - 0.5) / 1.5)   # heavy ones plough on


# ── Concrete (a slab) ───────────────────────
# A player standing on it calls these like a Block's.

var block_id := "slab"


func get_rect_global() -> Rect2:
	return get_global_transform() * extent

func on_player_land(player: Player) -> void:
	if concrete and player.last_impact >= BreakableBlock.POUND_SPEED and not Net.is_client():
		schedule_shatter(0, player.global_position, 380.0, player)


func on_player_stand(_player: Player, _delta: float) -> void:
	pass


func on_player_leave(_player: Player) -> void:
	pass


func on_player_jump(player: Player, _strength: float) -> void:
	if concrete and not Net.is_client():
		schedule_shatter(roundi(BreakableBlock.BREAK_DELAY * Engine.physics_ticks_per_second), player.global_position, 220.0, player)


## Shatters `ticks` physics steps from now, in its own physics step (the same
## reasons as BreakableBlock.schedule_break). The shards spare `spare` for a
## moment, so the one it broke on isn't hit again by its own pieces.
func schedule_shatter(ticks: int, origin: Vector2, force: float, spare: Player) -> void:
	if not concrete or (_shatter_in >= 0 and _shatter_in <= ticks):
		return
	_shatter_in = ticks
	_shatter_args = [origin, force, spare]


func _shatter() -> void:
	var origin: Vector2 = _shatter_args[0]
	var force: float = _shatter_args[1]
	var spare: Player = _shatter_args[2] if is_instance_valid(_shatter_args[2]) else null
	Telemetry.broke(self, "slab", spare)
	SignalBus.block_broken.emit(global_position)
	Sfx.play("break", -1.0)
	Fx.burst(global_position, Palette.PAPER_DIM, 10, 260.0, 0.5)
	# Seeded by where it is, not at random: replays come out the same.
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector2i(global_position)) + 7919
	var parent := get_parent()
	for poly in BreakableBlock.shatter(extent, maxi(3, roundi(extent.get_area() / BreakableBlock.CHUNK_AREA)), rng):
		var center := Vector2.ZERO
		for v in poly:
			center += v
		center /= poly.size()
		var local := poly.duplicate()
		for i in local.size():
			local[i] -= center
		var f := Fragment.new()
		f.setup(local, _body, _hi)
		f.credit = credit
		if spare:
			f.thrown_by = spare
			f._thrown_time = 0.35
		parent.add_child(f)
		f.global_position = to_global(center)
		f.rotation = rotation
		var away := (f.global_position - origin).normalized()
		f.linear_velocity = linear_velocity * 0.3 + away * force * rng.randf_range(0.5, 1.0)
		f.angular_velocity = rng.randf_range(-4, 4)
	queue_free()


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
	else:
		draw_line(_poly[0].lerp(_poly[1], 0.5), _poly[2].lerp(_poly[0], 0.4), Color(Palette.INK, 0.5), 2.0)
