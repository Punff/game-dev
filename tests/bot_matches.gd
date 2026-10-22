extends Node

## Plays whole matches with simple climbing bots and records them with
## Telemetry (tagged "bot"), to exercise the stats pipeline and to get a
## rough feel for a tuning change before people play it:
##   TELEMETRY_LOG=/tmp/bots.jsonl godot --headless --fixed-fps 60 --path . res://tests/bot_matches.tscn -- --matches=6
## Add --signaling=ws://127.0.0.1:8787 to upload to a local `wrangler dev`
## (BOT_UPLOAD=1); bots never upload anywhere else.
##
## The bots climb the way the map is built to be climbed: from the platform
## they're on they pick one MapPlanner says they can reach (its own jump
## envelope), run to a take-off spot that isn't under it, jump, double-jump
## at the top and only drift over it once they're above its edge - the same
## policy the planner checks every row with. Charged jumps when only those
## reach. They blast and throw the way people do (see SHOCK_RATE). Each match uses a fixed
## map seed (--seed-base=N, default 1000), so a run before and after a change
## plays the same maps: compare with tools/analytics/compare.py.

const CAP := 150.0                 ## s of match time before the survivors are retired
const SPEED := 1.0                 ## Engine.time_scale while a match runs (run with --fixed-fps 60 for speed)

# ── Abilities, the way people use them ───────
# From the live couch matches (169 matches, 143 player-minutes, 2026-10-22);
# check a change with tools/analytics/abilities.py. People blast nearly as
# soon as the cooldown lets them once someone is within 6 m, now and then
# out to 9 m (the blast's reach), hardly ever further, and from the first
# second of a match. 84% of blasts go sideways, the rest up or down about
# evenly. The gravity field is a rare, short thing (0.2-0.9 s), used about
# as often whoever is near, and mostly let go of without a throw.
## Blasts per second while ready, by distance (m) to the nearest player.
const SHOCK_RATE := [[3.0, 1.6], [6.0, 1.4], [9.0, 0.15], [15.0, 0.03], [INF, 0.013]]
const SHOCK_STRAIGHT := 0.16       ## share of blasts aimed up/down (half each) rather than sideways
const FIELD_RATE := 0.026          ## gravity fields per second while ready
const FIELD_TIME := Vector2(0.2, 0.9)
const FIELD_THROW := 0.1           ## share of fields that end in a throw at the nearest player

var _rng := RandomNumberGenerator.new()
var _seed_base := 1000


func _ready() -> void:
	var matches := 6
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--matches="):
			matches = int(arg.get_slice("=", 1))
		elif arg.begins_with("--seed-base="):
			_seed_base = int(arg.get_slice("=", 1))
	if not OS.has_environment("BOT_UPLOAD") or Net.signaling_url == Net.SIGNALING_URL:
		OS.set_environment("NO_STATS", "1")   # never the live server
	OS.set_environment("MATCH_LOG_IN_TESTS", "1")
	if not OS.has_environment("TELEMETRY_LOG"):
		Telemetry.log_path = "user://logs/bot_matches.jsonl"   # never mixed into the player's own log
	Telemetry.tag = "bot"
	_rng.seed = 11
	await get_tree().process_frame
	for i in matches:
		var n: int = [1, 2, 4, 1, 3, 2][i % 6]
		await _play(n, i)
	await get_tree().create_timer(2.0).timeout   # let the last upload finish
	get_tree().quit()


func _play(n: int, index: int) -> void:
	PlayerManager.clear()
	for d in [Settings.DEVICE_KB_A, Settings.DEVICE_KB_B, 0, 1].slice(0, n):
		PlayerManager.join(d)
	MatchManager.state = MatchManager.State.COUNTDOWN
	MatchManager.next_map_seed = _seed_base + index
	_rng.seed = 11 + index   # per match, so a run reproduces match for match
	PlayerManager.reset_match_stats()
	# The whole match at one speed (countdown too), recorded with it, so
	# tests/replay.tscn can play it back exactly.
	Engine.time_scale = SPEED
	var scene: Node = load("res://scenes/game.tscn").instantiate()
	get_tree().root.add_child(scene)
	for i in roundi(4.0 * Engine.physics_ticks_per_second):   # the countdown, counted in ticks (a timer can land either side of one)
		await get_tree().physics_frame
	var brains := {}
	for p: Player in scene.players:
		brains[p.player_id] = {"hold": {}, "charge_until": 0.0, "field_until": 0.0, "field_throw": false, "target": Rect2(), "charged": false, "stuck": 0.0, "best_y": INF}
	var t := 0.0
	while MatchManager.state != MatchManager.State.ENDED:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		for p: Player in scene.players:
			if not p.is_dead:
				_think(p, brains[p.player_id], scene, t)
		if t > CAP:
			for p: Player in scene.players:
				p.die()
	Engine.time_scale = 1.0
	get_tree().paused = false
	for id in PlayerManager.players:
		for a in Settings.ACTIONS:
			Input.action_release(PlayerManager.action(id, a))
	print("Bot match %d: %d players, %.0f s, best %d m" % [index + 1, n, t, MatchManager.last_results.get("best_height", 0)])
	scene.queue_free()
	await get_tree().process_frame


