class_name MapEvents
extends Node

## Now and then the climb gets shaken up, by something that belongs to the
## part of the map the leader is in - that's most of what makes a biome feel
## like a place, not just a palette. Each biome draws from its own pool:
##   slab    a slab of concrete drops onto someone (marked where it'll land):
##           it shatters on whoever it hits, or floats where it stops as a
##           stepping stone you can break like any concrete
##   surge   the slag flares and surges up for a few seconds
##   wind    a gust pushes everyone (and the floating debris) sideways
##   quake   the ground shakes and nearby concrete cracks apart
## Each is called out a moment before it hits. The host (or an offline game)
## decides them: what they do to the world is physics, lava height, chunks or
## broken blocks, which already reach online guests. Guests are told each
## event too (Net._map_event), for the callout, the glow, and the wind on
## their own ball, which they simulate themselves. Off with Settings
## "map_events".
##
## Where things happen is worked out from the players, never the camera or
## the window: those depend on screen shape and frame timing, and a match has
## to replay the same anywhere.

const FIRST_AFTER := 25.0         ## s into the match
const GAP := Vector2(22.0, 38.0)  ## s between events
## A stretch where nobody breaks any concrete brings the next event
## forward (but never closer than MIN_GAP after the last one).
const QUIET := 12.0
const MIN_GAP := 14.0
const WARN := 1.2                 ## s of warning before it hits
const POOL := {
	"Rubble": ["slab"],
	"Inferno": ["surge", "slab", "quake"],
	"Void": ["wind", "quake", "slab"],
	"Storm": ["quake", "wind", "surge"],
}
const CALLOUT := {"slab": "Look up!", "surge": "The slag surges!", "wind": "Wind!", "quake": "Quake!"}

const SURGE_SPEED := 70.0         ## extra lava px/s
const SURGE_TIME := 3.5
const WIND_FORCE := 260.0         ## px/s² on loose chunks
const WIND_PUSH := 140.0          ## px/s of drift on players in the air (a third on the ground)
const WIND_TIME := 4.0
const QUAKE_BREAKS := 3
const SLAB_SIZE := Vector2(200, 60)
const SLAB_DROP := 480.0          ## px above its target it appears (about the top of the view)
const SLAB_SPEED := 720.0
const SLAB_SETTLE := 260.0        ## once it's slowed below this (px/s) it floats, a stepping stone
## Quakes crack concrete in this box around the leader (a 1280x720 view).
const QUAKE_AREA := Vector2(1280, 720)

var game: Node                     # game.gd
## Every event is this kind (designer runs: --event=quake).
var only := ""
## An online guest: told about events, doesn't decide them.
var remote := false
var _rng := RandomNumberGenerator.new()
var _next := FIRST_AFTER
var _kind := ""                    # event under way, "" when none
var _t := 0.0                      # time into it (negative while warning)
var _wind_dir := 1.0
var _target: Player
var _last := -INF                  # match time of the last event
var _quiet := 0.0                  # s since any concrete broke


func setup(g: Node, seed_value: int) -> void:
	game = g
	_rng.seed = seed_value + 9091
	SignalBus.block_broken.connect(_on_block_broken)


func _on_block_broken(_at: Vector2) -> void:
	_quiet = 0.0


## Called by the game every physics tick while the match is on.
func tick(delta: float, match_time: float) -> void:
	_quiet += delta
	if _kind != "":
		_run(delta)
		return
	if remote or not Settings.get_value("map_events"):
		return
	if _quiet >= QUIET:
		_next = minf(_next, maxf(_last + MIN_GAP, match_time))
	if match_time >= _next:
		start(only if only != "" else _kind_here())
		_last = match_time
		_quiet = 0.0
		_next = match_time + _rng.randf_range(GAP.x, GAP.y)


func _kind_here() -> String:
	var lead: Player = game.leader()
	var biome: Dictionary = game.map_gen.biome_at_y(lead.global_position.y if lead else 0.0)
	var pool: Array = POOL.get(biome.name, ["slab"])
	return pool[_rng.randi() % pool.size()]


## Starts an event (warning first). Tests and designers call it directly.
func start(kind: String) -> void:
	_kind = kind
	_t = -WARN
	var text: String = CALLOUT[kind]
	var color := Palette.RUST
	match kind:
		"slab":
			_target = _pick_target()
			if _target == null:
				_kind = ""
				return
			text = "%s, look up!" % _target.info.display_name if game.players.size() > 1 and _target.info else text
		"wind":
			_wind_dir = 1.0 if _rng.randf() < 0.5 else -1.0
			text += " >>" if _wind_dir > 0 else " <<"
			color = Palette.PAPER
		"quake":
			color = Palette.MUSTARD
	SignalBus.map_event_called.emit(text, color)
	if Net.is_server():
		Net.relay_map_event(kind, text, color, _wind_dir)
	var lead: Player = game.leader()
	Telemetry.world("map_event", lead.global_position if lead else Vector2.ZERO, {"kind": kind})
	Sfx.play("count")


## Online guest: the host started an event. Only what shows or moves our own
## ball runs here (the callout came with the message).
func start_remote(kind: String, wind_dir: float) -> void:
	remote = true
	_kind = kind
	_t = -WARN
	_wind_dir = wind_dir


