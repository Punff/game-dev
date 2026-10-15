class_name Player
extends CharacterBody2D

## A ball with a double jump, a charged jump, a gravity field and a shockwave.
## Movement constants are public so the map generator and tests can reason
## about what is reachable.

signal died(player_id: int)

# ── Movement ─────────────────────────────────
const RADIUS := 14.0
const SPEED := 330.0
const ACCEL := 2400.0
const AIR_ACCEL := 1700.0
const FRICTION := 2600.0
const ICE_ACCEL := 500.0
const ICE_FRICTION := 160.0
const GRAVITY := 1500.0
const JUMP_VELOCITY := 640.0
const MAX_JUMPS := 2
const JUMP_CUT := 0.5            ## velocity multiplier when jump is released early
const COYOTE_TIME := 0.1
const JUMP_BUFFER := 0.12
const MAX_FALL := 1100.0
const FAST_FALL_ACCEL := 3200.0
const FAST_FALL_MAX := 1700.0

# ── Charged jump ─────────────────────────────
const CHARGE_TIME := 1.0
const CHARGE_VELOCITY := 980.0   ## at full charge

# ── Abilities ────────────────────────────────
const GRAVITY_COOLDOWN := 4.0
const GRAVITY_DURATION := 1.4
const GRAVITY_RADIUS := 170.0
const SHOCK_COOLDOWN := 3.0
const SHOCK_RANGE := 430.0
const SHOCK_FORCE := 1300.0
const SHOCK_RECOIL := 380.0
const JUMP_PUSH_RADIUS := 110.0
const JUMP_PUSH_FORCE := 380.0

## Half width of the playable column; set by the game from the map generator.
static var world_half_width := 700.0

var info: PlayerInfo
var player_id := 1
var color := Color.WHITE
var is_dead := false
var controls_enabled := false

var jumps_left := MAX_JUMPS
var facing := 1.0
var max_height_px := 0.0
var spawn_y := 0.0

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
var _floor_blocks: Array = []
var _squash := Vector2.ONE
var _trail: PackedVector2Array = []
var _blink := 0.0
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
	_blink = randf_range(1.0, 4.0)


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
	velocity.y = minf(velocity.y + g * delta, MAX_FALL if not _field_active else 220.0)

	if not on_floor and _pressed("down"):
		velocity.y = minf(velocity.y + FAST_FALL_ACCEL * delta, FAST_FALL_MAX)

	_handle_horizontal(delta, on_floor)
	_handle_jump(delta, on_floor)
	_handle_charge(delta, on_floor)
	_handle_abilities(delta)

	move_and_slide()

	var x_limit := world_half_width - RADIUS
	if absf(global_position.x) > x_limit:
		global_position.x = clampf(global_position.x, -x_limit, x_limit)
		velocity.x = 0.0

	_update_floor_blocks(delta)
	_push_players_on_contact()

	if is_on_floor() and not _was_on_floor:
		_on_landed()
	elif not is_on_floor() and _was_on_floor and velocity.y < 0.0:
		_squash = Vector2(0.75, 1.3)
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
		rate = FRICTION if on_floor else AIR_ACCEL * 0.6
	# Don't brake momentum from launches/shockwaves faster than air control allows.
	velocity.x = move_toward(velocity.x, target, rate * delta)


func _handle_jump(delta: float, _on_floor: bool) -> void:
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
		Sfx.play("jump" if grounded_jump else "double_jump", -4.0)
		if not grounded_jump:
			Fx.ring(global_position + Vector2(0, RADIUS), Color(color, 0.8), 34.0, 3.0, 0.25)

	# Variable jump height.
	if _just_released("jump") and velocity.y < -JUMP_VELOCITY * 0.4:
		velocity.y *= JUMP_CUT


func _handle_charge(delta: float, on_floor: bool) -> void:
	if not _charging and on_floor and _just_pressed("charge"):
		_charging = true
		_charge = 0.0
	if not _charging:
		return
	if not on_floor and _coyote <= 0.0:
		_charging = false
		return
	_charge = minf(_charge + delta / CHARGE_TIME, 1.0)
	velocity.x *= 0.85   # plant your feet while charging
	if not _pressed("charge"):
		var ratio := _charge
		_charging = false
		_coyote = 0.0
		velocity.y = -lerpf(JUMP_VELOCITY, CHARGE_VELOCITY, ratio)
		jumps_left = MAX_JUMPS - 1
		_squash = Vector2(0.6, 1.5)
		_on_jumped(1.0 + ratio, true)
		Sfx.play("charge_jump", -3.0, 0.8 + ratio * 0.4)
		Fx.ring(global_position + Vector2(0, RADIUS), color, 50.0 + ratio * 50.0, 5.0, 0.35)
		if ratio > 0.9:
			PlayerManager.rumble(player_id, 0.3, 0.2, 0.12)


