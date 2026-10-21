extends Node

## Writes down how each offline match played out, for tuning the climb:
## lava height/speed and every player's height every half second, each
## jump (kind, rise, air time), time spent close to the lava, deaths (when,
## how high, lava or knock-out) and the result. One JSON object per match is
## appended to user://logs/matches.jsonl, with the tuning constants in
## effect so runs from before and after a tweak can be compared.

const PATH := "user://logs/matches.jsonl"
const SAMPLE_EVERY := 0.5
const PX_PER_M := 50.0
const NEAR_LAVA := 260.0           ## px: where the lava eases off (Lava.update_lava)

var _rec: Dictionary = {}
var _t := 0.0
var _next_sample := 0.0
var _p := {}                       # player_id -> tracking state
var _g: Node = null                # the running game scene


func _ready() -> void:
	process_physics_priority = 100   # after players and the game have moved
	SignalBus.match_started.connect(_on_started)
	SignalBus.player_died.connect(_on_died)
	SignalBus.match_ended.connect(_on_ended)


func _game() -> Node:
	if Net.is_client():
		return null   # guests only see snapshots; the host logs the match
	var scene := get_tree().current_scene
	if scene and scene.scene_file_path.begins_with("res://tests/") and not OS.has_environment("MATCH_LOG_IN_TESTS"):
		return null   # the test suite plays matches too; keep them out of the log
	if is_instance_valid(_g):
		return _g
	for n in [scene] + get_tree().root.get_children():
		if n and n.scene_file_path == MatchManager.GAME:
			_g = n
			return n
	return null


func _on_started() -> void:
	_g = null
	var g := _game()
	if g == null:
		return
	_t = 0.0
	_next_sample = 0.0
	_p.clear()
	for p: Player in g.players:
		_p[p.player_id] = {"floor": true, "vy": 0.0, "takeoff": 0.0, "apex": 0.0, "air": 0.0, "kind": "",
			"jumps": [], "counts": {}, "near_lava": 0.0, "air_total": 0.0}
	_rec = {
		"date": Time.get_datetime_string_from_system(),
		"build": "editor" if OS.has_feature("editor") else OS.get_name(),
		"players": g.players.size(),
		"online": Net.is_online(),
		"tuning": {
			"gravity": Player.GRAVITY, "jump_velocity": Player.JUMP_VELOCITY, "charge_velocity": Player.CHARGE_VELOCITY,
			"speed": Player.SPEED, "lava_base": Lava.BASE_SPEED, "lava_ramp": Lava.RAMP, "lava_max": Lava.MAX_SPEED, "lava_chase_from": Lava.CHASE_FROM, "lava_chase_full": Lava.CHASE_FULL,
			"lava_start_below": g.LAVA_START_BELOW, "lava_grace": g.LAVA_GRACE,
		},
		"samples": [],   # [t, lava_m, lava_speed, [[height_m, gap_m] or null per player]]
		"deaths": [],
	}


func _physics_process(delta: float) -> void:
	var g := _game()
	if g == null or _rec.is_empty() or MatchManager.state != MatchManager.State.PLAYING:
		return
	_t += delta
	var lava_y: float = g.lava.surface_y
	for p: Player in g.players:
		if p.is_dead or not _p.has(p.player_id):
			continue
		_track(p, _p[p.player_id], lava_y, delta)
	if _t >= _next_sample:
		_next_sample += SAMPLE_EVERY
		var row := []
		for p: Player in g.players:
			row.append(null if p.is_dead else [snappedf(-p.global_position.y / PX_PER_M, 0.1), snappedf((lava_y - p.global_position.y) / PX_PER_M, 0.1)])
		_rec.samples.append([snappedf(_t, 0.01), snappedf(-lava_y / PX_PER_M, 0.1), roundi(g.lava.speed), row])


func _track(p: Player, s: Dictionary, lava_y: float, delta: float) -> void:
	var on_floor := p.is_on_floor()
	var vy := p.velocity.y
	if lava_y - p.global_position.y < NEAR_LAVA:
		s.near_lava += delta
	if s.floor and not on_floor:
		s.takeoff = p.global_position.y
		s.apex = p.global_position.y
		s.air = 0.0
		s.kind = "charge" if vy < -(Player.JUMP_VELOCITY + 40.0) else "jump" if vy < -300.0 else "fall"
		_count(s, s.kind)
	elif not on_floor:
		s.air += delta
		s.apex = minf(s.apex, p.global_position.y)
		if vy < s.vy - 300.0:   # a sudden kick upwards mid-air
			var k := "air_jump" if absf(vy + Player.JUMP_VELOCITY) < 30.0 else "boost"
			_count(s, k)
	elif not s.floor:
		s.air_total += s.air
		if s.kind != "fall" or s.air > 0.3:
			s.jumps.append([s.kind, roundi((s.takeoff - s.apex) / 1.0), roundi((s.takeoff - p.global_position.y) / 1.0), snappedf(s.air, 0.01)])
	s.floor = on_floor
	s.vy = vy


func _count(s: Dictionary, k: String) -> void:
	s.counts[k] = s.counts.get(k, 0) + 1


func _on_died(player_id: int) -> void:
	var g := _game()
	if g == null or _rec.is_empty():
		return
	var p: Player = g.player_by_id(player_id)
	if p == null:
		return
	_rec.deaths.append({"player": player_id, "t": snappedf(_t, 0.1), "height_m": snappedf(-p.global_position.y / PX_PER_M, 0.1),
		"max_m": p.height_meters(), "cause": "lava" if p.global_position.y > g.lava.surface_y - 30.0 else "knockout"})


func _on_ended(results: Dictionary) -> void:
	if _rec.is_empty():
		return
	var g := _game()
	_rec["duration"] = snappedf(_t, 0.1)
	_rec["winner"] = results.get("winner", -1)
	var per := {}
	for id in _p:
		var s: Dictionary = _p[id]
		var p: Player = g.player_by_id(id) if g else null
		per[str(id)] = {"max_m": p.height_meters() if p else 0, "counts": s.counts, "near_lava_s": snappedf(s.near_lava, 0.1),
			"air_s": snappedf(s.air_total, 0.1), "flights": s.jumps}   # [kind, rise px, net height gained px, air s]
	_rec["per_player"] = per
	DirAccess.make_dir_recursive_absolute(PATH.get_base_dir())
	var f := FileAccess.open(PATH, FileAccess.READ_WRITE if FileAccess.file_exists(PATH) else FileAccess.WRITE)
	if f:
		f.seek_end()
		f.store_line(JSON.stringify(_rec))
		f.close()
		print("Match log: %.0f s, %d players -> %s" % [_t, _rec.players, ProjectSettings.globalize_path(PATH)])
	_rec = {}
