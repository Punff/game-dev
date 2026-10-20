class_name BreakableBlock
extends Block

## Cracked concrete. Shatters into big floating chunks when you jump off it,
## ground-pound it (fast-fall onto it), blast it with a shockwave, or hit it
## with a flying chunk - so one break can set off a whole chain. The cracks
## you see are where it will split: uneven shards, cut at random.

const BREAK_DELAY := 0.08
const POUND_SPEED := 800.0      ## landing speed that smashes it
const CHUNK_AREA := 3600.0       ## roughly one shard per this many px²

var _shards: Array[PackedVector2Array] = []

var _broken := false

# Chain detection shared by all breakable blocks.
static var _recent_breaks: Array[int] = []


func _init() -> void:
	super._init()
	block_id = "breakable_block"


func _ready() -> void:
	super._ready()
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed + 7
	var count := maxi(3, roundi(size.x * size.y / CHUNK_AREA))
	_shards = shatter(Rect2(-size * 0.5, size), count, rng)


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
	net_changed()

	var parent := get_parent()
	var shards := _shards
	if get_tree().get_nodes_in_group("fragments").size() > 110:
		shards = shatter(Rect2(-size * 0.5, size), maxi(2, shards.size() / 2), RandomNumberGenerator.new())
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for poly in shards:
		var center := Vector2.ZERO
		for v in poly:
			center += v
		center /= poly.size()
		var local := poly.duplicate()
		for i in local.size():
			local[i] -= center
		var f := Fragment.new()
		f.setup(local, colors()[0], colors()[1])
		parent.add_child(f)
		f.global_position = global_position + center
		var away := (f.global_position - origin).normalized()
		f.linear_velocity = away * force * rng.randf_range(0.5, 1.0) + Vector2(0, rng.randf_range(-90, -20))
		f.angular_velocity = rng.randf_range(-4, 4)
	queue_free()


func net_state() -> int:
	return 1 if _broken else 0


func apply_net_state(state: int) -> void:
	if state == 1 and not _broken:
		_broken = true
		collision_layer = 0
		visible = false
		queue_free()   # the server sends the chunks


static func _track_chain(pos: Vector2) -> void:
	var now := Time.get_ticks_msec()
	_recent_breaks.append(now)
	while not _recent_breaks.is_empty() and now - _recent_breaks[0] > 450:
		_recent_breaks.pop_front()
	if _recent_breaks.size() >= 3:
		SignalBus.chain_reaction_occurred.emit(_recent_breaks.size(), pos)


## Splits `rect` into `count` uneven shards by repeatedly cutting the biggest
## piece along a random, tilted, kinked line near its middle.
static func shatter(rect: Rect2, count: int, rng: RandomNumberGenerator) -> Array[PackedVector2Array]:
	var pieces: Array[PackedVector2Array] = [PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)])]
	var min_area := rect.get_area() / count * 0.3
	var tries := 0
	while pieces.size() < count and tries < count * 8:
		tries += 1
		var bi := 0
		for i in pieces.size():
			if _area(pieces[i]) > _area(pieces[bi]):
				bi = i
		var poly := pieces[bi]
		var lo := poly[0]
		var hi := poly[0]
		var c := Vector2.ZERO
		for v in poly:
			lo = lo.min(v)
			hi = hi.max(v)
			c += v
		c = c / poly.size() + (hi - lo) * Vector2(rng.randf_range(-0.2, 0.2), rng.randf_range(-0.2, 0.2))
		# Cut across the piece's long side (now and then any which way), tilted
		# and kinked so shards come out as jagged wedges, not slices.
		var along := PI * 0.5 if hi.x - lo.x > hi.y - lo.y else 0.0
		if rng.randf() < 0.25:
			along = rng.randf() * PI
		var d := Vector2.from_angle(along + rng.randf_range(-0.9, 0.9))
		var n := d.orthogonal()
		var span := (hi - lo).length() * 0.5
		var cut := PackedVector2Array([c + d * 4000.0])
		for t in [0.45, -0.1, -0.5]:
			if t != -0.1 or rng.randf() < 0.6:
				cut.append(c + d * span * t + n * span * rng.randf_range(-0.22, 0.22))
		cut.append(c - d * 4000.0)
		var side_a := cut.duplicate()
		side_a.append(c - d * 4000.0 + n * 4000.0)
		side_a.append(c + d * 4000.0 + n * 4000.0)
		var side_b := cut.duplicate()
		side_b.append(c - d * 4000.0 - n * 4000.0)
		side_b.append(c + d * 4000.0 - n * 4000.0)
		var a := Geometry2D.intersect_polygons(poly, side_a)
		var b := Geometry2D.intersect_polygons(poly, side_b)
		if a.size() != 1 or b.size() != 1 or _area(a[0]) < min_area or _area(b[0]) < min_area:
			continue
		pieces.remove_at(bi)
		pieces.append(a[0])
		pieces.append(b[0])
	return pieces


static func _area(poly: PackedVector2Array) -> float:
	var s := 0.0
	for i in poly.size():
		s += poly[i].cross(poly[(i + 1) % poly.size()])
	return absf(s) * 0.5


func _draw_icon() -> void:
	# The cracks are the seams it will actually split along.
	var col := Color(Palette.INK, 0.8)
	var half := size * 0.5 - Vector2(OUTLINE, OUTLINE) * 0.5
	for poly in _shards:
		for i in poly.size():
			var a := poly[i]
			var b := poly[(i + 1) % poly.size()]
			if _on_edge(a, half) and _on_edge(b, half) and (is_equal_approx(a.x, b.x) or is_equal_approx(a.y, b.y)):
				continue   # part of the block's own outline
			draw_polyline(rough_line(a.clamp(-half, half), b.clamp(-half, half), _seed + i, 1.2), col, 2.5)
	# rebar stubs poking from the ends
	for side in [-1.0, 1.0]:
		draw_line(Vector2(side * size.x * 0.5, -6), Vector2(side * (size.x * 0.5 + 9), -10), Color("6d4a2e"), 3.0)


static func _on_edge(p: Vector2, half: Vector2) -> bool:
	return absf(absf(p.x) - half.x) < 3.0 or absf(absf(p.y) - half.y) < 3.0
