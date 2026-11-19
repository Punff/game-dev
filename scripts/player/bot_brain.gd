class_name BotBrain
extends RefCounted

## A computer player: drives one Player's controls (PlayerInput.brain) the
## way a person on a pad would, one tick at a time. Used for "play against
## bots" in the couch lobby and by tests/bot_matches.gd.
##
## It climbs the way the map is built to be climbed: from the platform it's
## on it picks one MapPlanner says it can reach (the planner's own jump
## envelope), runs to a take-off spot that isn't under it, jumps,
## double-jumps at the top and only drifts over it once it's above its edge
## - the same policy the planner checks every row with. Charged jumps when
## only those reach. It blasts and throws the way people do (SHOCK_RATE).
## Only the controls it sends go into the match record, so a match with
## bots replays exactly like any other.

# ── Abilities, the way people use them ───────
# From the party couch matches (96 matches, mostly 4 players, 276
# player-minutes, 2026-11-10); check a change with tools/analytics/abilities.py.
# Since the opening stopped being a brawl (matches last 44 s, not 14),
# people blast about half as often as in October: once every few seconds
# within 6 m, now and then out to 9 m (the blast's reach), hardly ever
# further. 91% of blasts go sideways, the rest mostly up. The gravity field
# is a rare, short thing (0.3-0.8 s), used about as often whoever is near,
# and mostly let go of without a throw.
## Blasts per second while ready, by distance (m) to the nearest player.
const SHOCK_RATE := [[3.0, 0.43], [6.0, 0.26], [9.0, 0.1], [15.0, 0.01], [INF, 0.006]]
const SHOCK_STRAIGHT := 0.1        ## share of blasts aimed up/down (half each) rather than sideways
const FIELD_RATE := 0.018          ## gravity fields per second while ready
const FIELD_TIME := Vector2(0.2, 0.9)
const FIELD_THROW := 0.13          ## share of fields that end in a throw at the nearest player

var player: Player
var _rng := RandomNumberGenerator.new()
var _t := 0.0
var _b := {"hold": {}, "charge_until": 0.0, "field_until": 0.0, "field_throw": false, "target": Rect2(), "charged": false, "stuck": 0.0, "best_y": INF}


func _init(p: Player, rng_seed: int) -> void:
	player = p
	_rng.seed = rng_seed


## This tick's controls, written into `input` (called from PlayerInput.update).
func drive(input: PlayerInput) -> void:
	if not player.controls_enabled or player.is_dead:
		_b.hold = {}
		return
	_t += player.get_physics_process_delta_time()
	var want := _think(player, _b, _t)
	for i in Settings.ACTIONS.size():
		var a := Settings.ACTIONS[i]
		var on: bool = want.get(a, false)
		# Taps: a jump or blast has to be released for the next one to count.
		if on and a in ["jump", "shockwave"] and _b.hold.get(a, false):
			on = false
		_b.hold[a] = on
		if on:
			input.buttons |= 1 << i
	input.move = Vector2(float(want.get("right", false)) - float(want.get("left", false)),
		float(want.get("down", false)) - float(want.get("up", false)))


func _think(p: Player, b: Dictionary, t: float) -> Dictionary:
	var want := {}
	var on_floor := p.is_on_floor()
	var feet := p.global_position.y + Player.RADIUS
	# Stuck for a while without getting higher: try something else.
	if feet < b.best_y - 20.0:
		b.best_y = feet
		b.stuck = 0.0
	else:
		b.stuck += player.get_physics_process_delta_time()
	if on_floor and (b.target.size == Vector2.ZERO or _standing_on(p, b.target) or b.stuck > 3.0 or not _still_there(b.target)):
		_choose(p, b)
		if b.stuck > 3.0:
			b.stuck = 0.0
			b.best_y = feet
	var r: Rect2 = b.target
	if r.size == Vector2.ZERO:
		# Nothing reachable in sight: wander toward the middle and hop.
		want["right" if p.global_position.x < 0.0 else "left"] = true
		if on_floor and _rng.randf() < 0.05:
			want["jump"] = true
	elif on_floor:
		_ground(p, b, r, want, t)
	else:
		_air(p, b, r, want)
	_sabotage(p, b, t, want)
	return want


## The block we're standing on, as a rect (or a sliver at our feet).
func _here(p: Player) -> Rect2:
	for blk in p._floor_blocks:
		if is_instance_valid(blk):
			return blk.get_rect_global()
	return Rect2(p.global_position.x - 8.0, p.global_position.y + Player.RADIUS, 16.0, 4.0)


func _standing_on(p: Player, r: Rect2) -> bool:
	return absf(_here(p).position.y - r.position.y) < 4.0 and _here(p).intersects(r.grow(2.0))


