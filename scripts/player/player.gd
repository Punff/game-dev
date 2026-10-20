class_name Player
extends CharacterBody2D

## A ball with a double jump, a charged jump, a gravity field and a shockwave.
## Movement constants are public so the map generator and tests can reason
## about what is reachable.

signal died(player_id: int)

# ── Movement ─────────────────────────────────
# Values follow the original prototype: a small, slippery, floaty ball.
const RADIUS := 10.0
const SPEED := 300.0
const ACCEL := 1080.0
const AIR_ACCEL := 1080.0
const AIR_BRAKE := 0.89          ## fraction of AIR_ACCEL used to slow down with no input
const FRICTION := 960.0
const ICE_ACCEL := 300.0
const ICE_FRICTION := 90.0
const GRAVITY := 1200.0
const JUMP_VELOCITY := 600.0
const MAX_JUMPS := 2
const COYOTE_TIME := 0.1
const JUMP_BUFFER := 0.12
const MAX_FALL := 1600.0
const FAST_FALL_ACCEL := 3500.0
const FAST_FALL_MAX := 2400.0

# ── Charged jump ─────────────────────────────
## Start charging on the ground; keep charging if you run off the edge and
## release whenever - even mid-air - for the launch.
const CHARGE_TIME := 1.2
const CHARGE_VELOCITY := 820.0   ## at full charge

# ── Abilities ────────────────────────────────
const GRAVITY_COOLDOWN := 3.5
const GRAVITY_DURATION := 1.6
const GRAVITY_RADIUS := 170.0
const THROW_SPEED := 1000.0
const FLOOR_WIDTH := 300.0          ## gravity-field floor row width before chunks start a row below
const FLOOR_GAP := 2.0
const FLOOR_ARRIVE := 10.0          ## a chunk this close to its floor slot turns solid
const SHOCK_COOLDOWN := 2.5
const SHOCK_RANGE := 450.0
const SHOCK_FORCE := 1350.0
const SHOCK_RECOIL := 420.0
const ROCKET_NO_FASTFALL := 0.25   ## s after a downward shockwave when "down" won't fast-fall
const AIM_GRACE := 0.12            ## s an aim is remembered for a gravity-field throw
const JUMP_PUSH_RADIUS := 200.0
const JUMP_PUSH_FORCE := 260.0

## Half width of the arena; past this (plus a margin) you've been knocked out.
static var world_half_width := 800.0
## The lava's surface, for the heat glow (INF when there's no lava).
static var lava_y := INF
const HEAT_RANGE := 220.0
const OUT_OF_BOUNDS := 500.0

var info: PlayerInfo
var player_id := 1
var color := Color.WHITE
var is_dead := false
var controls_enabled := false
var name_tag := ""               ## shown over the ball instead of "P<id>"

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
var _phasing: Array[Fragment] = []
var _floor_blocks: Array = []
var _squash := Vector2.ONE
var _trail: PackedVector2Array = []
var _hit_flash := 0.0
var _rocket_time := 0.0             # after a downward blast, holding down doesn't fast-fall
var _last_aim := Vector2.ZERO       # recent aim, so a throw survives letting go of it a moment early
var _last_aim_time := 0.0
var _ring := PackedVector2Array()   # the boiling outline, rebuilt ~10 times a second
var _ring_boil := -1
var input := PlayerInput.new()   ## where controls come from: this machine or the network

## Online guests don't simulate other players' balls: a puppet just shows
## where the host says it is, a few ticks in the past so there's always a
## pair of snapshots to blend between.
var puppet := false
var _snaps: Array = []            # [host tick, position], oldest first
## Online guest: this machine's own ball, simulated here the moment a key is
## pressed and quietly corrected by what the host reports.
var predicted := false
var _history := {}                # input frame -> {"s": state right after that step, "in": packed frame}
var _replaying := false
var _host_report: Array = []      # newest [ack, position, velocity], handled on the next physics tick
var _vis_offset := Vector2.ZERO   # drawn offset that eases a correction in instead of jumping
var _tag: Label
const SNAP_CORRECTION := 600.0    ## further off than this and the ball just jumps to the host's