func _handle_abilities(delta: float) -> void:
	# Gravity field: hold to hover and herd floating debris.
	if _field_active:
		_field_time += delta
		if not _pressed("gravity") or _field_time >= GRAVITY_DURATION:
			_end_field()
		else:
			_update_field(delta)
	elif _just_pressed("gravity") and gravity_cd <= 0.0:
		_field_active = true
		_field_time = 0.0
		Sfx.play("gravity", -4.0)

	if _just_pressed("shockwave") and shock_cd <= 0.0:
		_fire_shockwave()


func _end_field() -> void:
	_field_active = false
	gravity_cd = GRAVITY_COOLDOWN


func _update_field(delta: float) -> void:
	var aim := aim_vector()
	var frame := Engine.get_physics_frames()
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
		var orbit_a := float(f.get_instance_id() % 628) * 0.01
		var target := global_position + Vector2(0, 46) + Vector2(aim.x, aim.y * 1.5) * 110.0 \
			+ Vector2(cos(orbit_a), sin(orbit_a) * 0.4) * 34.0
		var to_target := target - f.global_position
		var desired := to_target.normalized() * minf(to_target.length() * 5.0, 650.0) + velocity * 0.4
		f.linear_velocity = f.linear_velocity.lerp(desired, minf(6.0 * delta, 1.0))
		f.angular_velocity = lerpf(f.angular_velocity, 0.0, minf(10.0 * delta, 1.0))


func _fire_shockwave() -> void:
	shock_cd = SHOCK_COOLDOWN
	var dir := aim_vector()
	dir = Vector2(facing, 0.0) if dir.length_squared() < 0.1 else dir.normalized()
	var origin := global_position
	Fx.cone(origin, dir, color.lightened(0.3), SHOCK_RANGE)
	Sfx.play("shockwave", -2.0)
	SignalBus.screen_shake_requested.emit(6.0)
	PlayerManager.rumble(player_id, 0.4, 0.3, 0.15)

	# Recoil: firing downwards gives a little rocket-jump.
	velocity -= dir * SHOCK_RECOIL
	if dir.y > 0.5:
		velocity.y = minf(velocity.y, -SHOCK_RECOIL)

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
		if dist > SHOCK_RANGE or dist < 1.0 or to.normalized().dot(dir) < 0.45:
			continue
		var falloff := 1.0 - dist / SHOCK_RANGE
		if node is Player:
			node.hit_by_shockwave(to.normalized() * SHOCK_FORCE * (0.35 + 0.65 * falloff), self)
		elif node is Fragment:
			node.stun = 0.6
			node.apply_central_impulse(to.normalized() * 900.0 * (0.4 + falloff))
		elif node is Block:
			node.on_shockwave(to.normalized(), origin)


func hit_by_shockwave(impulse: Vector2, _from: Player) -> void:
	if is_dead:
		return
	velocity += impulse
	if _field_active:
		_end_field()
	_charging = false
	_squash = Vector2(1.3, 0.75)
	Fx.burst(global_position, color, 8, 220.0, 0.35)
	PlayerManager.rumble(player_id, 0.6, 0.6, 0.25)


func _on_jumped(strength: float, from_ground: bool) -> void:
	if from_ground:
		Fx.dust(global_position + Vector2(0, RADIUS), Color(1, 1, 1, 0.6))
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
		var to := f.global_position - global_position
		var r := 140.0 * strength
		if to.length() < r:
			f.apply_central_impulse(to.normalized() * 260.0 * (1.0 - to.length() / r) * strength)


func _on_landed() -> void:
	var impact := clampf(absf(get_real_velocity().y) / 900.0, 0.0, 1.0)
	_squash = Vector2(1.0 + 0.45 * impact + 0.1, 1.0 - 0.4 * impact - 0.05)
	if impact > 0.25:
		Fx.dust(global_position + Vector2(0, RADIUS), Color(1, 1, 1, 0.5), 6)
		Sfx.play("land", -10.0 + impact * 6.0)


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
			c.velocity += dir * 120.0
			velocity -= dir * 60.0


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
	_field_active = false
	velocity = Vector2.ZERO
	collision_layer = 0
	collision_mask = 0
	Fx.burst(global_position, color, 22, 420.0, 0.8)
	Fx.ring(global_position, color, 120.0, 6.0, 0.5)
	Sfx.play("death")
	SignalBus.screen_shake_requested.emit(14.0)
	PlayerManager.rumble(player_id, 1.0, 1.0, 0.45)
	died.emit(player_id)
	SignalBus.player_died.emit(player_id)
	visible = false
	set_physics_process(false)


