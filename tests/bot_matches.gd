extends Node

## Plays whole matches with simple climbing bots and records them with
## Telemetry (tagged "bot"), to exercise the stats pipeline and to get a
## rough feel for a tuning change before people play it:
##   TELEMETRY_LOG=/tmp/bots.jsonl godot --headless --path . res://tests/bot_matches.tscn -- --matches=6
## Add --signaling=ws://127.0.0.1:8787 to upload to a local `wrangler dev`
## (BOT_UPLOAD=1); bots never upload anywhere else.
##
## The bots are crude on purpose: head for the nearest platform above, jump
## and double-jump toward it, charge for big gaps, blast and throw at anyone
## close. They climb, fight and die - enough to fill every part of a record.

const CAP := 150.0                 ## s of match time before the survivors are retired
const SPEED := 3.0                 ## Engine.time_scale while a match runs

var _rng := RandomNumberGenerator.new()
var _clearing := false             # _target: heading for the end of a platform we're under


func _ready() -> void:
	var matches := 6
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--matches="):
			matches = int(arg.get_slice("=", 1))
	if not OS.has_environment("BOT_UPLOAD") or Net.signaling_url == Net.SIGNALING_URL:
		OS.set_environment("NO_STATS", "1")   # never the live server
	OS.set_environment("MATCH_LOG_IN_TESTS", "1")
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
	PlayerManager.reset_match_stats()
	var scene: Node = load("res://scenes/game.tscn").instantiate()
	get_tree().root.add_child(scene)
	await get_tree().create_timer(4.0).timeout
	Engine.time_scale = SPEED
	var brains := {}
	for p: Player in scene.players:
		brains[p.player_id] = {"hold": {}, "charge_until": 0.0, "field_until": 0.0}
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
	var target := _target(p)
	var dx := target.x - p.global_position.x
	var below := target.y < p.global_position.y - 15.0
	if absf(dx) > 12.0:
		want["right" if dx > 0 else "left"] = true
	var on_floor := p.is_on_floor()
	var gap := p.global_position.y - target.y
	# Charge for big gaps, otherwise jump and double-jump at the top of the arc.
	if t < b.charge_until:
		want["charge"] = true
	elif on_floor and below and gap > 230.0 and absf(dx) < (24.0 if _clearing else 80.0) and _rng.randf() < 0.05:
		b.charge_until = t + _rng.randf_range(0.5, 1.3)
		want["charge"] = true
	elif below and on_floor and absf(dx) < (24.0 if _clearing else 170.0) and _rng.randf() < 0.3:
		want["jump"] = true
	elif below and not on_floor and p.velocity.y > -60.0 and p.jumps_left > 0 and (not _clearing or absf(dx) < 40.0) and _rng.randf() < 0.4:
		want["jump"] = true
	# Pick on whoever is close.
	var foe := _nearest_foe(p, scene)
	if foe and p.global_position.distance_to(foe.global_position) < 320.0:
		var to := (foe.global_position - p.global_position).normalized()
		if p.shock_cd <= 0.0 and _rng.randf() < 0.04:
			want["shockwave"] = true
			_aim(want, to)
		elif p.gravity_cd <= 0.0 and _rng.randf() < 0.02:
			b.field_until = t + _rng.randf_range(0.5, 1.2)
	if t < b.field_until:
		want["gravity"] = true
		if foe and b.field_until - t < 0.15:
			_aim(want, (foe.global_position - p.global_position).normalized())
	# Now and then fast-fall onto concrete to smash it.
	if not on_floor and p.velocity.y > 200.0 and _rng.randf() < 0.01:
		want["down"] = true
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


## Where to head: onto the best platform a little above us - or, while
## we're still under it, just past its nearer end so the jump clears it.
func _target(p: Player) -> Vector2:
	var r := _platform(p)
	_clearing = false
	if r.size == Vector2.ZERO:
		return Vector2(0.0, p.global_position.y - 400.0)
	var x := p.global_position.x
	var under := x > r.position.x - Player.RADIUS - 4.0 and x < r.end.x + Player.RADIUS + 4.0
	if p.global_position.y > r.position.y - Player.RADIUS and under and r.size.x < 700.0:
		var left := absf(x - r.position.x) < absf(x - r.end.x)
		x = r.position.x - 34.0 if left else r.end.x + 34.0
		_clearing = true
	else:
		x = clampf(x, r.position.x + 15.0, r.end.x - 15.0)
	return Vector2(x, r.position.y)


func _platform(p: Player) -> Rect2:
	var best := Rect2()
	var score := INF
	for blk: Block in get_tree().get_nodes_in_group("blocks"):
		if blk.collision_layer == 0:
			continue
		var r := blk.get_rect_global()
		var rise := p.global_position.y - r.position.y
		if rise < 30.0 or rise > 330.0:
			continue
		var x := clampf(p.global_position.x, r.position.x + 15.0, r.end.x - 15.0)
		var s := absf(x - p.global_position.x) + absf(rise - 150.0) * 0.6 + absf(x) * 0.15
		if s < score:
			score = s
			best = r
	return best


func _nearest_foe(p: Player, scene: Node) -> Player:
	var best: Player = null
	for o: Player in scene.players:
		if o != p and not o.is_dead and (best == null or p.global_position.distance_to(o.global_position) < p.global_position.distance_to(best.global_position)):
			best = o
	return best