func _init() -> void:
	collision_layer = 1
	collision_mask = 1
	floor_snap_length = 10.0
	floor_max_angle = deg_to_rad(65)   # stand on tilted, jagged debris without sliding off
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
	input = PlayerInput.new(player_id, p.is_local())
	add_to_group("player")


func _ready() -> void:
	spawn_y = global_position.y
	z_index = 10
	# Name tag as a Label: shaped once, instead of outlined text redrawn every frame.
	var tag := Label.new()
	tag.text = _tag_text()
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.add_theme_font_override("font", UiTheme.heavy())
	tag.add_theme_font_size_override("font_size", 16)
	tag.add_theme_color_override("font_color", color)
	tag.add_theme_color_override("font_outline_color", Palette.INK)
	tag.add_theme_constant_override("outline_size", 5)
	tag.size = Vector2(60, 0)
	tag.position = Vector2(-30, -RADIUS - 16 - UiTheme.heavy().get_ascent(16))
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tag)
	_tag = tag


# ── Input helpers ────────────────────────────

func _pressed(a: String) -> bool:
	return controls_enabled and input.allowed and input.pressed(a)

func _just_pressed(a: String) -> bool:
	return controls_enabled and input.allowed and input.just_pressed(a)

func _just_released(a: String) -> bool:
	return controls_enabled and input.just_released(a)

func aim_vector() -> Vector2:
	var v := input.move if controls_enabled and input.allowed else Vector2.ZERO
	if _reverse_timer > 0.0:
		v.x = -v.x
	return v


# ── Main loop ────────────────────────────────

func _physics_process(delta: float) -> void:
	if is_dead:
		return
	if puppet:
		_follow_snapshots()
		_update_visuals(delta)
		return
	if not _host_report.is_empty():
		_reconcile(_host_report[0], _host_report[1], _host_report[2])
		_host_report = []
	# A guest's ball on the host runs one step per frame of controls received,
	# so it stays in step with the guest's own simulation of it.
	for k in input.steps_due():
		input.update()
		_step(delta)
		if is_dead:
			return
	if predicted:
		var frame := input.pack()
		_history[input.seq] = {"s": _capture(), "in": frame}
		Net.send_frame(self, frame)
	_update_visuals(delta)


func _step(delta: float) -> void:
	var on_floor := is_on_floor()
	gravity_cd = maxf(gravity_cd - delta, 0.0)
	shock_cd = maxf(shock_cd - delta, 0.0)
	_reverse_timer = maxf(_reverse_timer - delta, 0.0)
	_hit_flash = maxf(_hit_flash - delta, 0.0)
	_rocket_time = maxf(_rocket_time - delta, 0.0)
	var aim := aim_vector()
	if aim.length_squared() > 0.2:
		_last_aim = aim
		_last_aim_time = AIM_GRACE
	else:
		_last_aim_time = maxf(_last_aim_time - delta, 0.0)

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

	# (Not right after a rocket-jump: aiming down is the same key.)
	if not on_floor and _pressed("down") and not _field_active and _rocket_time <= 0.0:
		velocity.y = minf(velocity.y + FAST_FALL_ACCEL * delta, FAST_FALL_MAX)

	_handle_horizontal(delta, on_floor)
	_handle_jump(delta)
	_handle_charge(delta, on_floor)
	_handle_abilities(delta)

	var fall_speed := velocity.y
	move_and_slide()

	# No walls: get shoved far enough off the side and you're out.
	if absf(global_position.x) > world_half_width + OUT_OF_BOUNDS and not Net.is_client():
		die()
		return

	if is_on_floor() and not _was_on_floor:
		last_impact = fall_speed
		_on_landed()
	elif not is_on_floor() and _was_on_floor and velocity.y < 0.0:
		_squash = Vector2(0.65, 1.4)
	_update_floor_blocks(delta)
	_push_players_on_contact()
	_was_on_floor = is_on_floor()

	max_height_px = maxf(max_height_px, spawn_y - global_position.y)


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
		_squash = Vector2(0.65, 1.4)
		_on_jumped(1.0, grounded_jump)
		Sfx.play("jump" if grounded_jump else "double_jump", -3.0)
		if not grounded_jump:
			_own_fx(true)
			Fx.ring(global_position + Vector2(0, RADIUS), color, 46.0, 4.0, 0.25)
			_own_fx(false)



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
		_own_fx(true)
		Fx.ring(global_position + Vector2(0, RADIUS), color, 60.0 + ratio * 70.0, 6.0, 0.35)
		Fx.speed_lines(global_position, Vector2.DOWN, color)
		_own_fx(false)
		if ratio > 0.9:
			_rumble(0.3, 0.2, 0.12)


