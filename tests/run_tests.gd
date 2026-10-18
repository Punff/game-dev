extends Node

## Headless test runner:
##   godot --headless --path . res://tests/run_tests.tscn
## Exits with code 1 if anything fails.

var _failures := 0
var _checks := 0


func _ready() -> void:
	await get_tree().process_frame   # let autoloads finish _ready
	_test_envelope_sanity()
	_test_planner_invariants()
	_test_planner_determinism()
	_test_bindings_roundtrip()
	await _test_bricks()
	await _test_debris_feel()
	await _test_jump_physics_matches_envelope()
	await _test_game_smoke()
	await _test_chaos()
	await _test_knockout()
	print("\n%d checks, %d failures" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func check(cond: bool, msg: String) -> void:
	_checks += 1
	if not cond:
		_failures += 1
		printerr("FAIL: " + msg)


# ── Planner ──────────────────────────────────

func _test_envelope_sanity() -> void:
	var dbl := MapPlanner.max_rise(false)
	var chg := MapPlanner.max_rise(true)
	print("Envelope: double-jump rise %.0f px, charged rise %.0f px, reach@200 %.0f px" % [dbl, chg, MapPlanner.reach_h(200, false)])
	check(dbl > 260.0, "double jump should clear the largest normal row gap")
	check(chg > dbl, "charged jump must out-reach a double jump")
	check(MapPlanner.reach_h(dbl + 10.0, false) < 0.0, "nothing is reachable above max rise")
	check(MapPlanner.can_reach(-100, 100, 150, 300, 150), "simple sideways hop is reachable")
	check(not MapPlanner.can_reach(-100, 100, 900, 1000, 150), "far platform is unreachable")
	check(not MapPlanner.can_reach(-100, 100, -300, 300, 150), "covered by a much wider platform with no way around")


func _test_planner_invariants() -> void:
	var seeds := 60
	var total_rows := 0
	var type_counts := {}
	var contest_rows := 0
	var max_stretch := 0
	for s in range(1, seeds + 1):
		var p := MapPlanner.new(s)
		p.start(0.0)
		p.generate_until(-45000.0)   # all four biomes
		var prev_anchors: Array = p.rows[0].platforms
		var stretch := 0
		for i in range(1, p.rows.size()):
			# Contest rows funnel everyone onto the same platform(s).
			if p.rows[i].template in [MapPlanner.T.CONTEST, MapPlanner.T.PAIR]:
				contest_rows += 1
				stretch = 0
			elif p.rows[0].y - p.rows[i].y > 1400.0:
				stretch += 1
				max_stretch = maxi(max_stretch, stretch)
			var row: Dictionary = p.rows[i]
			var prev: Dictionary = p.rows[i - 1]
			var gap: float = prev.y - row.y
			total_rows += 1
			var plats: Array = row.platforms
			check(not plats.is_empty(), "seed %d row %d is empty" % [s, i])
			for pl in plats:
				type_counts[pl.type] = type_counts.get(pl.type, 0) + 1
				var lo: float = pl.x0 - pl.travel
				var hi: float = pl.x1 + pl.travel
				check(lo >= -MapPlanner.HALF_WIDTH - 0.1 and hi <= MapPlanner.HALF_WIDTH + 0.1, "seed %d row %d platform out of bounds (%.0f..%.0f)" % [s, i, lo, hi])
				check(pl.x1 - pl.x0 >= MapPlanner.MIN_WIDTH - 0.1, "seed %d row %d platform too narrow" % [s, i])
				# Never jammed on top of something from the row below.
				for q in prev.platforms:
					if pl.x1 + pl.travel < q.x0 - q.travel or pl.x0 - pl.travel > q.x1 + q.travel:
						continue
					var clearance: float = MapPlanner.top_of(q) - (pl.y + pl.h * 0.5)
					check(clearance >= Player.RADIUS * 2.0, "seed %d row %d platform squashed onto the row below (%.0f px)" % [s, i, clearance])
			# No overlaps inside a row (moving platforms include their travel)
			for a in plats.size():
				for b in range(a + 1, plats.size()):
					var pa: Dictionary = plats[a]
					var pb: Dictionary = plats[b]
					var sep: float = (pb.x0 - pb.travel) - (pa.x1 + pa.travel) if pa.x0 < pb.x0 else (pa.x0 - pa.travel) - (pb.x1 + pb.travel)
					check(sep >= MapPlanner.ROW_SPACING_MIN - 0.5, "seed %d row %d platforms overlap (sep %.1f)" % [s, i, sep])
			check(gap > 0.0 and gap <= 540.0, "seed %d row %d gap %.0f out of range" % [s, i, gap])
			# Reachability: an anchor reachable from an anchor below
			var anchors := plats.filter(func(pl): return pl.anchor_ok)
			var reached := anchors.filter(func(pl): return MapPlanner.can_reach_any(prev_anchors, pl, row.charged))
			check(not reached.is_empty(), "seed %d row %d has no reachable anchor" % [s, i])
			if reached.is_empty():
				print("  row detail: charged=%s prev=%s now=%s" % [row.charged, _spans(prev_anchors), _spans(plats)])
			prev_anchors = reached if not reached.is_empty() else anchors
	print("Planner: %d rows over %d seeds, block mix %s" % [total_rows, seeds, type_counts])
	check(type_counts.size() >= 9, "every block type should appear at least once")
	print("Contest rows: %d (%.0f%%), longest run without one: %d rows" % [contest_rows, 100.0 * contest_rows / total_rows, max_stretch])
	check(max_stretch <= 6, "a contest row should come along at least every 6 rows")
	check(type_counts.get("breakable", 0) > type_counts.get("static", 0) * 0.6, "breakable concrete should be a big part of the map")


func _spans(plats: Array) -> String:
	return ", ".join(plats.map(func(p): return "[%.0f..%.0f top %.0f %s]" % [p.x0, p.x1, MapPlanner.top_of(p), p.type]))


func _test_planner_determinism() -> void:
	var a := MapPlanner.new(1234)
	var b := MapPlanner.new(1234)
	a.start(0.0)
	b.start(0.0)
	a.generate_until(-8000.0)
	b.generate_until(-8000.0)
	check(var_to_str(a.rows) == var_to_str(b.rows), "same seed must produce the same map")


# ── Settings / input ─────────────────────────

func _test_bindings_roundtrip() -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_G
	ev.pressed = true
	var b := Settings.event_to_binding(ev, false)
	check(b.get("k") == KEY_G, "key binding captured")
	var back := Settings.binding_to_event(b)
	check(back is InputEventKey and back.physical_keycode == KEY_G, "key binding rebuilt")
	var jm := InputEventJoypadMotion.new()
	jm.axis = JOY_AXIS_TRIGGER_RIGHT
	jm.axis_value = 0.9
	var jb := Settings.event_to_binding(jm, true)
	check(jb.get("a") == JOY_AXIS_TRIGGER_RIGHT and jb.get("v") == 1.0, "trigger binding captured")
	check(Settings.binding_label(jb) == "RT", "trigger label")
	check(Settings.event_to_binding(jm, false).is_empty(), "pad input ignored when binding keyboard")

	# Actions are built per player and follow remaps.
	PlayerManager.clear()
	var id := PlayerManager.join(Settings.DEVICE_KB_A)
	var act := PlayerManager.action(id, "jump")
	check(InputMap.has_action(act), "player action created")
	var old: Dictionary = Settings.bindings.kb_a.jump[0]
	Settings.bindings.kb_a.jump[0] = {"k": KEY_G, "loc": 0}
	SignalBus.bindings_changed.emit()
	var has_g := InputMap.action_get_events(act).any(func(e): return e is InputEventKey and e.physical_keycode == KEY_G)
	check(has_g, "remap reaches InputMap")
	Settings.bindings.kb_a.jump[0] = old
	SignalBus.bindings_changed.emit()
	var pad := PlayerManager.join(0)
	var pad_ev := InputMap.action_get_events(PlayerManager.action(pad, "jump"))
	check(pad_ev.size() > 0 and pad_ev.all(func(e): return e.device == 0), "pad actions bound to their device")
	PlayerManager.clear()


# ── Physics: the real Player can do what the planner assumes ──

func _test_jump_physics_matches_envelope() -> void:
	# Cases inside the planner's safety margin must succeed with a simple bot:
	# run right, jump, double jump at the apex, hold right.
	var cases := [Vector2(250, 100), Vector2(120, 200), Vector2(200, 180), Vector2(60, 230), Vector2(30, 220), Vector2(300, 120)]
	for c in cases:
		check(MapPlanner.can_reach(-150, 0, c.x, c.x + 150, c.y), "case %s should be planner-reachable" % c)
		var landed := await _bot_jump(c.x, c.y)
		check(landed, "bot failed to land on a platform %.0f px across and %.0f px up" % [c.x, c.y])


func _bot_jump(dx: float, dy: float) -> bool:
	PlayerManager.clear()
	var id := PlayerManager.join(Settings.DEVICE_KB_A)
	var world := Node2D.new()
	get_tree().root.add_child(world)
	var a := StaticPlatform.new()
	a.position = Vector2(-75, 0)
	a.set_block_size(Vector2(150, Block.HEIGHT))
	world.add_child(a)
	var b := StaticPlatform.new()
	b.position = Vector2(dx + 75, -dy)
	b.set_block_size(Vector2(150, Block.HEIGHT))
	world.add_child(b)
	var p := Player.new()
	p.setup(PlayerManager.players[id])
	p.controls_enabled = true
	world.add_child(p)
	p.global_position = Vector2(-140, -Block.HEIGHT * 0.5 - Player.RADIUS)
	var right := PlayerManager.action(id, "right")
	var jump := PlayerManager.action(id, "jump")
	var success := false
	var jumped := 0
	var above := false
	for frame in 260:
		await get_tree().physics_frame
		var x := p.global_position.x
		var rise := -Block.HEIGHT * 0.5 - Player.RADIUS - p.global_position.y
		if rise >= dy + 2.0:
			above = true
		# Same policy MapPlanner.simulate_ledge assumes: approach the ledge,
		# don't go under it until you're above it, then drift over.
		var stop := p.velocity.x * p.velocity.x / (2.0 * Player.AIR_ACCEL * Player.AIR_BRAKE)
		var want_right := x + stop < (dx + 75.0 if above else dx - Player.RADIUS - 10.0)
		if want_right:
			Input.action_press(right)
		else:
			Input.action_release(right)
		if jumped == 0 and x > -5:
			Input.action_press(jump)
			jumped = 1
		elif jumped == 1 and p.velocity.y < 0.0:
			jumped = 5   # airborne, wait for the apex
		elif jumped == 5 and p.velocity.y >= 0.0:
			Input.action_release(jump)   # at the apex, so no jump-cut
			jumped = 2
		elif jumped == 2:
			Input.action_press(jump)
			jumped = 3
		if jumped == 0:
			# Approach at the half speed the planner assumes for its take-off.
			if p.velocity.x < Player.SPEED * 0.5:
				Input.action_press(right)
			else:
				Input.action_release(right)
		if OS.has_environment("BOT_DEBUG") and frame % 3 == 0:
			print("   f%d pos %s vel %s floor %s state %d right %s" % [frame, p.global_position.round(), p.velocity.round(), p.is_on_floor(), jumped, want_right])
		if p.is_on_floor() and p.global_position.y < -dy:
			success = true
			break
	if not success:
		print("  bot ended at %s vel %s jumped-state %d" % [p.global_position, p.velocity, jumped])
	Input.action_release(right)
	Input.action_release(jump)
	world.free()
	PlayerManager.clear()
	await get_tree().process_frame
	return success


# ── Brick walls ──────────────────────────────

func _make_wall(pos: Vector2, size: Vector2) -> BreakableBlock:
	var b := BreakableBlock.new()
	b.position = pos
	b.set_block_size(size)
	get_tree().root.add_child(b)
	return b


func _alive_bricks(b: BreakableBlock) -> Array:
	return b._bricks.filter(func(k): return k.alive)


func _test_bricks() -> void:
	# Layout: bricks tile the block exactly, in courses, with staggered joints.
	for sz in [Vector2(160, 60), Vector2(420, 60), Vector2(300, 120), Vector2(90, 60)]:
		var b := _make_wall(Vector2(1000, -5000), sz)
		var area := 0.0
		for k in b._bricks:
			area += k.rect.get_area()
			check(Rect2(-sz * 0.5, sz).grow(0.01).encloses(k.rect), "brick inside its block (%s)" % sz)
			check(k.rect.size.x > BreakableBlock.BRICK_W * 0.25, "no sliver bricks (%s)" % sz)
		check(absf(area - sz.x * sz.y) < 1.0, "bricks cover the whole block (%s)" % sz)
		check(b._bricks.size() >= roundi(sz.y / BreakableBlock.COURSE_H) * (2 if sz.x >= 160 else 1), "several bricks per block (%s)" % sz)
		b.free()
	var wa := _make_wall(Vector2(300, -5000), Vector2(420, 60))
	var wb := _make_wall(Vector2(300, -5000), Vector2(420, 60))
	check(wa._bricks.size() == wb._bricks.size() and wa._bricks[1].rect == wb._bricks[1].rect, "same block position gives the same bricks")
	wa.free()
	wb.free()

	# Damage is local.
	var w := _make_wall(Vector2(0, -5000), Vector2(600, 60))
	var total := w._bricks.size()
	w.hit_by_debris(Vector2(-280, -5000), Vector2(900, 0))
	var left := _alive_bricks(w).size()
	check(left < total and left >= total - 3, "a flying chunk knocks out one or two bricks")
	w.on_shockwave(Vector2.LEFT, Vector2(420, -5000))
	var after_shock := _alive_bricks(w)
	check(after_shock.size() < left and after_shock.size() > 0, "a shockwave bites into the wall without levelling it")
	for k in after_shock:
		check(k.rect.end.x + w.position.x < 420 - BreakableBlock.SHOCK_BITE + 40, "only bricks inside the bite came loose")
	await get_tree().physics_frame
	check(get_tree().get_nodes_in_group("fragments").size() >= total - after_shock.size() , "loose bricks became debris")
	w.break_apart(Vector2(0, -4900))
	await get_tree().process_frame
	check(not is_instance_valid(w), "a wall with no bricks left is removed")
	for f in get_tree().get_nodes_in_group("fragments"):
		f.free()


# ── Debris vs. player abilities ──────────────

func _brick_at(pos: Vector2) -> Fragment:
	var f := Fragment.new()
	var hs := Vector2(30, 14)
	f.setup(PackedVector2Array([-hs, Vector2(hs.x, -hs.y), hs, Vector2(-hs.x, hs.y)]), Color.WHITE, Color.WHITE)
	get_tree().root.add_child(f)
	f.global_position = pos
	return f


func _test_debris_feel() -> void:
	PlayerManager.clear()
	var id := PlayerManager.join(Settings.DEVICE_KB_A)
	var floor_block := StaticPlatform.new()
	floor_block.position = Vector2(0, -8000)
	floor_block.set_block_size(Vector2(1200, 60))
	get_tree().root.add_child(floor_block)
	var p := Player.new()
	p.setup(PlayerManager.players[id])
	get_tree().root.add_child(p)
	var top := floor_block.position.y - 30.0 - Player.RADIUS
	p.global_position = Vector2(0, top)
	await get_tree().physics_frame

	# Jump kick: a plain jump shoves nearby debris, a charged jump makes it a projectile.
	var f := _brick_at(Vector2(70, top - 10))
	p._on_jumped(1.0, true)
	var plain := f.linear_velocity.length()
	f.linear_velocity = Vector2.ZERO
	p._on_jumped(2.0, true)
	var charged := f.linear_velocity.length()
	print("Debris: jump kick %.0f px/s, charged kick %.0f px/s" % [plain, charged])
	check(plain > 250.0, "a jump visibly kicks nearby debris")
	check(charged > Fragment.IMPACT_SPEED, "a charged jump launches debris hard enough to hurt")
	check(f.thrown_by == p, "kicked debris doesn't hit the kicker")
	f.free()

	# Gravity field: bricks swing in and settle into a flat floor under you.
	var bricks: Array[Fragment] = []
	for i in 6:
		bricks.append(_brick_at(Vector2(-120 + i * 48, top - 120 - (i % 2) * 40)))
	p.global_position = Vector2(0, top - 200)
	p.controls_enabled = true
	Input.action_press(PlayerManager.action(id, "gravity"))
	for i in 80:   # ~1.3 s
		await get_tree().physics_frame
	var held := p.held_count()
	var spread := 0.0
	var tilt := 0.0
	var speed := 0.0
	for b in bricks:
		spread = maxf(spread, absf(b.global_position.y - p.global_position.y))
		tilt = maxf(tilt, absf(wrapf(b.rotation, -PI * 0.5, PI * 0.5)))
		speed = maxf(speed, (b.linear_velocity - p.velocity).length())
	print("Field: holding %d, max depth below %.0f px, max tilt %.0f°, max rel. speed %.0f px/s" % [held, spread, rad_to_deg(tilt), speed])
	check(held == bricks.size(), "the field gathers every brick in range")
	check(spread < 110.0, "held bricks pack under the player")
	check(tilt < deg_to_rad(15), "bricks packed under you lie flat")
	check(speed < 150.0, "held bricks settle instead of jittering")
	Input.action_release(PlayerManager.action(id, "gravity"))
	await get_tree().physics_frame

	# Ground pound into a pile splashes it.
	for b in bricks:
		b.global_position = Vector2(randf_range(-60, 60), top - 5)
		b.linear_velocity = Vector2.ZERO
	p.gravity_cd = 0.0
	p.global_position = Vector2(0, top - 4)
	p.last_impact = 2000.0
	p._on_landed()
	var fastest := 0.0
	for b in bricks:
		fastest = maxf(fastest, b.linear_velocity.length())
	check(fastest > Fragment.IMPACT_SPEED, "a ground pound sends nearby debris flying")
	for b in bricks:
		b.free()
	p.queue_free()
	floor_block.queue_free()
	await get_tree().process_frame
	PlayerManager.clear()


# ── Smoke test: the real game scene runs ─────

func _test_game_smoke() -> void:
	PlayerManager.clear()
	PlayerManager.join(Settings.DEVICE_KB_A)
	PlayerManager.join(Settings.DEVICE_KB_B)
	MatchManager.state = MatchManager.State.COUNTDOWN
	var scene: Node = load("res://scenes/game.tscn").instantiate()
	get_tree().root.add_child(scene)
	await get_tree().create_timer(5.0).timeout
	var players := get_tree().get_nodes_in_group("player")
	check(players.size() == 2, "two players spawned")
	check(get_tree().get_nodes_in_group("blocks").size() > 20, "map streamed in")
	check(MatchManager.state == MatchManager.State.PLAYING, "countdown finished and match started")
	scene.queue_free()
	await get_tree().process_frame
	PlayerManager.clear()


# ── Chaos: random inputs for every player, exercising all abilities ──

func _test_chaos() -> void:
	PlayerManager.clear()
	for d in [Settings.DEVICE_KB_A, Settings.DEVICE_KB_B, 0, 1]:
		PlayerManager.join(d)
	var scene: Node = load("res://scenes/game.tscn").instantiate()
	get_tree().root.add_child(scene)
	await get_tree().create_timer(4.0).timeout   # countdown
	Engine.time_scale = 3.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var broke := [0]
	SignalBus.block_broken.connect(func(_p): broke[0] += 1)
	var max_h := 0
	for step in 150:
		for id in PlayerManager.players:
			for a in Settings.ACTIONS:
				var act := PlayerManager.action(id, a)
				if rng.randf() < (0.5 if a in ["jump", "right", "left"] else 0.25):
					Input.action_press(act)
				else:
					Input.action_release(act)
		await get_tree().create_timer(0.15).timeout
		for p: Player in scene.players:
			max_h = maxi(max_h, p.height_meters())
		if MatchManager.state == MatchManager.State.ENDED:
			break
	Engine.time_scale = 1.0
	for id in PlayerManager.players:
		for a in Settings.ACTIONS:
			Input.action_release(PlayerManager.action(id, a))
	print("Chaos: %d blocks broken, %d fragments alive, best height %d m, state %s" % [broke[0], get_tree().get_nodes_in_group("fragments").size(), max_h, MatchManager.State.keys()[MatchManager.state]])
	check(get_tree().get_nodes_in_group("blocks").size() > 0, "map still exists after chaos")
	get_tree().paused = false
	scene.queue_free()
	await get_tree().process_frame
	PlayerManager.clear()


func _test_knockout() -> void:
	PlayerManager.clear()
	var id := PlayerManager.join(Settings.DEVICE_KB_A)
	var p := Player.new()
	p.setup(PlayerManager.players[id])
	get_tree().root.add_child(p)
	p.global_position = Vector2(Player.world_half_width + Player.OUT_OF_BOUNDS + 50.0, 0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	check(p.is_dead, "knocked past the arena edge = out")
	p.queue_free()
	PlayerManager.clear()
