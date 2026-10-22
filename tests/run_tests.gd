extends Node

## Headless test runner:
##   godot --headless --fixed-fps 60 --path . res://tests/run_tests.tscn   (fast; drop --fixed-fps for real time)
## Exits with code 1 if anything fails.

var _failures := 0
var _checks := 0


func _ready() -> void:
	await get_tree().process_frame   # let autoloads finish _ready
	_test_envelope_sanity()
	_test_planner_invariants()
	_test_planner_always_reachable()
	_test_planner_determinism()
	_test_bindings_roundtrip()
	await _test_field_holds_player()
	await _test_jump_physics_matches_envelope()
	await _test_game_smoke()
	await _test_vanishing_waits()
	await _test_field_spares_holder()
	_test_lava_pressure()
	await _test_no_field_launch()
	await _test_wind_pushes()
	await _test_map_events()
	await _test_sandbox_smoke()
	await _test_menu_smoke()
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


## Seeds whose start floor once left no room for a stepping stone beside it,
## which cut the guaranteed route for the whole map.
func _test_planner_always_reachable() -> void:
	for seed_value in [168, 230]:
		var p := MapPlanner.new(seed_value)
		p.start(0.0)
		var bad := 0
		while p.cursor_y > -20000.0:
			var row: Dictionary = p.generate_until(p.cursor_y - 1.0)[0]
			if not row.platforms.any(func(q): return q.reachable and q.anchor_ok):
				bad += 1
		check(bad == 0, "planner: every row of seed %d has a reachable anchor" % seed_value)


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


# ── Gravity field: debris under your feet holds you up ──

func _test_field_holds_player() -> void:
	PlayerManager.clear()
	var id := PlayerManager.join(Settings.DEVICE_KB_A)
	var block := BreakableBlock.new()
	block.position = Vector2(0, -8000)
	block.set_block_size(Vector2(340, 60))
	get_tree().root.add_child(block)
	var p := Player.new()
	p.setup(PlayerManager.players[id])
	get_tree().root.add_child(p)
	p.global_position = Vector2(0, -8000 - 30 - Player.RADIUS - 1)
	for i in 30:   # settle onto the block, so the jump is from the ground
		await get_tree().physics_frame
		if p.is_on_floor():
			break
	var start_y := p.global_position.y
	# Jump off it (it shatters) and hold the field on the way up.
	p.controls_enabled = true
	Input.action_press(PlayerManager.action(id, "jump"))
	await get_tree().physics_frame
	Input.action_release(PlayerManager.action(id, "jump"))
	Input.action_press(PlayerManager.action(id, "gravity"))
	var on_floor_frames := 0
	var apex := INF
	var lowest := -INF
	var highest := INF
	for i in 90:   # 1.5 s, field lasts 1.6 s
		await get_tree().physics_frame
		if apex == INF:
			if p.velocity.y >= 0.0:
				apex = p.global_position.y
			continue
		if p.is_on_floor():
			on_floor_frames += 1
		lowest = maxf(lowest, p.global_position.y)
		highest = minf(highest, p.global_position.y)
	Input.action_release(PlayerManager.action(id, "gravity"))
	print("Field hold: on debris %d frames after the apex, then sank %.0f px, rose %.0f px" % [on_floor_frames, lowest - apex, apex - highest])
	check(on_floor_frames > 40, "debris gathered under you holds you up while the field is on")
	check(lowest - apex < 120.0, "you don't sink through your own debris floor")
	check(apex - highest < 30.0, "debris doesn't push you upwards")
	for f in get_tree().get_nodes_in_group("fragments"):
		f.free()
	p.free()
	PlayerManager.clear()


# ── Smoke test: the sandbox ("How to play") runs ─

# ── Menus ────────────────────────────────────

func _focus() -> Control:
	return get_viewport().gui_get_focus_owner()


func _frames(n := 3) -> void:
	for i in n:
		await get_tree().process_frame