func _handle_abilities(delta: float) -> void:
	# Gravity field: hold to hover and grab chunks; release while aiming to throw them.
	if _field_active:
		_field_time += delta
		if not _pressed("gravity") or _field_time >= GRAVITY_DURATION:
			_end_field(true)
		elif not Net.is_client():   # the host moves the chunks
			_update_field(delta)
	elif _pressed("gravity") and gravity_cd <= 0.0 and _just_pressed("gravity"):
		_field_active = true
		_field_time = 0.0
		Sfx.play("gravity", -3.0)

	if _just_pressed("shockwave") and shock_cd <= 0.0:
		_fire_shockwave()


func _end_field(allow_throw: bool) -> void:
	_field_active = false
	_set_phasing([])
	gravity_cd = GRAVITY_COOLDOWN
	var aim := aim_vector()
	if aim.length_squared() <= 0.2 and _last_aim_time > 0.0:
		aim = _last_aim   # let go of the aim a hair before the field: still a throw
	var thrown := 0
	if allow_throw and aim.length_squared() > 0.2 and not Net.is_client():
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
		_shake(3.0 + thrown)


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
	if aim.length_squared() > 0.2:
		# Chunks gather in a loose cluster where you aim.
		_set_phasing([])
		for idx in held.size():
			var f := held[idx]
			var target := global_position + aim.normalized() * 95.0 + Vector2(cos(idx * 2.4), sin(idx * 2.4)) * (20.0 + idx * 4.0)
			_pull(f, target, delta)
			f.angular_velocity = lerpf(f.angular_velocity, 0.0, minf(10.0 * delta, 1.0))
	else:
		_pack_floor(held, delta)
	_held = held


func _pull(f: Fragment, target: Vector2, delta: float) -> void:
	var to_target := target - f.global_position
	var desired := to_target.normalized() * minf(to_target.length() * 7.0, 900.0) + velocity
	f.linear_velocity = f.linear_velocity.lerp(desired, minf(6.5 * delta, 1.0))


## With no aim, held chunks line up edge to edge under your feet, each with
## its top face at your feet, turning back the way they were cut. The highest
## chunks make the top row, overflow goes in rows underneath (never above
## you), and each row keeps its chunks' left-to-right order so their paths
## don't cross. On the way to its slot a chunk passes through you, so nothing
## jams against the ball; it turns solid once it arrives.
func _pack_floor(held: Array[Fragment], delta: float) -> void:
	held.sort_custom(func(a, b): return a.global_position.y < b.global_position.y)
	var rows: Array = [[]]
	var width := 0.0
	for f in held:
		if width + f.extent.size.x > FLOOR_WIDTH and not rows[-1].is_empty():
			rows.append([])
			width = 0.0
		rows[-1].append(f)
		width += f.extent.size.x + FLOOR_GAP
	var phasing: Array[Fragment] = []
	var top := global_position.y + RADIUS + 1.0
	for row: Array in rows:
		var row_w := -FLOOR_GAP
		var row_h := 0.0
		for f: Fragment in row:
			row_w += f.extent.size.x + FLOOR_GAP
			row_h = maxf(row_h, f.extent.size.y)
		row.sort_custom(func(a, b): return a.global_position.x < b.global_position.x)
		var x := global_position.x - row_w * 0.5
		for f: Fragment in row:
			var target := Vector2(x - f.extent.position.x, top - f.extent.position.y)
			_pull(f, target, delta)
			if f.global_position.distance_to(target) > FLOOR_ARRIVE:
				phasing.append(f)
			f.angular_velocity = lerpf(f.angular_velocity, -wrapf(f.rotation, -PI, PI) * 8.0, minf(10.0 * delta, 1.0))
			x += f.extent.size.x + FLOOR_GAP
		top += row_h + FLOOR_GAP
	_set_phasing(phasing)


