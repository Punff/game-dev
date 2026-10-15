class_name BreakableBlock
extends Block

## Cracked concrete. Shatters into big floating chunks when you jump off it,
## ground-pound it (fast-fall onto it), blast it with a shockwave, or hit it
## with a flying chunk - so one break can set off a whole chain.

const BREAK_DELAY := 0.08
const POUND_SPEED := 800.0      ## landing speed that smashes it
const CHUNK_SIZE := 70.0

var _broken := false

# Chain detection shared by all breakable blocks.
static var _recent_breaks: Array[int] = []


func _init() -> void:
	super._init()
	block_id = "breakable_block"
	toughness = 0.6


func on_player_jump(player: Player, _strength: float) -> void:
	# Small delay so the jump itself still pushes off solid ground.
	get_tree().create_timer(BREAK_DELAY).timeout.connect(break_apart.bind(player.global_position, 220.0))


func on_player_land(player: Player) -> void:
	if player.last_impact >= POUND_SPEED:
		break_apart(player.global_position, 380.0)
		SignalBus.screen_shake_requested.emit(10.0)


func on_shockwave(_dir: Vector2, origin: Vector2) -> void:
	break_apart(origin, 520.0)


func break_apart(origin: Vector2, force := 260.0) -> void:
	if _broken or not is_inside_tree():
		return
	_broken = true
	SignalBus.block_broken.emit(global_position)
	Sfx.play("break", -1.0, randf_range(0.85, 1.1))
	Fx.burst(global_position, Palette.PAPER_DIM, 10, 260.0, 0.5)
	_track_chain(global_position)

	shatter(origin, force, 0.0, CHUNK_SIZE)


static func _track_chain(pos: Vector2) -> void:
	var now := Time.get_ticks_msec()
	_recent_breaks.append(now)
	while not _recent_breaks.is_empty() and now - _recent_breaks[0] > 450:
		_recent_breaks.pop_front()
	if _recent_breaks.size() >= 3:
		SignalBus.chain_reaction_occurred.emit(_recent_breaks.size(), pos)


func _draw_icon() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed + 7
	var col := Color(Palette.INK, 0.85)
	var hh := size.y * 0.5 - OUTLINE
	for p in _icon_positions(110.0):
		var x := p.x + rng.randf_range(-15, 15)
		var crack := PackedVector2Array([Vector2(x, -hh)])
		var y := -hh
		while y < hh:
			y = minf(y + rng.randf_range(10, 18), hh)
			x += rng.randf_range(-12, 12)
			crack.append(Vector2(x, y))
		draw_polyline(crack, col, 2.5)
		# a branch
		var k := crack.size() / 2
		draw_line(crack[k], crack[k] + Vector2(rng.randf_range(-22, 22), rng.randf_range(6, 14)), col, 2.0)
	# rebar stubs poking from the ends
	for side in [-1.0, 1.0]:
		draw_line(Vector2(side * size.x * 0.5, -6), Vector2(side * (size.x * 0.5 + 9), -10), Color("6d4a2e"), 3.0)
