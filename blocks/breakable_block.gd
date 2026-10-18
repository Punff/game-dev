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
	collision_layer = 0
	visible = false
	SignalBus.block_broken.emit(global_position)
	Sfx.play("break", -1.0, randf_range(0.85, 1.1))
	Fx.burst(global_position, Palette.PAPER_DIM, 10, 260.0, 0.5)
	_track_chain(global_position)

	var parent := get_parent()
	var live := get_tree().get_nodes_in_group("fragments").size()
	var cols := maxi(2, roundi(size.x / CHUNK_SIZE))
	var rows := 1 if size.y < 90.0 else 2
	if live > 110:
		cols = maxi(2, cols / 2)
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var cw := size.x / cols
	var rh := size.y / rows
	# Jittered grid of cut points shared between neighbouring chunks.
	var pts := []
	for j in rows + 1:
		var row := []
		for i in cols + 1:
			var p := Vector2(-size.x * 0.5 + cw * i, -size.y * 0.5 + rh * j)
			if i > 0 and i < cols:
				p.x += rng.randf_range(-cw, cw) * 0.3
			if j > 0 and j < rows:
				p.y += rng.randf_range(-rh, rh) * 0.25
			row.append(p)
		pts.append(row)
	for j in rows:
		for i in cols:
			var a: Vector2 = pts[j][i]
			var b: Vector2 = pts[j][i + 1]
			var c: Vector2 = pts[j + 1][i + 1]
			var d: Vector2 = pts[j + 1][i]
			var center := (a + b + c + d) * 0.25
			var poly := PackedVector2Array([a - center, b - center, c - center, d - center])
			var f := Fragment.new()
			f.setup(poly, colors()[0], colors()[1])
			parent.add_child(f)
			f.global_position = global_position + center
			var away := (f.global_position - origin).normalized()
			f.linear_velocity = away * force * rng.randf_range(0.5, 1.0) + Vector2(0, rng.randf_range(-90, -20))
			f.angular_velocity = rng.randf_range(-4, 4)
	queue_free()


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