## Chunks in `list` pass through this player; every other one is solid again.
func _set_phasing(list: Array[Fragment]) -> void:
	for f in _phasing:
		if is_instance_valid(f) and not f in list:
			f.remove_collision_exception_with(self)
	for f in list:
		if not f in _phasing:
			f.add_collision_exception_with(self)
	_phasing = list


func _fire_shockwave() -> void:
	shock_cd = SHOCK_COOLDOWN
	var dir := aim_vector()
	dir = Vector2(facing, 0.0) if dir.length_squared() < 0.1 else dir.normalized()
	var origin := global_position
	_own_fx(true)
	Fx.cone(origin, dir, color, SHOCK_RANGE)
	_shake(8.0)
	_own_fx(false)
	Sfx.play("shockwave", 0.0)
	_rumble(0.4, 0.3, 0.15)

	# Recoil: firing downwards gives a rocket-jump.
	velocity -= dir * SHOCK_RECOIL
	if dir.y > 0.5:
		velocity.y = minf(velocity.y, -SHOCK_RECOIL * 1.4)
		_rocket_time = ROCKET_NO_FASTFALL
	if Net.is_client():
		return   # what it hits is up to the host

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
	_rumble(0.6, 0.6, 0.25)


func _on_jumped(strength: float, from_ground: bool) -> void:
	if from_ground:
		_own_fx(true)
		Fx.dust(global_position + Vector2(0, RADIUS), Palette.PAPER_DIM)
		_own_fx(false)
	if Net.is_client():
		return   # shoving people and blocks is up to the host
	if from_ground:
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
			other.velocity += to.normalized() * JUMP_PUSH_FORCE * strength
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
	_squash = Vector2(1.0 + 0.4 * (0.5 + impact), 1.0 - 0.4 * (0.5 + impact) * 0.9)
	_own_fx(true)
	if impact > 0.25:
		Fx.dust(global_position + Vector2(0, RADIUS), Palette.PAPER_DIM, 8)
		Sfx.play("land", -8.0 + impact * 6.0)
	if last_impact > 1000.0:
		_shake(5.0)
	_own_fx(false)


## The guest driving this ball already showed its own jumps, landings and
## blasts (it predicts them), so the host marks those effects as theirs and
## they aren't drawn twice. Everything else it causes is shown to everyone.
func _shake(strength: float) -> void:
	if not _replaying:
		SignalBus.screen_shake_requested.emit(strength)


func _rumble(weak: float, strong: float, duration: float) -> void:
	if not _replaying:
		PlayerManager.rumble(player_id, weak, strong, duration)


func _own_fx(on: bool) -> void:
	Fx.owner_peer = info.peer_id if on and info and Net.is_server() and not input.is_local else 0


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
			c.velocity += dir * 200.0
			velocity -= dir * 200.0


# ── Effects from blocks ──────────────────────

func launch(vy: float) -> void:
	velocity.y = -vy
	jumps_left = MAX_JUMPS - 1
	_coyote = 0.0
	_squash = Vector2(0.6, 1.5)
	_rumble(0.2, 0.0, 0.1)


func reverse_controls(duration: float) -> void:
	_reverse_timer = maxf(_reverse_timer, duration)


func is_reversed() -> bool:
	return _reverse_timer > 0.0


func is_charging() -> bool:
	return _charging


func height_meters() -> int:
	return int(max_height_px / 50.0)


func _tag_text() -> String:
	return name_tag if name_tag != "" else "P%d" % player_id