func _think(p: Player, b: Dictionary, scene: Node, t: float) -> void:
	var want := {}
	var on_floor := p.is_on_floor()
	var feet := p.global_position.y + Player.RADIUS
	# Stuck for a while without getting higher: try something else.
	if feet < b.best_y - 20.0:
		b.best_y = feet
		b.stuck = 0.0
	else:
		b.stuck += get_physics_process_delta_time()
	if on_floor and (b.target.size == Vector2.ZERO or _standing_on(p, b.target) or b.stuck > 3.0 or not _still_there(b.target)):
		if OS.has_environment("BOT_TRACE") and p.player_id == 1:
			print("TRACE t%.1f y%.0f reached=%s stuck=%.1f old=%s" % [t, feet, b.target.size != Vector2.ZERO and _standing_on(p, b.target), b.stuck, b.target])
		_choose(p, b)
		if OS.has_environment("BOT_TRACE") and p.player_id == 1:
			print("      -> %s charged=%s here=%s" % [b.target, b.charged, _here(p)])
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
	_sabotage(p, b, scene, t, want)
	_press(p, b, want)


## The block we're standing on, as a rect (or a sliver at our feet).
func _here(p: Player) -> Rect2:
	for blk in p._floor_blocks:
		if is_instance_valid(blk):
			return blk.get_rect_global()
	return Rect2(p.global_position.x - 8.0, p.global_position.y + Player.RADIUS, 16.0, 4.0)


func _standing_on(p: Player, r: Rect2) -> bool:
	return absf(_here(p).position.y - r.position.y) < 4.0 and _here(p).intersects(r.grow(2.0))


func _still_there(r: Rect2) -> bool:
	for blk: Block in get_tree().get_nodes_in_group("blocks"):
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
	for blk: Block in get_tree().get_nodes_in_group("blocks"):
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
	# Line up behind the take-off spot, then run through it and jump.
	if signf(dx) == dir or absf(dx) > 14.0:
		want["right" if dx > 0.0 else "left"] = true
		if p.is_on_wall():
			want["jump"] = true   # a wall in the way (the start floor's): hop it
	else:
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
		# Not above the ledge yet: keep going, but stop short of passing under it.
		var edge := r.position.x - Player.RADIUS - 6.0 if p.global_position.x < r.position.x else r.end.x + Player.RADIUS + 6.0
		var vx := absf(p.velocity.x)
		var stop := vx * vx / (2.0 * Player.AIR_ACCEL * Player.AIR_BRAKE)
		var under := p.global_position.x > r.position.x - Player.RADIUS and p.global_position.x < r.end.x + Player.RADIUS
		if not under and absf(edge - p.global_position.x) > stop:
			want["right" if edge > p.global_position.x else "left"] = true
		# Second jump at the top of the first.
		if p.velocity.y > -40.0 and p.jumps_left > 0:
			want["jump"] = true
	b.charge_until = 0.0


## The closest platform below us to land on (or an empty rect).
func _landing(p: Player) -> Rect2:
	var feet := p.global_position.y + Player.RADIUS
	var best := Rect2()
	var score := INF
	for blk: Block in get_tree().get_nodes_in_group("blocks"):
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
func _sabotage(p: Player, b: Dictionary, scene: Node, t: float, want: Dictionary) -> void:
	var dt := get_physics_process_delta_time()
	var foe := _nearest_foe(p, scene)
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


func _press(p: Player, b: Dictionary, want: Dictionary) -> void:
	for a in Settings.ACTIONS:
		var act := PlayerManager.action(p.player_id, a)
		var on: bool = want.get(a, false)
		# Taps: a jump or blast has to be released for the next one to count.
		if on and a in ["jump", "shockwave"] and b.hold.get(a, false):
			on = false
		if on:
			Input.action_press(act)
		else:
			Input.action_release(act)
		b.hold[a] = on


func _aim(want: Dictionary, to: Vector2) -> void:
	want.erase("left")
	want.erase("right")
	if to.x > 0.3: want["right"] = true
	elif to.x < -0.3: want["left"] = true
	if to.y > 0.3: want["down"] = true
	elif to.y < -0.3: want["up"] = true


func _nearest_foe(p: Player, scene: Node) -> Player:
	var best: Player = null
	for o: Player in scene.players:
		if o != p and not o.is_dead and (best == null or p.global_position.distance_to(o.global_position) < p.global_position.distance_to(best.global_position)):
			best = o
	return best
