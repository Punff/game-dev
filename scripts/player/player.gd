class_name Player
extends CharacterBody2D

## A ball with a double jump, a charged jump, a gravity field and a shockwave.
## Movement constants are public so the map generator and tests can reason
## about what is reachable.

signal died(player_id: int)

# ── Movement ─────────────────────────────────
const RADIUS := 16.0
const SPEED := 390.0
const ACCEL := 2700.0
const AIR_ACCEL := 1900.0
const AIR_BRAKE := 0.45          ## fraction of AIR_ACCEL used to slow down with no input
const FRICTION := 2800.0
const ICE_ACCEL := 550.0
const ICE_FRICTION := 170.0
const GRAVITY := 1400.0
const JUMP_VELOCITY := 780.0
const MAX_JUMPS := 2
const JUMP_CUT := 0.5            ## velocity multiplier when jump is released early
const COYOTE_TIME := 0.1
const JUMP_BUFFER := 0.12
const MAX_FALL := 1300.0
const FAST_FALL_ACCEL := 3800.0
const FAST_FALL_MAX := 2100.0

# ── Charged jump ─────────────────────────────
## Start charging on the ground; keep charging if you run off the edge and
## release whenever - even mid-air - for the launch.
const CHARGE_TIME := 1.0
const CHARGE_VELOCITY := 1220.0  ## at full charge

# ── Abilities ────────────────────────────────
const GRAVITY_COOLDOWN := 3.5
const GRAVITY_DURATION := 2.2
const GRAVITY_RADIUS := 240.0
const THROW_SPEED := 1150.0
const SHOCK_COOLDOWN := 2.5
const SHOCK_RANGE := 500.0
const SHOCK_FORCE := 1800.0
const SHOCK_RECOIL := 430.0
const JUMP_PUSH_RADIUS := 170.0
const JUMP_PUSH_FORCE := 520.0

## Half width of the playable column; set by the game from the map generator.
static var world_half_width := 1100.0

var info: PlayerInfo
var player_id := 1
var color := Color.WHITE
var is_dead := false
var controls_enabled := false

var jumps_left := MAX_JUMPS
var facing := 1.0
var max_height_px := 0.0
var spawn_y := 0.0
var last_impact := 0.0           ## downward speed at the moment of the last landing

# Per-frame surface effects, written by blocks in on_player_stand().
var surface_push := 0.0
var surface_ice := false
var _push_applied := 0.0
var _ice_applied := false

var _coyote := 0.0
var _jump_buffer := 0.0
var _was_on_floor := false
var _reverse_timer := 0.0
var _charging := false
var _charge := 0.0
var gravity_cd := 0.0
var shock_cd := 0.0
var _field_time := 0.0
var _field_active := false
var _held: Array[Fragment] = []
var _floor_blocks: Array = []
var _squash := Vector2.ONE
var _trail: PackedVector2Array = []
var _hit_flash := 0.0
var _a: Dictionary = {}          # action name cache


func _init() -> void:
	collision_layer = 1
	collision_mask = 1
	floor_snap_length = 6.0
	floor_max_angle = deg_to_rad(50)
	var cs := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = RADIUS
	cs.shape = circle
	add_child(cs)


func setup(p: PlayerInfo) -> void:
	info = p
	player_id = p.player_id
	color = p.color
	name = "Player%d" % player_id
	for a in Settings.ACTIONS:
		_a[a] = PlayerManager.action(player_id, a)
	add_to_group("player")


func _ready() -> void:
	spawn_y = global_position.y
	z_index = 10


# ── Input helpers ────────────────────────────

func _pressed(a: String) -> bool:
	return controls_enabled and Input.is_action_pressed(_a[a])

func _just_pressed(a: String) -> bool:
	return controls_enabled and Input.is_action_just_pressed(_a[a])

func _just_released(a: String) -> bool:
	return controls_enabled and Input.is_action_just_released(_a[a])