func _run(delta: float) -> void:
	var was := _t
	_t += delta
	var hit := was < 0.0 and _t >= 0.0   # the moment it lands
	match _kind:
		"slab":
			if remote:
				if _t >= 0.0:
					_kind = ""
			elif _t < 0.0:
				_mark_slab()
			elif hit:
				_drop_slab()
				_kind = ""
		"surge":
			if hit:
				game.lava.surge = SURGE_SPEED   # (a guest's lava only glows: its height comes from the host)
				SignalBus.screen_shake_requested.emit(6.0)
			elif _t >= SURGE_TIME:
				game.lava.surge = 0.0
				_kind = ""
		"wind":
			Player.wind = _wind_dir * WIND_PUSH if _t >= 0.0 else 0.0
			if _t >= 0.0 and not remote:
				_blow(delta)
			if _t >= WIND_TIME:
				Player.wind = 0.0
				_kind = ""
		"quake":
			if _t < 0.0:
				SignalBus.screen_shake_requested.emit(3.0)
			elif hit:
				SignalBus.screen_shake_requested.emit(14.0)
				if not remote:
					_crack()
				_kind = ""


func stop() -> void:
	if game:
		game.lava.surge = 0.0
	Player.wind = 0.0
	_kind = ""


# ── Slab ─────────────────────────────────────

## Usually the leader (falling slabs keep the front honest), sometimes anyone.
func _pick_target() -> Player:
	var alive: Array = game.players.filter(func(p): return not p.is_dead)
	if alive.is_empty():
		return null
	if _rng.randf() < 0.6:
		return game.leader()
	return alive[_rng.randi() % alive.size()]


## Where it'll come down: a ring over the player, and a mark on whatever
## they'd land on below.
func _mark_slab() -> void:
	if not is_instance_valid(_target) or _target.is_dead:
		return
	if int(-_t * 60.0) % 12 == 0:
		Fx.ring(_target.global_position + Vector2(0, -40), Palette.RUST, 34.0, 4.0, 0.25)
		var ground := _ground_below(_target.global_position)
		if ground != Vector2.INF:
			Fx.ring(ground, Palette.RUST, SLAB_SIZE.x * 0.5, 5.0, 0.3)


## The top of the first solid block under `p` (or INF).
func _ground_below(p: Vector2) -> Vector2:
	var best := INF
	for b: Block in get_tree().get_nodes_in_group("blocks"):
		var r := b.get_rect_global()
		if b.collision_layer != 0 and p.x >= r.position.x and p.x <= r.end.x and r.position.y >= p.y and r.position.y < best:
			best = r.position.y
	return Vector2(p.x, best) if best != INF else Vector2.INF


func _drop_slab() -> void:
	if not is_instance_valid(_target):
		return
	var x := _target.global_position.x + _target.velocity.x * 0.25   # a little ahead of where they're going
	var y := _target.global_position.y - SLAB_DROP
	var r := Rect2(-SLAB_SIZE * 0.5, SLAB_SIZE)
	var poly := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	var cols: Array = Palette.BLOCKS["breakable_block"]
	var f := Fragment.new()
	f.setup(poly, cols[0], cols[1])
	f.linear_damp = 0.1               # it's falling, not floating...
	f.settle_speed = SLAB_SETTLE      # ...until it's hit something: then it floats there
	f.concrete = true                 # and breaks like concrete
	# It drops through platforms above its target, so it actually arrives -
	# then hits them, or smashes what they're standing on.
	var below := _target.global_position.y - 30.0
	for b: Block in get_tree().get_nodes_in_group("blocks"):
		if b.global_position.y < below and absf(b.global_position.x - x) < b.size.x * 0.5 + SLAB_SIZE.x:
			f.add_collision_exception_with(b)
	game.map_gen.add_child(f)
	f.global_position = Vector2(x, y)
	f.linear_velocity = Vector2(0, SLAB_SPEED)
	f.angular_velocity = _rng.randf_range(-1.0, 1.0)
	Fx.speed_lines(Vector2(x, y + 80.0), Vector2.DOWN, Palette.RUST)


# ── Wind ─────────────────────────────────────

func _blow(delta: float) -> void:
	for f: Fragment in get_tree().get_nodes_in_group("fragments"):
		if f.held_by == null and not f.puppet:
			f.linear_velocity.x += _wind_dir * WIND_FORCE * delta
	# Speed lines are only a picture: the global random, on the event's own
	# clock, so they never shift what the next event will be.
	if int(_t * 60.0) % 12 == 0:
		var cam: Camera2D = game.camera
		var half: Vector2 = get_viewport().get_visible_rect().size / cam.zoom * 0.5
		var p := cam.get_screen_center_position() + Vector2(randf_range(-half.x, half.x), randf_range(-half.y, half.y) * 0.8)
		Fx.speed_lines(p, Vector2(_wind_dir, 0), Palette.PAPER_DIM)


# ── Quake ────────────────────────────────────

## Cracks a few concrete blocks around the leader, never one somebody is standing on
## (that would be a coin-flip death, not a scramble).
func _crack() -> void:
	var under := {}
	for p: Player in game.players:
		for b in p._floor_blocks:
			under[b] = true
	var lead: Player = game.leader()
	if lead == null:
		return
	var view := Rect2(lead.global_position - QUAKE_AREA * 0.5, QUAKE_AREA)
	var candidates: Array = get_tree().get_nodes_in_group("blocks").filter(func(b):
		return b is BreakableBlock and not under.has(b) and view.has_point(b.global_position))
	for i in mini(QUAKE_BREAKS, candidates.size()):
		var b: BreakableBlock = candidates.pop_at(_rng.randi() % candidates.size())
		b.break_apart(b.global_position + Vector2(0, 30), 160.0, "quake")
