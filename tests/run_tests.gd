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
	await _test_jump_physics_matches_envelope()
	await _test_game_smoke()
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
	check(dbl > 240.0, "double jump should rise more than the largest normal gap")
	check(chg > dbl, "charged jump must out-reach a double jump")
	check(MapPlanner.reach_h(dbl + 10.0, false) < 0.0, "nothing is reachable above max rise")
	check(MapPlanner.can_reach(-100, 100, 150, 300, 150), "simple sideways hop is reachable")
	check(not MapPlanner.can_reach(-100, 100, 900, 1000, 150), "far platform is unreachable")
	check(not MapPlanner.can_reach(-100, 100, -300, 300, 150), "covered by a much wider platform with no way around")


func _test_planner_invariants() -> void:
	var seeds := 60
	var total_rows := 0
	var type_counts := {}
	for s in range(1, seeds + 1):
		var p := MapPlanner.new(s)
		p.start(0.0)
		p.generate_until(-32000.0)   # all four biomes
		var prev_anchors: Array = p.rows[0].platforms
		for i in range(1, p.rows.size()):
			var row: Dictionary = p.rows[i]
			var prev: Dictionary = p.rows[i - 1]
			var dy: float = prev.y - row.y
			total_rows += 1
			var plats: Array = row.platforms
			check(not plats.is_empty(), "seed %d row %d is empty" % [s, i])
			# Bounds & sizes
			for pl in plats:
				type_counts[pl.type] = type_counts.get(pl.type, 0) + 1
				var lo: float = pl.x0 - pl.travel
				var hi: float = pl.x1 + pl.travel
				check(lo >= -MapPlanner.HALF_WIDTH - 0.1 and hi <= MapPlanner.HALF_WIDTH + 0.1, "seed %d row %d platform out of bounds (%.0f..%.0f)" % [s, i, lo, hi])
				check(pl.x1 - pl.x0 >= MapPlanner.MIN_WIDTH - 0.1, "seed %d row %d platform too narrow" % [s, i])
			# No overlaps inside a row (moving platforms include their travel)
			for a in plats.size():
				for b in range(a + 1, plats.size()):
					var pa: Dictionary = plats[a]
					var pb: Dictionary = plats[b]
					var sep: float = (pb.x0 - pb.travel) - (pa.x1 + pa.travel) if pa.x0 < pb.x0 else (pa.x0 - pa.travel) - (pb.x1 + pb.travel)
					check(sep >= MapPlanner.ROW_SPACING_MIN - 0.5, "seed %d row %d platforms overlap (sep %.1f)" % [s, i, sep])
			# Vertical spacing sane
			check(dy >= 150.0 and dy <= 310.0, "seed %d row %d gap %.0f out of range" % [s, i, dy])
			# Reachability: an anchor reachable from an anchor below
			var anchors := plats.filter(func(pl): return pl.anchor_ok)
			var ok := false
			for a in anchors:
				for src in prev_anchors:
					if MapPlanner.can_reach(src.x0, src.x1, a.x0, a.x1, dy, row.charged):
						ok = true
			check(ok, "seed %d row %d has no reachable anchor" % [s, i])
			var reached := anchors.filter(func(pl): return MapPlanner.can_reach_any(prev_anchors, pl, dy, row.charged))
			if not ok:
				print("  row detail: dy=%.0f charged=%s prev=%s now=%s" % [dy, row.charged, _spans(prev_anchors), _spans(plats)])
			prev_anchors = reached if not reached.is_empty() else anchors
	print("Planner: %d rows over %d seeds, block mix %s" % [total_rows, seeds, type_counts])
	check(type_counts.size() >= 9, "every block type should appear at least once")


func _spans(plats: Array) -> String:
	return ", ".join(plats.map(func(p): return "[%.0f..%.0f %s]" % [p.x0, p.x1, p.type]))


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
	var cases := [Vector2(300, 120), Vector2(120, 200), Vector2(220, 180), Vector2(60, 225), Vector2(30, 220), Vector2(160, 228)]
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
		var stop := p.velocity.x * p.velocity.x / (2.0 * Player.AIR_ACCEL * 0.6)
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
