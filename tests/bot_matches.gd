extends Node

## Plays whole matches with simple climbing bots and records them with
## Telemetry (tagged "bot"), to exercise the stats pipeline and to get a
## rough feel for a tuning change before people play it:
##   TELEMETRY_LOG=/tmp/bots.jsonl godot --headless --fixed-fps 60 --path . res://tests/bot_matches.tscn -- --matches=6
## Add --signaling=ws://127.0.0.1:8787 to upload to a local `wrangler dev`
## (BOT_UPLOAD=1); bots never upload anywhere else.
##
## The bots are the game's own computer players (scripts/player/bot_brain.gd),
## every seat taken by one. Each match uses a fixed map seed
## (--seed-base=N, default 1000), so a run before and after a change plays
## the same maps: compare with tools/analytics/compare.py.

const CAP := 150.0                 ## s of match time before the survivors are retired
const SPEED := 1.0                 ## Engine.time_scale while a match runs (run with --fixed-fps 60 for speed)

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
	await get_tree().process_frame
	for i in matches:
		var n: int = [1, 2, 4, 1, 3, 2][i % 6]
		await _play(n, i)
	await get_tree().create_timer(2.0).timeout   # let the last upload finish
	get_tree().quit()


func _play(n: int, index: int) -> void:
	PlayerManager.clear()
	for i in n:
		PlayerManager.add_bot()
	MatchManager.state = MatchManager.State.COUNTDOWN
	MatchManager.next_map_seed = _seed_base + index
	PlayerManager.reset_match_stats()
	# The whole match at one speed (countdown too), recorded with it, so
	# tests/replay.tscn can play it back exactly.
	Engine.time_scale = SPEED
	var scene: Node = load("res://scenes/game.tscn").instantiate()
	get_tree().root.add_child(scene)
	for i in roundi(4.0 * Engine.physics_ticks_per_second):   # the countdown, counted in ticks (a timer can land either side of one)
		await get_tree().physics_frame
	var t := 0.0
	while MatchManager.state != MatchManager.State.ENDED:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		if t > CAP:
			for p: Player in scene.players:
				p.die()
	Engine.time_scale = 1.0
	get_tree().paused = false
	print("Bot match %d: %d players, %.0f s, best %d m" % [index + 1, n, t, MatchManager.last_results.get("best_height", 0)])
	scene.queue_free()
	await get_tree().process_frame