func _test_menu_smoke() -> void:
	var saved := {"onboarded": Settings.get_value("onboarded"), "auth_token": Settings.get_value("auth_token"), "account_name": Settings.get_value("account_name")}
	Settings.values.auth_token = ""
	Settings.values.onboarded = false
	var shell: UiShell = load(MatchManager.MAIN_MENU).instantiate()
	get_tree().root.add_child(shell)
	await _frames()

	check(not shell.tracklist.visible and shell.sleeve.top() is SignInPage, "menu: first launch asks to sign in")
	shell.sleeve.back()
	check(shell.sleeve.top() is SignInPage, "menu: Back doesn't skip the sign-in gate")
	(shell.sleeve.top() as SignInPage)._play_as_guest()
	await _frames()
	check(shell.tracklist.visible and _focus() is UiTrack, "menu: playing as a guest opens the tracklist")
	check(Settings.get_value("onboarded"), "menu: the guest choice is remembered")

	for id in ["play", "profile", "leaderboard", "settings"]:
		shell.choose(id)
		await _frames()
		var page := shell.sleeve.top()
		check(page != null and shell.sleeve.active, "menu: %s opens in the sleeve" % id)
		check(_focus() != null and shell.sleeve.is_ancestor_of(_focus()), "menu: %s takes focus" % id)
		if page and page.tabs:
			for i in page.tabs.count():
				page.tabs.show_tab(i)
				await _frames(2)
				check(_focus() != null and page.is_ancestor_of(_focus()), "menu: %s tab %s has focus" % [id, page.tabs.tab_name()])
		shell.sleeve.back()
		await _frames()
		check(_focus() is UiTrack and (_focus() as UiTrack).id == id, "menu: back from %s returns to its track" % id)

	shell.choose("play")
	await _frames()
	(shell.sleeve.top() as PlayPage).open_online()
	await _frames()
	check(shell.sleeve.depth() == 2 and shell.sleeve.top() is OnlinePage, "menu: Online opens on top of Play")
	shell.sleeve.back()
	await _frames()
	check(shell.sleeve.depth() == 1 and shell.sleeve.is_ancestor_of(_focus()), "menu: back from Online returns to Play")
	shell.free()

	# Pause: Settings opens in the same sleeve, Back steps out, then resumes.
	var pause := PauseMenu.new()
	get_tree().root.add_child(pause)
	await _frames()
	pause.open()
	await _frames()
	check(get_tree().paused and pause.page.is_ancestor_of(_focus()), "pause: opens paused with focus on its buttons")
	var resume := _focus()
	pause.page.push(SettingsPage.new())
	await _frames()
	check(pause.page.sleeve.top() is SettingsPage and pause.page.sleeve.is_ancestor_of(_focus()), "pause: Settings opens on top")
	pause.page.sleeve.back()
	await _frames()
	check(pause.visible and _focus() == resume, "pause: Back from Settings returns to the pause buttons")
	pause.page.sleeve.back()
	await _frames()
	check(not pause.visible and not get_tree().paused, "pause: Back on the pause page resumes")
	pause.free()
	for k in saved:
		Settings.values[k] = saved[k]
	Settings.save_settings()
	await _frames()


func _test_sandbox_smoke() -> void:
	var sb: Sandbox = load(Sandbox.SCENE).instantiate()
	get_tree().root.add_child(sb)
	await get_tree().create_timer(0.6).timeout
	check(sb.player.is_on_floor(), "sandbox: you spawn standing on the floor")
	sb._teleport(2)   # concrete
	await get_tree().create_timer(0.3).timeout
	check(sb.player.global_position.distance_to(sb._spawn_point(2)) < 20.0, "sandbox: stations teleport you")
	check(is_instance_valid(sb.dummy) and not sb.dummy.is_dead, "sandbox: the dummy is there")
	sb.free()
	PlayerManager.clear()
	await get_tree().process_frame


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
	# Once the match is decided, pause stays shut until the results are up.
	players[1].die()
	await get_tree().process_frame
	check(not scene._can_pause(), "no pausing between the last knock-out and the results")
	await get_tree().create_timer(scene.END_DELAY + 0.5).timeout
	check(MatchManager.state == MatchManager.State.ENDED and scene.end_screen.visible, "results come up after the end delay")
	check(not scene.pause_menu.visible, "the pause menu isn't open under the results")
	get_tree().paused = false
	scene.queue_free()
	await get_tree().process_frame
	PlayerManager.clear()