## A point pulled inside the camera's view, so a knock-out far off the side
## still gets its callout where people can read it.
func _on_screen(p: Vector2) -> Vector2:
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return p
	var half := get_viewport_rect().size / cam.zoom * 0.5
	var c := cam.get_screen_center_position()
	var m := Vector2(minf(160.0, half.x), minf(80.0, half.y))
	return p.clamp(c - half + m, c + half - m)


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
	if not Net.is_client():   # online, the host's effects are replayed for us
		Fx.burst(global_position, color, 22, 480.0, 0.8)
		if global_position.y > lava_y - 30.0:
			Fx.splash(Vector2(global_position.x, lava_y), color)
		else:
			Fx.ring(global_position, Palette.PAPER, 140.0, 8.0, 0.5)
		Fx.popup(_on_screen(global_position + Vector2(0, -50)), "%s out" % _tag_text(), color, 30)
		_shake(16.0)
	Sfx.play("death")
	_rumble(1.0, 1.0, 0.45)
	died.emit(player_id)
	SignalBus.player_died.emit(player_id)
	visible = false
	set_physics_process(false)


# ── Network state ────────────────────────────

const NET_STRIDE := 14
enum NetFlag { DEAD = 1, FIELD = 2, CHARGING = 4, REVERSED = 8 }


## Server: append this player's state to a snapshot.
func write_net(out: PackedFloat32Array) -> void:
	var flags := 0
	if is_dead: flags |= NetFlag.DEAD
	if _field_active: flags |= NetFlag.FIELD
	if _charging: flags |= NetFlag.CHARGING
	if _reverse_timer > 0.0: flags |= NetFlag.REVERSED
	out.append_array([player_id, global_position.x, global_position.y, velocity.x, velocity.y, facing,
		flags, _charge, _field_time, gravity_cd, shock_cd, _hit_flash, max_height_px, input.seq])


## Client: take the server's state (data[i] is this player's id).
func read_net(data: PackedFloat32Array, i: int, tick: int) -> void:
	var pos := Vector2(data[i + 1], data[i + 2])
	var vel := Vector2(data[i + 3], data[i + 4])
	var flags := int(data[i + 6])
	_hit_flash = maxf(_hit_flash, data[i + 11])
	max_height_px = maxf(max_height_px, data[i + 12])
	if flags & NetFlag.DEAD and not is_dead:
		global_position = pos
		die()
		return
	if predicted:
		# Rewinding has to happen inside a physics tick (move_and_slide
		# takes its time step from there), so it waits for the next one.
		var ack := int(data[i + 13])
		if _host_report.is_empty() or ack >= _host_report[0]:
			_host_report = [ack, pos, vel]
		return
	if vel.y < -400.0 and velocity.y > -100.0:
		_squash = Vector2(0.65, 1.4)   # just jumped
	elif vel.y >= 0.0 and velocity.y > 500.0 and absf(vel.y) < 50.0:
		_squash = Vector2(1.3, 0.75)   # just landed
	velocity = vel
	_snaps.append([tick, pos])
	if _snaps.size() > 12:
		_snaps.pop_front()
	facing = data[i + 5]
	_field_active = flags & NetFlag.FIELD != 0
	_charging = flags & NetFlag.CHARGING != 0
	_reverse_timer = 1.0 if flags & NetFlag.REVERSED else 0.0
	_charge = data[i + 7]
	_field_time = data[i + 8]
	gravity_cd = data[i + 9]
	shock_cd = data[i + 10]


## Puppet: blend between the two snapshots around the guest's render clock
## (a few ticks behind the newest), so jitter in arrival doesn't show.
func _follow_snapshots() -> void:
	if _snaps.is_empty():
		return
	var t := Net.render_tick
	var a: Array = _snaps[0]
	if t <= a[0]:
		global_position = a[1]
		return
	for k in range(1, _snaps.size()):
		var b: Array = _snaps[k]
		if b[0] >= t:
			global_position = (a[1] as Vector2).lerp(b[1], (t - a[0]) / maxf(b[0] - a[0], 1.0))
			return
		a = b
	# Past the newest snapshot (one is late): carry on a moment at its speed.
	Net.stats.extrapolated += 1
	global_position = (a[1] as Vector2) + velocity * minf(t - a[0], 6.0) / Engine.physics_ticks_per_second