func _still_there(r: Rect2) -> bool:
	for blk: Block in player.get_tree().get_nodes_in_group("blocks"):
		if blk.collision_layer != 0 and blk.get_rect_global().position.y == r.position.y and absf(blk.get_rect_global().get_center().x - r.get_center().x) < 300.0:
			return true
	return false


## The best platform the planner says we can reach from here: high up,
## solid (steel over concrete over the rest), not too far sideways.
func _choose(p: Player, b: Dictionary) -> void:
	var here := _here(p)
	var src := {"x0": here.position.x, "x1": here.end.x, "y": here.position.y + 30.0, "h": 60.0}
	var best := Rect2()
	var best_charged := false
	var score := -INF
	for blk: Block in player.get_tree().get_nodes_in_group("blocks"):
		if blk.collision_layer == 0:
			continue
		var r := blk.get_rect_global()
		var dy := here.position.y - r.position.y
		if dy < 20.0:
			continue
		var dst := {"x0": r.position.x, "x1": r.end.x, "y": r.position.y + r.size.y * 0.5, "h": r.size.y}
		var charged := false
		if not MapPlanner.can_reach_any([src], dst, false):
			if not MapPlanner.can_reach_any([src], dst, true):
				continue
			charged = true
		var kind := 1.0 if blk is StaticPlatform else (0.6 if blk is BreakableBlock else 0.3)
		var s := dy * kind - absf(r.get_center().x - here.get_center().x) * 0.15 - (60.0 if charged else 0.0)
		if blk is CatchupPad and blk.armed and p != CatchupPad.leader:
			s += 600.0   # a lit catch-up pad: take it, like people would
		if s > score:
			score = s
			best = r
			best_charged = charged
	b.target = best
	b.charged = best_charged


## Where to leave the ground for `r`: the end of our platform nearest it,
## but not under it (or we'd hit our head).
func _takeoff(p: Player, r: Rect2) -> float:
	var here := _here(p)
	var gap := Player.RADIUS + 6.0
	if r.position.x - gap > here.position.x and (r.get_center().x >= p.global_position.x or r.end.x + gap > here.end.x):
		return minf(here.end.x - 4.0, r.position.x - gap)
	return maxf(here.position.x + 4.0, r.end.x + gap)


func _ground(p: Player, b: Dictionary, r: Rect2, want: Dictionary, t: float) -> void:
	var off := _takeoff(p, r)
	var dir := signf(r.get_center().x - off)
	# A charge once started is held to full, standing still, then let go
	# heading for the target - letting go early is a weak hop.
	if b.charge_until > 0.0:
		if t < b.charge_until:
			want["charge"] = true
		else:
			b.charge_until = 0.0
			want["right" if dir > 0.0 else "left"] = true
		return
	var dx := off - p.global_position.x
	if b.charged:
		# Charging locks you in place, but you slide on a bit: come to a stop
		# on the spot first (not past it - that can be under the target).
		var vx := p.velocity.x
		var slide := vx * vx / (2.0 * Player.FRICTION)
		if absf(dx) > 6.0 and absf(dx) > slide:
			want["right" if dx > 0.0 else "left"] = true
		elif absf(vx) < 30.0:
			b.charge_until = t + Player.CHARGE_TIME + 0.05
			want["charge"] = true
		return
	# Line up behind the take-off spot, then run through it and jump - but
	# not so fast that we'd drift in under the ledge before we're above it
	# (a head bump there wastes the double jump): brake on the way, so we
	# leave at a speed the air can still stop.
	var gap := Player.RADIUS + 6.0
	var edge := r.position.x - gap if dir > 0.0 else r.end.x + gap
	var air_brake := 2.0 * Player.AIR_ACCEL * Player.AIR_BRAKE
	var room := maxf((edge - p.global_position.x) * dir, 0.0)
	var vx := p.velocity.x
	var drift := vx * vx / air_brake if signf(vx) == dir else 0.0
	var leave := air_brake * maxf((edge - off) * dir - 12.0, 0.0)   # fastest take-off speed, squared
	var braking := (vx * vx - leave) / (2.0 * Player.ACCEL) if signf(vx) == dir and signf(dx) == dir else 0.0
	if signf(dx) == dir and absf(dx) > 14.0 and absf(dx) < braking + 12.0:
		want["left" if dir > 0.0 else "right"] = true
	elif signf(dx) == dir or absf(dx) > 14.0:
		want["right" if dx > 0.0 else "left"] = true
		if p.is_on_wall():
			want["jump"] = true   # a wall in the way (the start floor's): hop it
	elif drift > room:
		want["left" if dir > 0.0 else "right"] = true
	else:
		if room > 20.0:
			want["right" if dir > 0.0 else "left"] = true
		want["jump"] = true