## Each map event does its thing in a real match.
func _test_map_events() -> void:
	PlayerManager.clear()
	PlayerManager.join(Settings.DEVICE_KB_A)
	MatchManager.next_map_seed = 4242   # a map with concrete in view for the quake
	var scene: Node = load("res://scenes/game.tscn").instantiate()
	get_tree().root.add_child(scene)
	await get_tree().create_timer(4.2).timeout   # countdown
	var ev: MapEvents = scene.events

	ev.start("slab")
	var falling := false
	for i in roundi((MapEvents.WARN + 0.4) * 60.0):
		await get_tree().physics_frame
		for f in get_tree().get_nodes_in_group("fragments"):
			falling = falling or f.linear_velocity.y > 600.0
	check(falling, "map events: a slab drops")

	ev.start("surge")
	await get_tree().create_timer(MapEvents.WARN + 0.2).timeout
	check(scene.lava.surge > 0.0, "map events: the lava surges")
	await get_tree().create_timer(MapEvents.SURGE_TIME).timeout
	check(scene.lava.surge == 0.0, "map events: the surge ends")

	var concrete := func(): return get_tree().get_nodes_in_group("blocks").filter(func(b): return b is BreakableBlock and not b._broken).size()
	var standing: int = concrete.call()
	ev.start("quake")
	await get_tree().create_timer(MapEvents.WARN + 0.2).timeout
	check(concrete.call() < standing, "map events: a quake cracks concrete")

	var loose := get_tree().get_nodes_in_group("fragments").filter(func(f): return f.linear_velocity.y < 300.0)
	var xs := loose.map(func(f): return f.linear_velocity.x)
	ev.start("wind")
	await get_tree().create_timer(MapEvents.WARN + 1.0).timeout
	var moved := 0
	for i in loose.size():
		if is_instance_valid(loose[i]) and absf(loose[i].linear_velocity.x - xs[i]) > 50.0:
			moved += 1
	check(loose.is_empty() or moved > 0, "map events: wind drifts the debris")
	scene.queue_free()
	await get_tree().process_frame
	PlayerManager.clear()


## Your own gravity field doesn't batter you with the chunks it carries (live
## data: most chunk hits were players' own fields pulling debris into them),
## nor right after you let go of them. Someone else's chunks still hit.
func _test_field_spares_holder() -> void:
	PlayerManager.clear()
	var id := PlayerManager.join(Settings.DEVICE_KB_A)
	var other_id := PlayerManager.join(Settings.DEVICE_KB_B)
	var p := Player.new()
	p.setup(PlayerManager.players[id])
	get_tree().root.add_child(p)
	var q := Player.new()
	q.setup(PlayerManager.players[other_id])
	get_tree().root.add_child(q)
	for who in [["carried", p, p], ["just let go", p, p], ["someone else's", p, q]]:
		p.global_position = Vector2(0, -9500)
		p.velocity = Vector2.ZERO
		p._hit_flash = 0.0
		q.global_position = Vector2(4000, -9500)
		var f := Fragment.new()
		var r := Rect2(-20, -12, 40, 24)
		f.setup(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]), Color.GRAY, Color.WHITE)
		get_tree().root.add_child(f)
		f.global_position = p.global_position + Vector2(-70, 0)
		var owner: Player = who[2]
		if who[0] == "carried":
			f.held_by = owner
		elif who[0] == "just let go":
			f.release(owner)
		else:
			f.held_by = owner
		f.linear_velocity = Vector2(900, 0)
		var hit := false
		for i in 12:
			await get_tree().physics_frame
			f.linear_velocity = Vector2(900, 0) if i < 6 else f.linear_velocity
			hit = hit or p._hit_flash > 0.0
		check(hit == (who[0] == "someone else's"), "field chunks: %s chunk %s you" % [who[0], "hits" if who[0] == "someone else's" else "doesn't hit"])
		f.free()
	p.free()
	q.free()
	PlayerManager.clear()


