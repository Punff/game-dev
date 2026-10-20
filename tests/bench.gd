extends Node

## Performance benchmark: a real 4-player match with random inputs, and the
## concrete around the players smashed every 1.5 s so debris piles up. Prints
## physics / process time per frame, bucketed by how many chunks are alive.
##   godot --headless --fixed-fps 60 --path . res://tests/bench.tscn   (CPU only)
##   godot --fixed-fps 60 --path . res://tests/bench.tscn              (with drawing)
## --fixed-fps runs the simulation flat out with no waiting, so the wall time
## between frames is the work done (the engine's own timing monitors don't
## update every frame).
## BENCH_SECONDS=30 to run longer.

var _samples: Array = []   # [chunks, physics ms, process ms, nodes, pairs]


func _ready() -> void:
	var seconds := float(OS.get_environment("BENCH_SECONDS")) if OS.has_environment("BENCH_SECONDS") else 20.0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)   # measure work, not the monitor
	# BENCH_WINDOW=2560x1440: a big canvas, like a browser on a high-DPI screen.
	if OS.has_environment("BENCH_WINDOW"):
		var wh := OS.get_environment("BENCH_WINDOW").split("x")
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(Vector2i(int(wh[0]), int(wh[1])))
		await get_tree().create_timer(0.5).timeout
	print("BENCH window %s" % DisplayServer.window_get_size())
	PlayerManager.clear()
	for d in [Settings.DEVICE_KB_A, Settings.DEVICE_KB_B, 0, 1]:
		PlayerManager.join(d)
	var scene: Node = load("res://scenes/game.tscn").instantiate()
	get_tree().root.add_child.call_deferred(scene)
	await get_tree().create_timer(4.2).timeout   # countdown
	# BENCH_HIDE=grit,background,lava,blocks: measure what each layer costs to draw.
	var hide := OS.get_environment("BENCH_HIDE").split(",", false)
	if "grit" in hide: Grit.visible = false
	if "background" in hide: scene.background.visible = false
	if "lava" in hide: scene.lava.visible = false
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var t := 0.0
	var next_inputs := 0.0
	var next_smash := 0.0
	var climb := 0.0
	if OS.has_environment("BENCH_FREEZE"):
		for p in scene.players:
			p.set_physics_process(false)
	while t < seconds:
		var t0 := Time.get_ticks_usec()
		await get_tree().process_frame
		var frame_ms := (Time.get_ticks_usec() - t0) / 1000.0
		t += 1.0 / 60.0
		if t >= next_inputs:
			next_inputs = t + 0.15
			for id in PlayerManager.players:
				for a in Settings.ACTIONS:
					var act := PlayerManager.action(id, a)
					if rng.randf() < (0.5 if a in ["jump", "right", "left"] else 0.2):
						Input.action_press(act)
					else:
						Input.action_release(act)
		if t >= next_smash:
			next_smash = t + 1.5
			# Climb: put everyone on blocks a bit higher, so the map keeps
			# streaming in like a real match (random inputs barely climb).
			climb += 350.0
			var tops: Array = get_tree().get_nodes_in_group("blocks").filter(func(b): return not b is BreakableBlock)
			tops.sort_custom(func(a, b): return absf(a.global_position.y + climb) < absf(b.global_position.y + climb))
			var alive: Array = scene.players.filter(func(p): return not p.is_dead)
			for i in alive.size():
				if i < tops.size():
					var b: Block = tops[i]
					alive[i].global_position = b.global_position - Vector2(0, b.size.y * 0.5 + Player.RADIUS + 1)
					alive[i].velocity = Vector2.ZERO
			var c: Vector2 = scene.camera.get_screen_center_position()
			for b in get_tree().get_nodes_in_group("blocks"):
				if b is BreakableBlock and b.global_position.distance_to(c) < 900 and not OS.has_environment("BENCH_NOSMASH"):
					b.break_apart(c + Vector2(0, 300), 300.0)
		_samples.append([
			get_tree().get_nodes_in_group("fragments").size(),
			frame_ms,
			0.0,
			Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
			Performance.get_monitor(Performance.PHYSICS_2D_COLLISION_PAIRS),
		])
		if MatchManager.state == MatchManager.State.ENDED:
			break
	_report()
	if ClassDB.class_exists("Prof") or true:
		var prof = load("res://scripts/core/prof.gd") if ResourceLoader.exists("res://scripts/core/prof.gd") else null
		if prof:
			var names: Array = prof.acc.keys()
			names.sort_custom(func(a, b): return prof.acc[a] > prof.acc[b])
			for n in names:
				print("PROF %-34s %8.1f ms total  %7d calls  %6.1f us/call" % [n, prof.acc[n] / 1000.0, prof.calls[n], float(prof.acc[n]) / prof.calls[n]])
	get_tree().quit()


func _report() -> void:
	var buckets := {}
	for s in _samples:
		var k := int(s[0] / 25) * 25
		if not buckets.has(k):
			buckets[k] = []
		buckets[k].append(s)
	print("BENCH frames %d" % _samples.size())
	print("BENCH chunks   frames  frame avg/p95 ms                        nodes  pairs")
	var keys := buckets.keys()
	keys.sort()
	for k in keys:
		var rows: Array = buckets[k]
		print("BENCH %3d-%-3d  %5d   %6.2f / %6.2f     %6.2f / %6.2f   %5d  %5d" % [k, k + 24, rows.size(),
			_avg(rows, 1), _p95(rows, 1), _avg(rows, 2), _p95(rows, 2), int(_avg(rows, 3)), int(_avg(rows, 4))])
	print("BENCH all      %5d   %6.2f / %6.2f     %6.2f / %6.2f" % [_samples.size(),
		_avg(_samples, 1), _p95(_samples, 1), _avg(_samples, 2), _p95(_samples, 2)])
	var worst: Array = _samples.map(func(r): return r[1] + r[2])
	worst.sort()
	print("BENCH frame (physics+process) avg %.2f  p95 %.2f  p99 %.2f  max %.2f ms" % [
		worst.reduce(func(a, b): return a + b, 0.0) / worst.size(), worst[int(worst.size() * 0.95)],
		worst[int(worst.size() * 0.99)], worst[-1]])


static func _avg(rows: Array, i: int) -> float:
	var s := 0.0
	for r in rows:
		s += r[i]
	return s / maxf(rows.size(), 1)


static func _p95(rows: Array, i: int) -> float:
	var v: Array = rows.map(func(r): return r[i])
	v.sort()
	return v[mini(int(v.size() * 0.95), v.size() - 1)]
