class_name BreakableBlock
extends Block

## Shatters when you jump off it or hit it with a shockwave. The pieces float
## in place as debris you can stand on or herd with a gravity field.

const BREAK_DELAY := 0.08

var _broken := false

# Chain detection shared by all breakable blocks.
static var _recent_breaks: Array[int] = []


func _init() -> void:
	super._init()
	block_id = "breakable_block"


func on_player_jump(_player: Player, _strength: float) -> void:
	# Small delay so the jump itself still pushes off solid ground.
	get_tree().create_timer(BREAK_DELAY).timeout.connect(break_apart.bind(global_position + Vector2(0, -20)))


func on_shockwave(_dir: Vector2, origin: Vector2) -> void:
	break_apart(origin)


func break_apart(origin: Vector2) -> void:
	if _broken or not is_inside_tree():
		return
	_broken = true
	collision_layer = 0
	visible = false
	SignalBus.block_broken.emit(global_position)
	Sfx.play("break", -2.0)
	_track_chain()

	var parent := get_parent()
	var live := get_tree().get_nodes_in_group("fragments").size()
	var pieces := 5 if live < 60 else 3
	var w := size.x / pieces
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	# Slice the block into vertical-ish shards with jagged edges.
	var cuts: Array[float] = [-size.x * 0.5]
	for i in range(1, pieces):
		cuts.append(-size.x * 0.5 + w * i + rng.randf_range(-w * 0.25, w * 0.25))
	cuts.append(size.x * 0.5)
	var hh := size.y * 0.5
	for i in pieces:
		var x0 := cuts[i]
		var x1 := cuts[i + 1]
		var jag0 := rng.randf_range(-8, 8) if i > 0 else 0.0
		var jag1 := rng.randf_range(-8, 8) if i < pieces - 1 else 0.0
		var cx := (x0 + x1) * 0.5
		var poly := PackedVector2Array([
			Vector2(x0 - cx, -hh), Vector2(x1 - cx, -hh),
			Vector2(x1 - cx + jag1, hh), Vector2(x0 - cx + jag0, hh),
		])
		var f := Fragment.new()
		f.setup(poly, colors()[0], colors()[1])
		parent.add_child(f)
		f.global_position = global_position + Vector2(cx, 0)
		var away := (f.global_position - origin).normalized()
		f.linear_velocity = Vector2(away.x * rng.randf_range(40, 110), rng.randf_range(-120, -40))
		f.angular_velocity = rng.randf_range(-3, 3)
	queue_free()


static func _track_chain() -> void:
	var now := Time.get_ticks_msec()
	_recent_breaks.append(now)
	while not _recent_breaks.is_empty() and now - _recent_breaks[0] > 350:
		_recent_breaks.pop_front()
	if _recent_breaks.size() >= 3:
		SignalBus.chain_reaction_occurred.emit(_recent_breaks.size(), Vector2.ZERO)


func _draw_icon() -> void:
	var col := Color(colors()[0].darkened(0.5), 0.9)
	for p in _icon_positions(80.0):
		draw_polyline(PackedVector2Array([p + Vector2(-14, -12), p + Vector2(-4, -2), p + Vector2(-9, 6), p + Vector2(3, 12)]), col, 2.5, true)
		draw_line(p + Vector2(-4, -2), p + Vector2(10, -6), col, 2.5, true)