func _axis(neg: String, pos: String) -> float:
	if not controls_enabled:
		return 0.0
	return Input.get_axis(_a[neg], _a[pos])

func aim_vector() -> Vector2:
	var v := Vector2(_axis("left", "right"), _axis("up", "down"))
	if _reverse_timer > 0.0:
		v.x = -v.x
	return v


# ── Main loop ────────────────────────────────

func _physics_process(delta: float) -> void:
	if is_dead:
		return
	var on_floor := is_on_floor()
	gravity_cd = maxf(gravity_cd - delta, 0.0)
	shock_cd = maxf(shock_cd - delta, 0.0)
	_reverse_timer = maxf(_reverse_timer - delta, 0.0)
	_hit_flash = maxf(_hit_flash - delta, 0.0)

	# Surface effects collected last frame.
	_push_applied = surface_push
	_ice_applied = surface_ice

	if on_floor:
		jumps_left = MAX_JUMPS
		_coyote = COYOTE_TIME
	else:
		_coyote -= delta
		if jumps_left == MAX_JUMPS and _coyote <= 0.0:
			jumps_left = MAX_JUMPS - 1   # walked off a ledge: only the air jump remains

	# Gravity (softened while a gravity field is up and you're falling).
	var g := GRAVITY
	if _field_active and velocity.y > 0.0:
		g *= 0.3
	velocity.y = minf(velocity.y + g * delta, MAX_FALL if not _field_active else 260.0)

	if not on_floor and _pressed("down") and not _field_active:
		velocity.y = minf(velocity.y + FAST_FALL_ACCEL * delta, FAST_FALL_MAX)

	_handle_horizontal(delta, on_floor)
	_handle_jump(delta)
	_handle_charge(delta, on_floor)
	_handle_abilities(delta)

	var fall_speed := velocity.y
	move_and_slide()

	var x_limit := world_half_width - RADIUS
	if absf(global_position.x) > x_limit:
		global_position.x = clampf(global_position.x, -x_limit, x_limit)
		velocity.x = 0.0

	if is_on_floor() and not _was_on_floor:
		last_impact = fall_speed
		_on_landed()
	elif not is_on_floor() and _was_on_floor and velocity.y < 0.0:
		_squash = Vector2(0.75, 1.3)
	_update_floor_blocks(delta)
	_push_players_on_contact()
	_was_on_floor = is_on_floor()

	max_height_px = maxf(max_height_px, spawn_y - global_position.y)
	_update_visuals(delta)


func _handle_horizontal(delta: float, on_floor: bool) -> void:
	var dir := aim_vector().x
	if absf(dir) < 0.2:
		dir = 0.0
	if dir != 0.0:
		facing = signf(dir)
	var target := dir * SPEED + _push_applied
	var rate: float
	if _ice_applied:
		rate = ICE_ACCEL if dir != 0.0 else ICE_FRICTION
	elif dir != 0.0:
		rate = ACCEL if on_floor else AIR_ACCEL
	else:
		rate = FRICTION if on_floor else AIR_ACCEL * AIR_BRAKE
	velocity.x = move_toward(velocity.x, target, rate * delta)


func _handle_jump(delta: float) -> void:
	if _just_pressed("jump"):
		_jump_buffer = JUMP_BUFFER
	else:
		_jump_buffer -= delta

	if _jump_buffer > 0.0 and not _charging and jumps_left > 0:
		var grounded_jump := _coyote > 0.0
		_jump_buffer = 0.0
		_coyote = 0.0
		jumps_left -= 1
		velocity.y = -JUMP_VELOCITY
		_squash = Vector2(0.7, 1.35)
		_on_jumped(1.0, grounded_jump)
		Sfx.play("jump" if grounded_jump else "double_jump", -3.0)
		if not grounded_jump:
			Fx.ring(global_position + Vector2(0, RADIUS), color, 46.0, 4.0, 0.25)

	# Variable jump height.
	if _just_released("jump") and velocity.y < -JUMP_VELOCITY * 0.4:
		velocity.y *= JUMP_CUT