func _air(p: Player, b: Dictionary, r: Rect2, want: Dictionary) -> void:
	var feet := p.global_position.y + Player.RADIUS
	# Falling past where we were going (knocked off, or missed): save
	# ourselves - steer for the nearest platform underneath.
	if p.velocity.y > 150.0 and feet > r.position.y + 40.0:
		var land := _landing(p)
		if land.size != Vector2.ZERO:
			var lx := clampf(p.global_position.x, land.position.x + 15.0, land.end.x - 15.0)
			if absf(lx - p.global_position.x) > 6.0:
				want["right" if lx > p.global_position.x else "left"] = true
			if p.jumps_left > 0 and absf(lx - p.global_position.x) > 120.0:
				want["jump"] = true
			b.target = Rect2()
			return
	var above := feet < r.position.y - 2.0
	var cx := clampf(p.global_position.x, r.position.x + 20.0, r.end.x - 20.0)
	if above:
		if absf(cx - p.global_position.x) > 6.0:
			want["right" if cx > p.global_position.x else "left"] = true
	else:
		# Not above the ledge yet: keep going, but stop short of passing
		# under it (braking hard if we'd drift past), and get out from
		# under it if we're there.
		var x := p.global_position.x
		var side := -1.0 if x < r.get_center().x else 1.0
		var edge := r.position.x - Player.RADIUS - 6.0 if side < 0.0 else r.end.x + Player.RADIUS + 6.0
		var vx := p.velocity.x
		var stop := vx * vx / (2.0 * Player.AIR_ACCEL * Player.AIR_BRAKE) if signf(vx) == -side else 0.0
		var under := x > r.position.x - Player.RADIUS and x < r.end.x + Player.RADIUS
		if under:
			want["right" if side > 0.0 else "left"] = true
		elif absf(edge - x) > stop + 4.0:
			want["right" if edge > x else "left"] = true
		elif stop > absf(edge - x):
			want["right" if side > 0.0 else "left"] = true
		# Second jump at the top of the first.
		if p.velocity.y > -40.0 and p.jumps_left > 0:
			want["jump"] = true
	b.charge_until = 0.0


## The closest platform below us to land on (or an empty rect).
func _landing(p: Player) -> Rect2:
	var feet := p.global_position.y + Player.RADIUS
	var best := Rect2()
	var score := INF
	for blk: Block in player.get_tree().get_nodes_in_group("blocks"):
		if blk.collision_layer == 0:
			continue
		var r := blk.get_rect_global()
		var drop := r.position.y - feet
		if drop < 0.0 or drop > 500.0:
			continue
		var dx := absf(clampf(p.global_position.x, r.position.x, r.end.x) - p.global_position.x)
		var s := dx + drop * 0.3
		if s < score:
			score = s
			best = r
	return best


## Blast and throw like people do (see SHOCK_RATE).
func _sabotage(p: Player, b: Dictionary, t: float, want: Dictionary) -> void:
	var dt := player.get_physics_process_delta_time()
	var foe := _nearest_foe(p)
	if foe and p.shock_cd <= 0.0:
		var m := p.global_position.distance_to(foe.global_position) / 50.0
		var rate := 0.0
		for band in SHOCK_RATE:
			if m < band[0]:
				rate = band[1]
				break
		if _rng.randf() < rate * dt:
			want["shockwave"] = true
			var to := (foe.global_position - p.global_position).normalized()
			if _rng.randf() < SHOCK_STRAIGHT:
				_aim(want, Vector2(0.0, -1.0 if _rng.randf() < 0.5 else 1.0))
			else:
				_aim(want, Vector2(signf(to.x) if to.x != 0.0 else 1.0, 0.0))
	if p.gravity_cd <= 0.0 and t >= b.field_until and _rng.randf() < FIELD_RATE * dt:
		b.field_until = t + _rng.randf_range(FIELD_TIME.x, FIELD_TIME.y)
		b.field_throw = _rng.randf() < FIELD_THROW
	if t < b.field_until:
		want["gravity"] = true
		if foe and b.field_throw and b.field_until - t < 0.15:
			_aim(want, (foe.global_position - p.global_position).normalized())


func _aim(want: Dictionary, to: Vector2) -> void:
	want.erase("left")
	want.erase("right")
	if to.x > 0.3: want["right"] = true
	elif to.x < -0.3: want["left"] = true
	if to.y > 0.3: want["down"] = true
	elif to.y < -0.3: want["up"] = true


func _nearest_foe(p: Player) -> Player:
	var best: Player = null
	for o: Player in player.get_tree().get_nodes_in_group("player"):
		if o != p and not o.is_dead and (best == null or p.global_position.distance_to(o.global_position) < p.global_position.distance_to(best.global_position)):
			best = o
	return best
