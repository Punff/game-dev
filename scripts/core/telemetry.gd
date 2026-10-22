extends Node

## Records how each match actually played, for balancing and design: every
## ability use and what it achieved, who hit whom with what, who knocked who
## out, which blocks broke and why, block effects, time spent on each block
## type, stalls (long stretches without climbing), plus player positions and
## the lava every half second for pace charts and heatmaps.
##
## Game code reports the moments that matter (Telemetry.ev / hit / broke /
## died); continuous things (standing on blocks, air time, stalls) are
## tracked here each physics tick. At the end, one JSON record per match is
## appended to user://logs/matches.jsonl and handed to Stats for upload.
## tools/analytics turns a pile of these into a design report.
##
## The host (or offline game) records; online guests only see snapshots.

const SCHEMA := 1
const PATH := "user://logs/matches.jsonl"
const SAMPLE_EVERY := 0.5
const PX_PER_M := 50.0
const NEAR_LAVA := 260.0           ## px: where the lava eases off (Lava.update_lava)
const CREDIT_TIME := 5.0           ## s: a death this soon after a hit is the hitter's knock-out
const PUSH_CREDIT_TIME := 2.0      ## s: same for a jump shove, which happens all the time up close
const STALL_AFTER := 8.0           ## s without a new best height (by 1 m) counts as a stall
const MAX_EVENTS := 8000           ## keeps a marathon match's record a sensible size

## True while a match is being recorded; the hooks are free when it's false.
var recording := false
## Put in the record when set (tests/bot_matches.gd: "bot"), so reports can
## keep bot play apart from people.
var tag := ""
## Where records are appended; TELEMETRY_LOG overrides it.
var log_path := OS.get_environment("TELEMETRY_LOG") if OS.has_environment("TELEMETRY_LOG") else PATH

var _rec: Dictionary = {}
var _events: Array = []
var _t := 0.0
var _next_sample := 0.0
var _p := {}                       # player_id -> tracking state
var _g: Node = null                # the running game scene
var _map_counts := {}              # the map's type_counts (outlives the map if the match is abandoned)


func _ready() -> void:
	process_physics_priority = 100   # after players and the game have moved
	SignalBus.match_started.connect(_on_started)
	SignalBus.match_ended.connect(_on_ended)
	SignalBus.chain_reaction_occurred.connect(func(n: int, pos: Vector2): _add("chain", 0, pos, {"n": n}))


func _game() -> Node:
	if Net.is_client():
		return null   # guests only see snapshots; the host records the match
	var scene := get_tree().current_scene
	if scene and scene.scene_file_path.begins_with("res://tests/") and not OS.has_environment("MATCH_LOG_IN_TESTS"):
		return null   # the test suite plays matches too; keep them out of the data
	if is_instance_valid(_g):
		return _g
	for n in [scene] + get_tree().root.get_children():
		if n and n.scene_file_path == MatchManager.GAME:
			_g = n
			return n
	return null


# ── Hooks called from game code ──────────────

## Something a player did. `data` holds the details worth keeping.
func ev(kind: String, p: Player, data := {}) -> void:
	if recording and p:
		_add(kind, p.player_id, p.global_position, data)


## Something that happened to the world, not to a player (MapEvents).
func world(kind: String, pos: Vector2, data := {}) -> void:
	if recording:
		_add(kind, 0, pos, data)


## A gravity field went up; how many chunks it had to work with says whether
## it was a real play or a whiff.
func field_on(p: Player) -> void:
	if not recording:
		return
	var near := 0
	for f: Node2D in get_tree().get_nodes_in_group("fragments"):
		if f.global_position.distance_to(p.global_position) < Player.GRAVITY_RADIUS:
			near += 1
	ev("field", p, {"near": near})


## `victim` was knocked by `attacker` (null: nobody to credit) with a
## shockwave ("shock"), a flying chunk ("chunk") or a jump shove ("push").
func hit(victim: Player, attacker: Player, kind: String, impulse: Vector2) -> void:
	if not recording or victim.is_dead or not _p.has(victim.player_id):
		return
	var by := attacker.player_id if attacker and attacker != victim else 0
	_p[victim.player_id].last_hit = [by, kind, _t]
	_add("hit", victim.player_id, victim.global_position, {"by": by, "how": kind, "force": roundi(impulse.length())})


## A breakable block shattered: cause is jump / pound / shock / chunk.
func broke(block: Block, cause: String, by: Player) -> void:
	if recording:
		_add("break", by.player_id if is_instance_valid(by) else 0, block.global_position, {"how": cause})