func _handle_charge(delta: float, on_floor: bool) -> void:
	# Starts on the ground (holding while landing counts too)...
	if not _charging and on_floor and _pressed("charge"):
		_charging = true
		_charge = 0.0
	if not _charging:
		return
	# ...then keeps building even if you run off the edge.
	_charge = minf(_charge + delta / CHARGE_TIME, 1.0)
	if not _pressed("charge"):
		var ratio := _charge
		_charging = false
		_coyote = 0.0
		velocity.y = -lerpf(JUMP_VELOCITY, CHARGE_VELOCITY, ratio)
		jumps_left = MAX_JUMPS - 1
		_squash = Vector2(0.6, 1.5)
		_on_jumped(1.0 + ratio, on_floor)
		Sfx.play("charge_jump", -2.0, 0.85 + ratio * 0.3)
		Fx.ring(global_position + Vector2(0, RADIUS), color, 60.0 + ratio * 70.0, 6.0, 0.35)
		Fx.speed_lines(global_position, Vector2.DOWN, color)
		if ratio > 0.9:
			PlayerManager.rumble(player_id, 0.3, 0.2, 0.12)


func _handle_abilities(delta: float) -> void:
	# Gravity field: hold to hover and grab chunks; release while aiming to throw them.
	if _field_active:
		_field_time += delta
		if not _pressed("gravity") or _field_time >= GRAVITY_DURATION:
			_end_field(true)
		else:
			_update_field(delta)
	elif _pressed("gravity") and gravity_cd <= 0.0 and _just_pressed("gravity"):
		_field_active = true
		_field_time = 0.0
		Sfx.play("gravity", -3.0)

	if _just_pressed("shockwave") and shock_cd <= 0.0:
		_fire_shockwave()


func _end_field(allow_throw: bool) -> void:
	_field_active = false
	gravity_cd = GRAVITY_COOLDOWN
	var aim := aim_vector()
	var thrown := 0
	if allow_throw and aim.length_squared() > 0.2:
		for f in _held:
			if is_instance_valid(f):
				f.throw(self, aim.normalized().rotated(randf_range(-0.12, 0.12)) * THROW_SPEED * randf_range(0.85, 1.1) + velocity * 0.3)
				thrown += 1
	for f in _held:
		if is_instance_valid(f):
			f.held_by = null
	_held.clear()
	if thrown > 0:
		Sfx.play("throw", -2.0)
		Fx.speed_lines(global_position, aim.normalized(), color)
		SignalBus.screen_shake_requested.emit(3.0 + thrown)


func _update_field(delta: float) -> void:
	var aim := aim_vector()
	var frame := Engine.get_physics_frames()
	var held: Array[Fragment] = []
	for f: Fragment in get_tree().get_nodes_in_group("fragments"):
		if f.stun > 0.0:
			continue
		var d := global_position.distance_to(f.global_position)
		if d > GRAVITY_RADIUS:
			continue
		if f.claim_frame == frame and f.claim_dist < d:
			continue   # another player's field holds it more tightly
		f.claim_frame = frame
		f.claim_dist = d
		f.held_by = self
		held.append(f)
		# Chunks gather where you aim; with no aim they pack under your feet
		# into a platform you can stand on.
		var idx := held.size() - 1
		var base := Vector2(0, RADIUS + 34)
		if aim.length_squared() > 0.2:
			base = aim.normalized() * 95.0
		var spread := Vector2((idx % 4 - 1.5) * 44.0, -(idx / 4) * 30.0) if aim.length_squared() <= 0.2 \
			else Vector2(cos(idx * 2.4), sin(idx * 2.4)) * (20.0 + idx * 4.0)
		var target := global_position + base + spread
		var to_target := target - f.global_position
		var desired := to_target.normalized() * minf(to_target.length() * 7.0, 900.0) + velocity
		f.linear_velocity = f.linear_velocity.lerp(desired, minf(8.0 * delta, 1.0))
		f.angular_velocity = lerpf(f.angular_velocity, 0.0, minf(10.0 * delta, 1.0))
	_held = held


