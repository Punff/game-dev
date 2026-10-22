extends Node

## Plays a recorded match again from its controls (offline records have
## them: Telemetry "inputs"), on the same map with the same settings - to
## watch a bug happen again, or check a fix:
##   REPLAY_FILE=<matches.jsonl> godot --path . res://tests/replay.tscn
## REPLAY_INDEX picks the record (default -1, the last one). Add
## REPLAY_CHECK=1 (and --headless) to compare each player's height and the
## time they went out with the record instead of watching; it exits 1 if
## they differ - the check that matches still replay faithfully.
## REPLAY_ALL=1 checks every record in the file. --fixed-fps 60 makes it
## run as fast as it can (same physics, no waiting for real time).

var _rec: Dictionary
var _scene: Node
var _died := {}   # player id -> match time when they went out


func _ready() -> void:
	await get_tree().process_frame   # the scene tree is still setting this up
	OS.set_environment("NO_STATS", "1")   # a replay never uploads
	var path := OS.get_environment("REPLAY_FILE")
	if path == "":
		path = Telemetry.PATH
	var index := int(OS.get_environment("REPLAY_INDEX")) if OS.has_environment("REPLAY_INDEX") else -1
	var recs: Array = []
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		_quit("Can't open %s" % path, 2)
		return
	for line in f.get_as_text().split("\n", false):
		var json := JSON.new()   # (quietly: old or cut-off lines are skipped)
		if json.parse(line) == OK and json.data is Dictionary and json.data.has("inputs"):
			recs.append(json.data)
	if recs.is_empty():
		_quit("No replayable records in %s (offline matches since replays were added)" % path, 2)
		return
	var todo: Array = recs if OS.has_environment("REPLAY_ALL") else [recs[index]]
	var failed := 0
	for r in todo:
		_rec = r
		if not await _play():
			failed += 1
	if OS.has_environment("REPLAY_CHECK") or OS.has_environment("REPLAY_ALL"):
		_quit("%d of %d replays match their records." % [todo.size() - failed, todo.size()], 1 if failed else 0)


## Plays _rec; true if it came out as recorded.
func _play() -> bool:
	print("Replay: %s match from %s, seed %d, %d players, %.0f s" % [_rec.mode, _rec.date, _rec.seed, _rec.players, _rec.duration])
	_died = {}

	# The same setup: players in order, map, speed, events (not saved).
	Settings.values.map_events = _rec.get("map_events", true)
	PlayerManager.clear()
	var devices := [Settings.DEVICE_KB_A, Settings.DEVICE_KB_B, 0, 1]
	for i in int(_rec.players):
		PlayerManager.join(devices[i])
	MatchManager.next_map_seed = int(_rec.seed)
	MatchManager.state = MatchManager.State.COUNTDOWN
	Engine.time_scale = float(_rec.get("time_scale", 1.0))
	if not SignalBus.player_died.is_connected(_on_died):
		SignalBus.player_died.connect(_on_died)
	_scene = load("res://scenes/game.tscn").instantiate()
	get_tree().root.add_child(_scene)
	for p: Player in _scene.players:
		p.input.replay = PackedInt32Array(_rec.inputs.get(str(p.player_id), []))
	await _until_over()
	var same := _compare()
	Engine.time_scale = 1.0
	get_tree().paused = false
	_scene.queue_free()
	await get_tree().process_frame
	PlayerManager.clear()
	return same


func _on_died(id: int) -> void:
	_died[id] = _scene._match_time


func _until_over() -> void:
	var cap := float(_rec.duration) + 15.0
	while MatchManager.state != MatchManager.State.ENDED and _scene._match_time < cap:
		await get_tree().physics_frame


func _compare() -> bool:
	var bad := 0
	for p: Player in _scene.players:
		var was: Dictionary = _rec.per_player.get(str(p.player_id), {})
		var death: Variant = was.get("death")
		var was_t: float = death.t if death is Dictionary else -1.0
		var now_t: float = _died.get(p.player_id, -1.0)
		var same: bool = int(was.get("max_m", -1)) == p.height_meters() and absf(was_t - now_t) < 0.25
		if not same:
			bad += 1
		print("  P%d  recorded %3d m, out at %5.1f s   replayed %3d m, out at %5.1f s   %s" % [
			p.player_id, int(was.get("max_m", -1)), was_t, p.height_meters(), now_t, "same" if same else "DIFFERENT"])
	return bad == 0


func _quit(msg: String, code: int) -> void:
	print(msg)
	Engine.time_scale = 1.0
	get_tree().paused = false
	get_tree().quit(code)
