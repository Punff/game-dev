class_name MapEvents
extends Node

## Now and then the climb gets shaken up, by something that belongs to the
## part of the map the leader is in - that's most of what makes a biome
## feel like a place, not just a palette:
##   Rubble   slab    a slab of concrete drops from above onto someone
##   Inferno  surge   the slag surges up for a few seconds
##   Void     wind    a gust drifts the floating debris sideways
##   Storm    quake   the ground shakes and nearby concrete cracks apart
## Each is called out a moment before it hits. Host (or offline) only:
## everything an event does is physics, lava height, chunks or broken
## blocks, which already reach online guests (its callouts are Fx, which are
## relayed too). Off with Settings "map_events".

const FIRST_AFTER := 25.0         ## s into the match
const GAP := Vector2(22.0, 38.0)  ## s between events
const WARN := 1.2                 ## s of warning before it hits
const BY_BIOME := {"Rubble": "slab", "Inferno": "surge", "Void": "wind", "Storm": "quake"}
const CALLOUT := {"slab": "Look up!", "surge": "The slag surges!", "wind": "Wind!", "quake": "Quake!"}

const SURGE_SPEED := 70.0         ## extra lava px/s
const SURGE_TIME := 3.5
const WIND_FORCE := 260.0         ## px/s² on loose chunks
const WIND_TIME := 4.0
const QUAKE_BREAKS := 3
const SLAB_SIZE := Vector2(150, 56)
const SLAB_SPEED := 950.0

var game: Node                     # game.gd
## Every event is this kind (designer runs: --event=quake).
var only := ""
var _rng := RandomNumberGenerator.new()
var _next := FIRST_AFTER
var _kind := ""                    # event under way, "" when none
var _t := 0.0                      # time into it (negative while warning)
var _wind_dir := 1.0
var _target: Player


func setup(g: Node, seed_value: int) -> void:
	game = g
	_rng.seed = seed_value + 9091


## Called by the game every physics tick while the match is on.
func tick(delta: float, match_time: float) -> void:
	if _kind != "":
		_run(delta)
	elif match_time >= _next and Settings.get_value("map_events"):
		start(only if only != "" else _kind_here())
		_next = match_time + _rng.randf_range(GAP.x, GAP.y)


func _kind_here() -> String:
	var lead: Player = game.leader()
	var biome: Dictionary = game.map_gen.biome_at_y(lead.global_position.y if lead else 0.0)
	return BY_BIOME.get(biome.name, "slab")


## Starts an event (warning first). Tests and designers call it directly.
func start(kind: String) -> void:
	_kind = kind
	_t = -WARN
	var cam: Camera2D = game.camera
	var top := cam.get_screen_center_position() - Vector2(0, get_viewport().get_visible_rect().size.y / cam.zoom.y * 0.5)
	match kind:
		"slab":
			_target = _pick_target()
			if _target == null:
				_kind = ""
				return
			Fx.popup(Vector2(_target.global_position.x, top.y + 90.0), CALLOUT[kind], Palette.RUST, 34)
		"wind":
			_wind_dir = 1.0 if _rng.randf() < 0.5 else -1.0
			Fx.popup(top + Vector2(0, 110), CALLOUT[kind] + (" >>" if _wind_dir > 0 else " <<"), Palette.PAPER, 34)
		_:
			Fx.popup(top + Vector2(0, 110), CALLOUT[kind], Palette.MUSTARD if kind == "quake" else Palette.RUST, 36)
	Telemetry.world("map_event", top, {"kind": kind})
	Sfx.play("count")


func _run(delta: float) -> void:
	var was := _t
	_t += delta
	var hit := was < 0.0 and _t >= 0.0   # the moment it lands
	match _kind:
		"slab":
			if _t < 0.0:
				_mark_slab()
			elif hit:
				_drop_slab()
				_kind = ""
		"surge":
			if hit:
				game.lava.surge = SURGE_SPEED
				SignalBus.screen_shake_requested.emit(6.0)
			elif _t >= SURGE_TIME:
				game.lava.surge = 0.0
				_kind = ""
		"wind":
			if _t >= 0.0:
				_blow(delta)
			if _t >= WIND_TIME:
				_kind = ""
		"quake":
			if _t < 0.0:
				SignalBus.screen_shake_requested.emit(3.0)
			elif hit:
				SignalBus.screen_shake_requested.emit(14.0)
				_crack()
				_kind = ""