# ── Visuals ──────────────────────────────────

func _update_visuals(delta: float) -> void:
	_squash = _squash.lerp(Vector2.ONE, minf(14.0 * delta, 1.0))
	_blink -= delta
	if _blink < -0.12:
		_blink = randf_range(2.0, 5.0)
	if not Fx.reduced and velocity.length_squared() > 420.0 * 420.0:
		_trail.append(global_position)
	elif not _trail.is_empty():
		_trail.remove_at(0)
	if _trail.size() > 8:
		_trail.remove_at(0)
	queue_redraw()


func _draw() -> void:
	# Trail (drawn in world space).
	var n := _trail.size()
	for i in n:
		var t := float(i + 1) / (n + 1)
		draw_circle(to_local(_trail[i]), RADIUS * (0.35 + 0.5 * t), Color(color, 0.18 * t))

	# Gravity field
	if _field_active:
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.012)
		draw_circle(Vector2.ZERO, GRAVITY_RADIUS, Color(color, 0.06 + 0.04 * pulse))
		draw_arc(Vector2.ZERO, GRAVITY_RADIUS, 0.0, TAU, 48, Color(color, 0.45), 2.0, true)
		var rot := Time.get_ticks_msec() * 0.003
		for k in 3:
			var a0 := rot + k * TAU / 3.0
			draw_arc(Vector2.ZERO, GRAVITY_RADIUS * 0.72, a0, a0 + 0.9, 12, Color(color, 0.35), 3.0, true)

	# Charge ring
	if _charging:
		draw_arc(Vector2.ZERO, RADIUS + 9, -PI * 0.5, -PI * 0.5 + TAU * _charge, 32, Color.WHITE if _charge >= 1.0 else color.lightened(0.4), 4.0, true)

	# Body (squash & stretch around the feet).
	var base := Vector2(0, RADIUS)
	draw_set_transform(base - base * _squash, 0.0, _squash)
	draw_circle(Vector2(0, 3), RADIUS, Color(0, 0, 0, 0.3))
	draw_circle(Vector2.ZERO, RADIUS + 2.5, Palette.BG_DEEP)
	draw_circle(Vector2.ZERO, RADIUS, color)
	draw_circle(Vector2(-4, -5), RADIUS * 0.38, Color(1, 1, 1, 0.28))
	# Eyes look where you're going.
	var look := Vector2(facing * 3.0 + velocity.x * 0.004, clampf(velocity.y * 0.004, -3, 3))
	var eye_h := 1.2 if _blink < 0.0 else 5.0
	for ex in [-4.5, 4.5]:
		var c := Vector2(ex, -2) + look
		draw_rect(Rect2(c - Vector2(2.2, eye_h * 0.5), Vector2(4.4, eye_h)), Palette.BG_DEEP)
	draw_set_transform(Vector2.ZERO)

	# Reversed-controls warning: orbiting arrows.
	if _reverse_timer > 0.0:
		var rc := Palette.BLOCKS["reverse_block"][1]
		var t := Time.get_ticks_msec() * 0.006
		for k in 2:
			var a := t + k * PI
			var p := Vector2(cos(a), sin(a) * 0.5) * (RADIUS + 12)
			draw_circle(p, 3.5, rc)

	# Name tag + ability pips
	var font := UiTheme.heavy()
	var tag := "P%d" % player_id
	draw_string_outline(font, Vector2(-30, -RADIUS - 16), tag, HORIZONTAL_ALIGNMENT_CENTER, 60, 16, 5, Palette.BG_DEEP)
	draw_string(font, Vector2(-30, -RADIUS - 16), tag, HORIZONTAL_ALIGNMENT_CENTER, 60, 16, color)
	_draw_pip(Vector2(-7, -RADIUS - 8), shock_ready())
	_draw_pip(Vector2(7, -RADIUS - 8), gravity_ready())


func _draw_pip(p: Vector2, ready: float) -> void:
	draw_circle(p, 4.0, Palette.BG_DEEP)
	if ready >= 1.0:
		draw_circle(p, 3.0, color.lightened(0.35))
	else:
		draw_arc(p, 2.2, -PI * 0.5, -PI * 0.5 + TAU * ready, 10, Color(color, 0.7), 2.0)