## Predicted ball: the host has used our controls up to frame `ack` and put
## the ball at `pos` going `vel`. If that's not where we had it after the
## same frame (a hit, a shove, a chunk that wasn't where we thought), rewind
## to the host's version of that moment and play our frames since then again,
## silently. The drawing eases from where the ball was to where it now is.
func _reconcile(ack: int, pos: Vector2, vel: Vector2) -> void:
	for n in _history.keys():
		if n < ack:
			_history.erase(n)
	if not _history.has(ack):
		# Nothing to compare with (the match just started): only fix a big gap.
		if global_position.distance_to(pos) > SNAP_CORRECTION * 2.0:
			_snap_to(pos, vel)
		return
	Net.note_lead(input.seq - ack)
	# (The same frame can be reported twice while the host waits for a late
	# one, so the entry stays, corrected, until a newer frame is used.)
	var then: Dictionary = _history[ack]
	var err: Vector2 = pos - then.s[0]
	if err.length_squared() < 0.04 and (vel - then.s[1]).length_squared() < 1.0:
		return
	if err.length() > SNAP_CORRECTION:
		_snap_to(pos, vel)
		return
	Net.stats.corrections += 1
	Net.stats.error_sum += err.length()
	Net.stats.error_max = maxf(Net.stats.error_max, err.length())
	var shown := global_position
	var now_frame: int = input.seq
	then.s[0] = pos
	then.s[1] = vel
	_restore(then.s)
	_replaying = true
	Fx.muted = true
	Sfx.muted = true
	var prev: int = then.in
	var dt := 1.0 / Engine.physics_ticks_per_second
	for n in range(ack + 1, now_frame + 1):
		var h: Dictionary = _history.get(n, {})
		if h.is_empty():
			break
		input.load_frame(h.in, prev)
		prev = h.in
		_step(dt)
		h.s = _capture()
	_replaying = false
	Fx.muted = false
	Sfx.muted = false
	_vis_offset += shown - global_position


## Everything a step of movement depends on, to rewind to (see _reconcile).
func _capture() -> Array:
	return [global_position, velocity, is_on_floor(), jumps_left, _coyote, _jump_buffer, _was_on_floor,
		_reverse_timer, _charging, _charge, gravity_cd, shock_cd, _field_time, _field_active,
		_rocket_time, _last_aim, _last_aim_time, facing]


func _restore(st: Array) -> void:
	global_position = st[0]
	# CharacterBody2D keeps whether it's on the floor from its last move:
	# nudge it down (or up) a hair so that matches the moment we rewind to.
	velocity = Vector2(0, 30) if st[2] else Vector2(0, -30)
	move_and_slide()
	global_position = st[0]
	velocity = st[1]
	jumps_left = st[3]
	_coyote = st[4]
	_jump_buffer = st[5]
	_was_on_floor = st[6]
	_reverse_timer = st[7]
	_charging = st[8]
	_charge = st[9]
	gravity_cd = st[10]
	shock_cd = st[11]
	_field_time = st[12]
	_field_active = st[13]
	_rocket_time = st[14]
	_last_aim = st[15]
	_last_aim_time = st[16]
	facing = st[17]


func _snap_to(pos: Vector2, vel: Vector2) -> void:
	if _history.size() > 0:
		Net.stats.snaps += 1
	global_position = pos
	velocity = vel
	_vis_offset = Vector2.ZERO
	_history.clear()
	reset_physics_interpolation()


# ── Visuals ──────────────────────────────────

func _update_visuals(delta: float) -> void:
	_squash = _squash.lerp(Vector2.ONE, minf(12.0 * delta, 1.0))
	_vis_offset = _vis_offset.lerp(Vector2.ZERO, minf(10.0 * delta, 1.0))
	if _tag:
		_tag.position.x = -30.0 + _vis_offset.x
		_tag.position.y = -RADIUS - 16 - UiTheme.heavy().get_ascent(16) + _vis_offset.y
	if not Fx.reduced and velocity.length_squared() > 520.0 * 520.0:
		_trail.append(global_position)
	elif not _trail.is_empty():
		_trail.remove_at(0)
	if _trail.size() > 6:
		_trail.remove_at(0)
	queue_redraw()