func stop() -> void:
	if _kind == "surge" and game:
		game.lava.surge = 0.0
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


## A target ring over the player while it's coming.
func _mark_slab() -> void:
	if not is_instance_valid(_target) or _target.is_dead:
		return
	if Engine.get_physics_frames() % 12 == 0:
		Fx.ring(_target.global_position + Vector2(0, -40), Palette.RUST, 34.0, 4.0, 0.25)


func _drop_slab() -> void:
	if not is_instance_valid(_target):
		return
	var cam: Camera2D = game.camera
	var view_h: float = get_viewport().get_visible_rect().size.y / cam.zoom.y
	var x := _target.global_position.x + _target.velocity.x * 0.25   # a little ahead of where they're going
	var y := cam.get_screen_center_position().y - view_h * 0.5 - SLAB_SIZE.y
	var r := Rect2(-SLAB_SIZE * 0.5, SLAB_SIZE)
	var poly := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	var cols: Array = Palette.BLOCKS["breakable_block"]
	var f := Fragment.new()
	f.setup(poly, cols[0], cols[1])
	f.linear_damp = 0.1   # it's falling, not floating
	# It drops through platforms above its target, so it actually arrives -
	# then hits them, or smashes what they're standing on.
	var below := _target.global_position.y - 30.0
	for b: Block in get_tree().get_nodes_in_group("blocks"):
		if b.global_position.y < below and absf(b.global_position.x - x) < b.size.x * 0.5 + SLAB_SIZE.x:
			f.add_collision_exception_with(b)
	game.map_gen.add_child(f)
	f.global_position = Vector2(x, y)
	f.linear_velocity = Vector2(0, SLAB_SPEED)
	f.angular_velocity = _rng.randf_range(-1.5, 1.5)
	Fx.speed_lines(Vector2(x, y + 80.0), Vector2.DOWN, Palette.RUST)


# ── Wind ─────────────────────────────────────

func _blow(delta: float) -> void:
	for f: Fragment in get_tree().get_nodes_in_group("fragments"):
		if f.held_by == null and not f.puppet:
			f.linear_velocity.x += _wind_dir * WIND_FORCE * delta
	if Engine.get_physics_frames() % 20 == 0:
		var cam: Camera2D = game.camera
		var half: Vector2 = get_viewport().get_visible_rect().size / cam.zoom * 0.5
		var p := cam.get_screen_center_position() + Vector2(_rng.randf_range(-half.x, half.x), _rng.randf_range(-half.y, half.y) * 0.8)
		Fx.speed_lines(p, Vector2(_wind_dir, 0), Palette.PAPER_DIM)


# ── Quake ────────────────────────────────────

## Cracks a few concrete blocks on screen, never one somebody is standing on
## (that would be a coin-flip death, not a scramble).
func _crack() -> void:
	var under := {}
	for p: Player in game.players:
		for b in p._floor_blocks:
			under[b] = true
	var cam: Camera2D = game.camera
	var view := Rect2(cam.get_screen_center_position() - get_viewport().get_visible_rect().size / cam.zoom * 0.5,
		get_viewport().get_visible_rect().size / cam.zoom)
	var candidates: Array = get_tree().get_nodes_in_group("blocks").filter(func(b):
		return b is BreakableBlock and not under.has(b) and view.has_point(b.global_position))
	for i in mini(QUAKE_BREAKS, candidates.size()):
		var b: BreakableBlock = candidates.pop_at(_rng.randi() % candidates.size())
		b.break_apart(b.global_position + Vector2(0, 30), 160.0, "quake")