func _fire_shockwave() -> void:
	shock_cd = SHOCK_COOLDOWN
	var dir := aim_vector()
	dir = Vector2(facing, 0.0) if dir.length_squared() < 0.1 else dir.normalized()
	var origin := global_position
	Fx.cone(origin, dir, color, SHOCK_RANGE)
	Sfx.play("shockwave", 0.0)
	SignalBus.screen_shake_requested.emit(8.0)
	PlayerManager.rumble(player_id, 0.4, 0.3, 0.15)

	# Recoil: firing downwards gives a rocket-jump.
	velocity -= dir * SHOCK_RECOIL
	if dir.y > 0.5:
		velocity.y = minf(velocity.y, -SHOCK_RECOIL * 1.4)

	var targets: Array = get_tree().get_nodes_in_group("player")
	targets.append_array(get_tree().get_nodes_in_group("blocks"))
	targets.append_array(get_tree().get_nodes_in_group("fragments"))
	for node in targets:
		if node == self or not is_instance_valid(node):
			continue
		var to: Vector2 = node.global_position - origin
		if node is Block:
			# Use the closest point on the block so long platforms are hit fairly.
			var r: Rect2 = node.get_rect_global()
			to = Vector2(clampf(origin.x, r.position.x, r.end.x), clampf(origin.y, r.position.y, r.end.y)) - origin
		var dist := to.length()
		if dist > SHOCK_RANGE or dist < 1.0 or to.normalized().dot(dir) < 0.4:
			continue
		var falloff := 1.0 - dist / SHOCK_RANGE
		if node is Player:
			node.hit_by_shockwave(to.normalized() * SHOCK_FORCE * (0.35 + 0.65 * falloff), self)
		elif node is Fragment:
			node.stun = 0.4
			node.throw(self, (to.normalized() * 0.6 + dir * 0.4).normalized() * 1000.0 * (0.5 + falloff))
		elif node is Block:
			node.on_shockwave(to.normalized(), origin)


func hit_by_shockwave(impulse: Vector2, _from: Player) -> void:
	_take_hit(impulse)
	Fx.burst(global_position, color, 8, 260.0, 0.35)


func hit_by_chunk(impulse: Vector2, _chunk: Fragment) -> void:
	_take_hit(impulse)
	Sfx.play("hit", -2.0)
	Fx.burst(global_position, Palette.PAPER_DIM, 6, 200.0, 0.3)


func _take_hit(impulse: Vector2) -> void:
	if is_dead:
		return
	velocity += impulse
	if _field_active:
		_end_field(false)
	_charging = false
	_squash = Vector2(1.35, 0.7)
	_hit_flash = 0.15
	PlayerManager.rumble(player_id, 0.6, 0.6, 0.25)


func _on_jumped(strength: float, from_ground: bool) -> void:
	if from_ground:
		Fx.dust(global_position + Vector2(0, RADIUS), Palette.PAPER_DIM)
		for b in _floor_blocks:
			if is_instance_valid(b):
				b.on_player_jump(self, strength)
	# Jumping next to someone shoves them away.
	for other: Player in get_tree().get_nodes_in_group("player"):
		if other == self or other.is_dead:
			continue
		var to := other.global_position - global_position
		var r := JUMP_PUSH_RADIUS * strength
		if to.length() < r:
			var f := 1.0 - to.length() / r
			other.velocity += to.normalized() * JUMP_PUSH_FORCE * strength * f
	# Debris gets kicked too.
	for f: Fragment in get_tree().get_nodes_in_group("fragments"):
		if f.held_by == self:
			continue
		var to := f.global_position - global_position
		var r := 180.0 * strength
		if to.length() < r:
			f.apply_central_impulse(to.normalized() * 900.0 * (1.0 - to.length() / r) * strength)