func died(p: Player) -> void:
	if not recording or not _p.has(p.player_id):
		return
	var s: Dictionary = _p[p.player_id]
	_end_stall(p, s)
	var cause := "quit"   # Net knocks out a guest who disconnects
	if p.global_position.y > Player.lava_y - 30.0:
		cause = "lava"
	elif absf(p.global_position.x) > Player.world_half_width + Player.OUT_OF_BOUNDS:
		cause = "side"
	var killer := 0
	var how := ""
	var window := PUSH_CREDIT_TIME if s.last_hit[1] == "push" else CREDIT_TIME
	if s.last_hit[0] > 0 and _t - s.last_hit[2] <= window:
		killer = s.last_hit[0]
		how = s.last_hit[1]
		if _p.has(killer):
			_p[killer].kos += 1
	s.death = {"t": snappedf(_t, 0.1), "cause": cause, "killer": killer, "how": how,
		"height_m": _m(-p.global_position.y), "max_m": p.height_meters(), "block": s.standing}
	_add("death", p.player_id, p.global_position, {"cause": cause, "killer": killer, "how": how})


# ── Match lifecycle ──────────────────────────

func _on_started() -> void:
	_g = null
	recording = false
	var g := _game()
	if g == null:
		return
	recording = true
	_map_counts = g.map_gen.type_counts
	_t = 0.0
	_next_sample = 0.0
	_events = []
	_p.clear()
	var online := Net.is_online()
	var roster := []
	for p: Player in g.players:
		_p[p.player_id] = {"id": p.player_id, "pos": p.global_position, "standing": "", "air": 0.0, "near_lava": 0.0, "block_time": {}, "block_lands": {},
			"best": 0.0, "best_t": 0.0, "stall_from": -1.0, "stall_total": 0.0, "stalls": 0,
			"last_hit": [0, "", -INF], "kos": 0, "death": null}
		roster.append({"id": p.player_id, "client": _client_of(p.info, online, g.players.size()), "name": _name_of(p.info, online),
			"device": "net" if not p.info.is_local() else "kb" if p.info.is_keyboard() else "pad"})
	var tuning := {
		"gravity": Player.GRAVITY, "jump_velocity": Player.JUMP_VELOCITY, "charge_velocity": Player.CHARGE_VELOCITY,
		"speed": Player.SPEED, "gravity_cd": Player.GRAVITY_COOLDOWN, "shock_cd": Player.SHOCK_COOLDOWN,
		"shock_force": Player.SHOCK_FORCE, "shock_range": Player.SHOCK_RANGE, "throw_speed": Player.THROW_SPEED,
		"lava_base": Lava.BASE_SPEED, "lava_ramp": Lava.RAMP, "lava_max": Lava.MAX_SPEED,
		"lava_chase_from": Lava.CHASE_FROM, "lava_chase_full": Lava.CHASE_FULL,
		"lava_start_below": g.LAVA_START_BELOW, "lava_grace": g.LAVA_GRACE,
	}
	_rec = {
		"schema": SCHEMA,
		"date": Time.get_datetime_string_from_system(true),
		"version": str(ProjectSettings.get_setting("application/config/version")),
		"build": "editor" if OS.has_feature("editor") else OS.get_name(),
		"client": Settings.client_id(),
		"mode": "online" if online else "solo" if g.players.size() == 1 else "local",
		"players": g.players.size(),
		"seed": g.map_gen.map_seed,
		"tuning": tuning,
		"tuning_hash": ("%08x" % hash(JSON.stringify(tuning, "", true))),
		"roster": roster,
		"tag": tag,
		"samples": [],   # [t, lava_m, lava px/s, [[x_m, height_m, state] or null per roster entry]]
	}


## Only results that belong to one person count for their stats: a solo run
## (this computer's owner) and online players (each brought their own id).
## Couch players share a computer, so they stay anonymous.
func _client_of(info: PlayerInfo, online: bool, count: int) -> String:
	if online:
		return info.client_id if not info.is_local() or info.client_id != "" else Settings.client_id()
	return Settings.client_id() if count == 1 else ""


func _name_of(info: PlayerInfo, online: bool) -> String:
	if online:
		return info.nick if not info.is_local() or info.nick != "" else Settings.player_name()
	return Settings.player_name() if PlayerManager.players.size() == 1 else info.display_name


func _physics_process(delta: float) -> void:
	if not recording:
		return
	var g := _game()
	if g == null:
		_finish([], -1, true)   # quit to the menu (or lost the host) mid-match
		return
	if MatchManager.state != MatchManager.State.PLAYING:
		return
	_t += delta
	var lava_y: float = g.lava.surface_y
	for p: Player in g.players:
		if not p.is_dead and _p.has(p.player_id):
			_track(p, _p[p.player_id], lava_y, delta)
	if _t >= _next_sample:
		_next_sample += SAMPLE_EVERY
		var row := []
		for p: Player in g.players:
			row.append(null if p.is_dead else [_m(p.global_position.x), _m(-p.global_position.y), _state_of(p)])
		_rec.samples.append([snappedf(_t, 0.01), _m(-lava_y), roundi(g.lava.speed), row])