## Riding your debris up is allowed, but within the field's ride budget: it
## used to ratchet into a launch of 1,000+ px/s, more than a full charge.
func _test_no_field_launch() -> void:
	PlayerManager.clear()
	var id := PlayerManager.join(Settings.DEVICE_KB_A)
	var block := BreakableBlock.new()
	block.position = Vector2(0, -8600)
	block.set_block_size(Vector2(340, 60))
	get_tree().root.add_child(block)
	var p := Player.new()
	p.setup(PlayerManager.players[id])
	get_tree().root.add_child(p)
	p.global_position = Vector2(0, -8600 - 30 - Player.RADIUS - 1)
	for i in 30:
		await get_tree().physics_frame
	p.controls_enabled = true
	var act := func(a): return PlayerManager.action(id, a)
	Input.action_press(act.call("jump"))
	await get_tree().physics_frame
	Input.action_release(act.call("jump"))
	Input.action_press(act.call("gravity"))
	for i in 50:
		await get_tree().physics_frame
	Input.action_press(act.call("up"))
	var fastest := 0.0
	for i in 64:
		if i == 4:
			Input.action_release(act.call("gravity"))
		await get_tree().physics_frame
		fastest = maxf(fastest, -p.velocity.y)
	Input.action_release(act.call("up"))
	check(fastest < 950.0, "riding your debris stays within its budget (%.0f px/s)" % fastest)
	for f in get_tree().get_nodes_in_group("fragments"):
		f.free()
	p.free()
	if is_instance_valid(block):
		block.free()
	PlayerManager.clear()


## The lava: a steady climber is eventually caught (faster gets higher), and
## a lead built while you're faster than it holds.
func _test_lava_pressure() -> void:
	var cam := Camera2D.new()
	get_tree().root.add_child(cam)
	var caught := {}
	for pace in [1.5, 2.6, 3.2]:   # m/s
		var lava := Lava.new()
		get_tree().root.add_child(lava)
		lava.surface_y = 650.0
		lava.active = true
		var y := 0.0
		var dt := 1.0 / 30.0
		var t := 0.0
		var biggest_gap := 0.0
		while t < 900.0:
			t += dt
			y -= pace * 50.0 * dt
			lava.update_lava(dt, y, cam)
			biggest_gap = maxf(biggest_gap, lava.surface_y - y)
			if y > lava.surface_y - 4.0:
				break
		caught[pace] = -y / 50.0
		if pace == 3.2:
			check(biggest_gap > 1000.0, "lava: a fast climber banks a lead (%.0f m)" % (biggest_gap / 50.0))
		lava.free()
	print("Lava catches a steady climber: 1.5 m/s at %.0f m, 2.6 at %.0f m, 3.2 at %.0f m" % [caught[1.5], caught[2.6], caught[3.2]])
	check(caught[1.5] < caught[2.6] and caught[2.6] < caught[3.2], "lava: climbing faster gets you higher")
	check(caught[2.6] > 600.0 and caught[2.6] < 1100.0, "lava: a good steady pace is caught somewhere around 850 m")
	cam.free()


## Map-event wind pushes a ball in the air.
func _test_wind_pushes() -> void:
	PlayerManager.clear()
	var id := PlayerManager.join(Settings.DEVICE_KB_A)
	var p := Player.new()
	p.setup(PlayerManager.players[id])
	get_tree().root.add_child(p)
	p.global_position = Vector2(0, -12000)
	Player.wind = MapEvents.WIND_PUSH
	for i in 20:
		await get_tree().physics_frame
	check(p.velocity.x > 50.0, "wind pushes a ball in the air (%.0f px/s)" % p.velocity.x)
	Player.wind = 0.0
	p.free()
	PlayerManager.clear()


## A vanishing block coming back doesn't close around a ball inside it.
func _test_vanishing_waits() -> void:
	var b := VanishingBlock.new()
	b.set_block_size(Vector2(200, 40))
	get_tree().root.add_child(b)
	var p := Player.new()
	p.setup(PlayerInfo.new())
	get_tree().root.add_child(p)
	p.set_physics_process(false)
	p.global_position = b.global_position
	b.on_player_land(p)
	await get_tree().create_timer(VanishingBlock.WARN_TIME + VanishingBlock.GONE_TIME + 0.3).timeout
	check(b.collision_layer == 0, "vanishing block stays gone while a ball is inside it")
	p.global_position += Vector2(0, -300)
	await get_tree().create_timer(0.1).timeout
	check(b.collision_layer == 1, "vanishing block comes back once the ball has left")
	b.free()
	p.free()


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