func _on_landed() -> void:
	var impact := clampf(last_impact / 1100.0, 0.0, 1.0)
	_squash = Vector2(1.0 + 0.5 * impact + 0.1, 1.0 - 0.45 * impact - 0.05)
	if impact > 0.25:
		Fx.dust(global_position + Vector2(0, RADIUS), Palette.PAPER_DIM, 8)
		Sfx.play("land", -8.0 + impact * 6.0)
	if last_impact > 1000.0:
		SignalBus.screen_shake_requested.emit(5.0)


func _update_floor_blocks(delta: float) -> void:
	surface_push = 0.0
	surface_ice = false
	var now: Array = []
	if is_on_floor():
		for i in get_slide_collision_count():
			var col := get_slide_collision(i)
			if col.get_normal().y > -0.6:
				continue
			var b := col.get_collider()
			if b is Block and not b in now:
				now.append(b)
	for b in now:
		if not b in _floor_blocks:
			b.on_player_land(self)
	for b in now:
		if is_instance_valid(b):
			b.on_player_stand(self, delta)
	for b in _floor_blocks:
		if is_instance_valid(b) and not b in now:
			b.on_player_leave(self)
	_floor_blocks = now


func _push_players_on_contact() -> void:
	for i in get_slide_collision_count():
		var c := get_slide_collision(i).get_collider()
		if c is Player:
			var dir: Vector2 = (c.global_position - global_position)
			dir = Vector2(facing, 0) if dir.length_squared() < 0.01 else dir.normalized()
			c.velocity += dir * 140.0
			velocity -= dir * 70.0


# ── Effects from blocks ──────────────────────

func launch(vy: float) -> void:
	velocity.y = -vy
	jumps_left = MAX_JUMPS - 1
	_coyote = 0.0
	_squash = Vector2(0.6, 1.5)
	PlayerManager.rumble(player_id, 0.2, 0.0, 0.1)


func reverse_controls(duration: float) -> void:
	_reverse_timer = maxf(_reverse_timer, duration)


func is_reversed() -> bool:
	return _reverse_timer > 0.0


func is_charging() -> bool:
	return _charging


func height_meters() -> int:
	return int(max_height_px / 50.0)


func gravity_ready() -> float:
	return 1.0 - gravity_cd / GRAVITY_COOLDOWN


func shock_ready() -> float:
	return 1.0 - shock_cd / SHOCK_COOLDOWN


func die() -> void:
	if is_dead:
		return
	is_dead = true
	if _field_active:
		_end_field(false)
	velocity = Vector2.ZERO
	collision_layer = 0
	collision_mask = 0
	Fx.burst(global_position, color, 22, 480.0, 0.8)
	Fx.ring(global_position, Palette.PAPER, 140.0, 8.0, 0.5)
	Sfx.play("death")
	SignalBus.screen_shake_requested.emit(16.0)
	PlayerManager.rumble(player_id, 1.0, 1.0, 0.45)
	died.emit(player_id)
	SignalBus.player_died.emit(player_id)
	visible = false
	set_physics_process(false)


# ── Visuals ──────────────────────────────────

func _update_visuals(delta: float) -> void:
	_squash = _squash.lerp(Vector2.ONE, minf(14.0 * delta, 1.0))
	if not Fx.reduced and velocity.length_squared() > 520.0 * 520.0:
		_trail.append(global_position)
	elif not _trail.is_empty():
		_trail.remove_at(0)
	if _trail.size() > 6:
		_trail.remove_at(0)
	queue_redraw()