func _track(p: Player, s: Dictionary, lava_y: float, delta: float) -> void:
	var standing := ""
	for b in p._floor_blocks:
		if is_instance_valid(b):
			standing = b.block_id
			break
	if standing != "":
		s.block_time[standing] = s.block_time.get(standing, 0.0) + delta
		if standing != s.standing:
			s.block_lands[standing] = s.block_lands.get(standing, 0) + 1
	else:
		s.air += delta
	s.standing = standing
	s.pos = p.global_position
	if lava_y - p.global_position.y < NEAR_LAVA:
		s.near_lava += delta
	# Stalls: long stretches without beating your best height by a metre.
	var h := p.max_height_px / PX_PER_M
	if h >= s.best + 1.0:
		_end_stall(p, s)
		s.best = h
		s.best_t = _t
	elif s.stall_from < 0.0 and _t - s.best_t >= STALL_AFTER:
		s.stall_from = s.best_t


## `p` may be gone already (an abandoned match); `s` remembers where it was.
func _end_stall(p: Player, s: Dictionary) -> void:
	if s.stall_from < 0.0:
		return
	var dur: float = _t - s.stall_from
	s.stall_total += dur
	s.stalls += 1
	_add("stall", s.id, p.global_position if p else s.pos, {"dur": snappedf(dur, 0.1), "best_m": snappedf(s.best, 0.1), "block": s.standing})
	s.stall_from = -1.0


func _on_ended(results: Dictionary) -> void:
	if not recording:
		return
	var order := []
	for info: PlayerInfo in results.get("standings", []):
		order.append(info.player_id)
	_finish(order, results.get("winner", -1), false)


## `order`: player ids, winner first (empty when abandoned: place 0 for all).
func _finish(order: Array, winner: int, abandoned: bool) -> void:
	var g := _game()
	var per := {}
	var ids := order if not order.is_empty() else _p.keys()
	var best := 0
	for i in ids.size():
		var id: int = ids[i]
		var s: Dictionary = _p.get(id, {})
		if s.is_empty():
			continue
		var p: Player = g.player_by_id(id) if g else null
		if p == null or not p.is_dead:
			_end_stall(p, s)
		var block_time := {}
		for k in s.block_time:
			block_time[k] = snappedf(s.block_time[k], 0.1)
		var max_m: int = p.height_meters() if p else int(s.best)
		best = maxi(best, max_m)
		per[str(id)] = {
			"place": 0 if abandoned else i + 1, "max_m": max_m, "death": s.death, "kos": s.kos,
			"air_s": snappedf(s.air, 0.1), "near_lava_s": snappedf(s.near_lava, 0.1),
			"stall_s": snappedf(s.stall_total, 0.1), "stalls": s.stalls,
			"block_time": block_time, "block_lands": s.block_lands,
		}
	recording = false   # after the last stalls went in
	_rec["duration"] = snappedf(_t, 0.1)
	_rec["winner"] = winner
	_rec["best_height"] = best
	_rec["abandoned"] = abandoned
	_rec["map"] = {"blocks": _map_counts}
	_rec["per_player"] = per
	_rec["events"] = _events
	_rec["events_dropped"] = _events.size() >= MAX_EVENTS
	_save(_rec)
	Stats.submit_match(_rec)
	_rec = {}
	_events = []


func _save(rec: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(log_path.get_base_dir())
	var f := FileAccess.open(log_path, FileAccess.READ_WRITE if FileAccess.file_exists(log_path) else FileAccess.WRITE)
	if f:
		f.seek_end()
		f.store_line(JSON.stringify(rec))
		f.close()
		print("Telemetry: %.0f s, %d players, %d events -> %s" % [_t, rec.players, _events.size(), ProjectSettings.globalize_path(log_path)])


# ── Helpers ──────────────────────────────────

## [t, kind, player id (0 = nobody), x m, height m, details]
func _add(kind: String, pid: int, pos: Vector2, data: Dictionary) -> void:
	if not recording or _events.size() >= MAX_EVENTS:
		return
	var e := [snappedf(_t, 0.01), kind, pid, _m(pos.x), _m(-pos.y)]
	if not data.is_empty():
		e.append(data)
	_events.append(e)


## g ground, a air, c charging, f gravity field
static func _state_of(p: Player) -> String:
	if p._field_active:
		return "f"
	if p._charging:
		return "c"
	return "g" if p.is_on_floor() else "a"


static func _m(px: float) -> float:
	return snappedf(px / PX_PER_M, 0.1)