func _draw() -> void:
	draw_set_transform(_vis_offset)
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

	# Lava heat: a hot glow under the ball and wisps of smoke as it gets close.
	var heat := clampf(1.0 - (lava_y - global_position.y - RADIUS) / HEAT_RANGE, 0.0, 1.0)
	if heat > 0.0:
		var t := Time.get_ticks_msec() * 0.001
		var pulse := 0.5 + 0.5 * sin(t * (6.0 + 8.0 * heat))
		draw_circle(Vector2(0, 2), RADIUS + 9.0 + 5.0 * pulse * heat, Color(Palette.RUST, 0.3 * heat))
		draw_circle(Vector2(0, 2), RADIUS + 4.0 + 3.0 * pulse * heat, Color(Palette.MUSTARD, 0.35 * heat))
		for k in 3:
			var f := fposmod(t * 1.1 + k / 3.0, 1.0)
			var p := Vector2((k - 1) * 9.0 + sin(t * 3.0 + k * 2.0) * 4.0, -RADIUS - 2.0 - f * 34.0)
			var r := 3.0 + f * 5.0
			draw_circle(p, r + 1.5, Color(Palette.INK, (1.0 - f) * 0.5 * heat))
			draw_circle(p, r, Color(Palette.PAPER_DIM, (1.0 - f) * 0.8 * heat))

	# Body: hand-drawn ball whose ink line "boils" ~10 times a second, colour
	# fill slightly out of register, a visor slash. Squash around the feet.
	var base := Vector2(0, RADIUS)
	draw_set_transform(_vis_offset + base - base * _squash, 0.0, _squash)
	var boil := int(Time.get_ticks_msec() / 100) + player_id * 31
	if boil != _ring_boil:
		_ring_boil = boil
		_ring = _wobbly_circle(RADIUS + 1.5, boil)
	var ring := _ring
	draw_colored_polygon(Block._shifted(ring, Vector2(4, 5)), Color(Palette.INK, 0.4))
	draw_colored_polygon(Block._shifted(ring, Vector2(-1.5, 1.5)), Palette.PAPER if _hit_flash > 0.0 else color)
	draw_arc(Vector2(2, 2), RADIUS - 3.5, 0.3, 1.8, 8, color.darkened(0.3), 3.0)
	if heat > 0.0:
		draw_arc(Vector2.ZERO, RADIUS - 1.5, 0.2, PI - 0.2, 10, Color(Palette.MUSTARD, heat), 4.0)
	draw_polyline(ring, Palette.INK, 2.5)
	var v := Vector2(facing * 3.0, -2.5)
	draw_line(v + Vector2(-6, 0.5), v + Vector2(6, -0.5), Palette.INK, 5.0)
	draw_line(v + Vector2(-4, 0.5), v + Vector2(4, -0.5), Palette.PAPER, 2.0)
	draw_set_transform(_vis_offset)

	# Reversed-controls warning: orbiting ink marks.
	if _reverse_timer > 0.0:
		var rc: Color = Palette.BLOCKS["reverse_block"][1]
		var t := Time.get_ticks_msec() * 0.006
		for k in 2:
			var a := t + k * PI
			var p := Vector2(cos(a), sin(a) * 0.5) * (RADIUS + 14)
			draw_circle(p, 5.0, Palette.INK)
			draw_circle(p, 3.0, rc)

	# Ability pips (the name tag is a Label child)
	_draw_pip(Vector2(-8, -RADIUS - 9), shock_ready())
	_draw_pip(Vector2(8, -RADIUS - 9), gravity_ready())


static func _wobbly_circle(r: float, seed_value: int) -> PackedVector2Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var pts := PackedVector2Array()
	var n := 14
	for i in n:
		var a := TAU * i / n
		pts.append(Vector2(cos(a), sin(a)) * r * rng.randf_range(0.93, 1.07))
	pts.append(pts[0])
	return pts


func _draw_pip(p: Vector2, ready: float) -> void:
	draw_rect(Rect2(p - Vector2(5, 3.5), Vector2(10, 7)), Palette.INK)
	if ready >= 1.0:
		draw_rect(Rect2(p - Vector2(3.5, 2), Vector2(7, 4)), Palette.PAPER)
	else:
		draw_rect(Rect2(p - Vector2(3.5, 2), Vector2(7 * ready, 4)), Color(color, 0.8))