func _draw() -> void:
	# Comic speed lines trailing behind fast movement.
	if _trail.size() >= 2:
		var tail := to_local(_trail[0])
		var dir := (-tail).normalized()
		var side := dir.orthogonal()
		for k in 3:
			var o := side * (k - 1) * 10.0
			draw_line(tail + o, o - dir * (RADIUS + 4.0), Color(Palette.PAPER, 0.55 - absf(k - 1) * 0.2), 3.0 - absf(k - 1))

	# Gravity field: dashed ink ring that tightens over its lifetime.
	if _field_active:
		var life := 1.0 - _field_time / GRAVITY_DURATION
		var rot := Time.get_ticks_msec() * 0.003
		var r := GRAVITY_RADIUS * (0.75 + 0.25 * life)
		draw_circle(Vector2.ZERO, r, Color(color, 0.08))
		for k in 16:
			var a0 := rot + k * TAU / 16.0
			draw_arc(Vector2.ZERO, r, a0, a0 + 0.22, 6, Palette.INK, 7.0)
			draw_arc(Vector2.ZERO, r, a0, a0 + 0.22, 6, color, 3.5)

	# Charge meter: chunky ring segments.
	if _charging:
		var segs := 8
		for k in segs:
			var a0 := -PI * 0.5 + k * TAU / segs
			var on := float(k) / segs < _charge
			draw_arc(Vector2.ZERO, RADIUS + 12, a0 + 0.06, a0 + TAU / segs - 0.06, 6, Palette.INK, 8.0)
			if on:
				draw_arc(Vector2.ZERO, RADIUS + 12, a0 + 0.06, a0 + TAU / segs - 0.06, 6, Palette.PAPER if _charge >= 1.0 else color, 4.5)

	# Body: flat colour, thick ink outline, a visor slash. Squash around the feet.
	var base := Vector2(0, RADIUS)
	draw_set_transform(base - base * _squash, 0.0, _squash)
	draw_circle(Vector2(6, 6), RADIUS + 3.0, Color(Palette.INK, 0.5))
	draw_circle(Vector2.ZERO, RADIUS + 3.5, Palette.INK)
	draw_circle(Vector2.ZERO, RADIUS, Palette.PAPER if _hit_flash > 0.0 else color)
	# shading crescent
	draw_arc(Vector2(3, 3), RADIUS - 3.0, 0.2, 1.9, 10, color.darkened(0.35), 4.0)
	var v := Vector2(facing * 4.0, -3.0)
	draw_line(v + Vector2(-8, 0), v + Vector2(8, 0), Palette.INK, 7.0)
	draw_line(v + Vector2(-6, 0), v + Vector2(6, 0), Palette.PAPER, 3.0)
	draw_set_transform(Vector2.ZERO)

	# Reversed-controls warning: orbiting ink marks.
	if _reverse_timer > 0.0:
		var rc: Color = Palette.BLOCKS["reverse_block"][1]
		var t := Time.get_ticks_msec() * 0.006
		for k in 2:
			var a := t + k * PI
			var p := Vector2(cos(a), sin(a) * 0.5) * (RADIUS + 14)
			draw_circle(p, 5.0, Palette.INK)
			draw_circle(p, 3.0, rc)

	# Name tag + ability pips
	var font := UiTheme.heavy()
	var tag := "P%d" % player_id
	draw_string_outline(font, Vector2(-30, -RADIUS - 18), tag, HORIZONTAL_ALIGNMENT_CENTER, 60, 20, 6, Palette.INK)
	draw_string(font, Vector2(-30, -RADIUS - 18), tag, HORIZONTAL_ALIGNMENT_CENTER, 60, 20, color)
	_draw_pip(Vector2(-8, -RADIUS - 9), shock_ready())
	_draw_pip(Vector2(8, -RADIUS - 9), gravity_ready())


func _draw_pip(p: Vector2, ready: float) -> void:
	draw_rect(Rect2(p - Vector2(5, 3.5), Vector2(10, 7)), Palette.INK)
	if ready >= 1.0:
		draw_rect(Rect2(p - Vector2(3.5, 2), Vector2(7, 4)), Palette.PAPER)
	else:
		draw_rect(Rect2(p - Vector2(3.5, 2), Vector2(7 * ready, 4)), Color(color, 0.8))
