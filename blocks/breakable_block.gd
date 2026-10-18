class_name BreakableBlock
extends Block

## A wall of concrete bricks laid in a running bond. Bricks come loose one at
## a time: jumping off kicks out the ones under your feet, a ground pound
## punches a hole, a shockwave bites a cone out of the wall, flying debris
## knocks out what it hits and a gravity field pries bricks free. Every loose
## brick becomes floating debris, so one hit can still set off a chain.

const COURSE_H := 30.0
const BRICK_W := 62.0
const BREAK_DELAY := 0.08
const POUND_SPEED := 800.0      ## landing speed that smashes it
const POUND_RADIUS := 42.0
const SHOCK_BITE := 300.0       ## bricks this close inside the shockwave cone come loose
const HIT_RADIUS := 30.0        ## flying debris knocks out bricks this close to it
const PRY_TIME := 0.22          ## a gravity field pulls one brick free this often
const PRY_MAX_HELD := 6
const MAX_FRAGMENTS := 140      ## past this, loose bricks just turn to dust

class Brick:
	var rect: Rect2              ## local to the block
	var cs: CollisionShape2D
	var outline: PackedVector2Array
	var tint: Color
	var alive := true

var _bricks: Array[Brick] = []
var _alive := 0
var _breaks := 0                ## seeds the debris scatter so it's the same on every machine
var _pry := {}                  ## player_id -> [seconds of field contact, last physics frame]

# Chain detection shared by all breakable blocks.
static var _recent_breaks: Array[int] = []


func _init() -> void:
	super._init()
	block_id = "breakable_block"
	_cs.disabled = true          # every brick has its own shape


func _ready() -> void:
	super._ready()
	_build_bricks()


func set_block_size(new_size: Vector2) -> void:
	super.set_block_size(new_size)
	if is_inside_tree():
		_build_bricks()


func _build_bricks() -> void:
	for b in _bricks:
		b.cs.queue_free()
	_bricks.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed + 11
	var face: Color = colors()[0]
	var courses := maxi(1, ceili(size.y / COURSE_H - 0.05))
	var ch := size.y / courses
	var right := size.x * 0.5
	for j in courses:
		var x := -size.x * 0.5
		var w := BRICK_W * rng.randf_range(0.8, 1.2) * (0.5 if j % 2 == 1 else 1.0)
		while x < right - 0.5:
			if right - (x + w) < BRICK_W * 0.4:
				w = right - x
			var b := Brick.new()
			b.rect = Rect2(x, -size.y * 0.5 + ch * j, w, ch)
			b.tint = face.darkened(rng.randf_range(0.0, 0.14)) if rng.randf() < 0.7 else face.lightened(rng.randf_range(0.0, 0.08))
			b.outline = rough_rect(b.rect.grow(-1.0), _seed + _bricks.size() * 31, 1.1)
			var shape := RectangleShape2D.new()
			shape.size = b.rect.size
			b.cs = CollisionShape2D.new()
			b.cs.shape = shape
			b.cs.position = b.rect.get_center()
			add_child(b.cs)
			_bricks.append(b)
			x += w
			w = BRICK_W * rng.randf_range(0.8, 1.2)
	_alive = _bricks.size()
	queue_redraw()


# ── Hits ─────────────────────────────────────

func on_player_jump(player: Player, _strength: float) -> void:
	# Kick out the bricks under your feet - after a beat, so the jump itself
	# still pushes off solid ground.
	var under := _bricks_under(to_local(player.global_position))
	if under.is_empty():
		return
	get_tree().create_timer(BREAK_DELAY).timeout.connect(_knock_out.bind(under, player.global_position, 220.0))


func on_player_land(player: Player) -> void:
	if player.last_impact < POUND_SPEED:
		return
	var foot := to_local(player.global_position) + Vector2(0, Player.RADIUS)
	var hit: Array[Brick] = []
	for b in _bricks:
		if b.alive and _rect_dist(b.rect, foot) < POUND_RADIUS:
			hit.append(b)
	_knock_out(hit, player.global_position, 380.0)
	SignalBus.screen_shake_requested.emit(10.0)


func on_shockwave(dir: Vector2, origin: Vector2) -> void:
	var o := to_local(origin)
	var hit: Array[Brick] = []
	for b in _bricks:
		if not b.alive:
			continue
		var to := _closest(b.rect, o) - o
		if to.length() < SHOCK_BITE and (to.length() < 1.0 or to.normalized().dot(dir) >= 0.4):
			hit.append(b)
	_knock_out(hit, origin, 520.0)


## A fast chunk of debris struck the wall.
func hit_by_debris(pos: Vector2, velocity: Vector2) -> void:
	var p := to_local(pos)
	var hit: Array[Brick] = []
	var nearest: Brick = null
	var nearest_d := INF
	for b in _bricks:
		if not b.alive:
			continue
		var d := _rect_dist(b.rect, p)
		if d < HIT_RADIUS:
			hit.append(b)
		if d < nearest_d:
			nearest_d = d
			nearest = b
	if hit.is_empty() and nearest:
		hit.append(nearest)
	# Bricks fly on in the direction of the hit.
	_knock_out(hit, pos - velocity.normalized() * 60.0, velocity.length() * 0.6)


func on_gravity_field(player: Player, delta: float) -> void:
	if player.held_count() >= PRY_MAX_HELD:
		return
	var frame := Engine.get_physics_frames()
	var st: Array = _pry.get(player.player_id, [0.0, frame])
	var t: float = st[0] + delta if frame - int(st[1]) <= 1 else delta
	if t < PRY_TIME:
		_pry[player.player_id] = [t, frame]
		return
	_pry[player.player_id] = [0.0, frame]
	# Pull out the nearest brick - never the ones you're standing on.
	var p := to_local(player.global_position)
	var standing := _bricks_under(p)
	var best: Brick = null
	var best_d := Player.GRAVITY_RADIUS * 0.85
	for b in _bricks:
		if not b.alive or b in standing:
			continue
		var d := _rect_dist(b.rect, p)
		if d < best_d:
			best_d = d
			best = b
	if best:
		var c := to_global(best.rect.get_center())
		_knock_out([best], c * 2.0 - player.global_position, 160.0)   # drifts towards the player


## Breaks every brick at once (dev tools / scripted demolition).
func break_apart(origin: Vector2, force := 260.0) -> void:
	var all: Array[Brick] = []
	for b in _bricks:
		if b.alive:
			all.append(b)
	_knock_out(all, origin, force)


func _knock_out(hit: Array, origin: Vector2, force: float) -> void:
	var live := hit.filter(func(b): return b.alive)
	if live.is_empty() or not is_inside_tree():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed + _breaks * 7919
	_breaks += 1
	var parent := get_parent()
	var spare := MAX_FRAGMENTS - get_tree().get_nodes_in_group("fragments").size()
	var mid := Vector2.ZERO
	for b: Brick in live:
		b.alive = false
		b.cs.disabled = true
		_alive -= 1
		var pos := to_global(b.rect.get_center())
		mid += pos
		if spare <= 0:
			Fx.dust(pos, Palette.PAPER_DIM, 4)
			continue
		spare -= 1
		var f := Fragment.new()
		var hs := b.rect.size * 0.5 - Vector2(1, 1)
		f.setup(PackedVector2Array([-hs, Vector2(hs.x, -hs.y), hs, Vector2(-hs.x, hs.y)]), b.tint, colors()[1])
		f.brick_outline = rough_rect(Rect2(-hs, hs * 2.0), _seed + _breaks * 13 + spare, 1.1)
		parent.add_child(f)
		f.global_position = pos
		var away := (pos - origin).normalized()
		f.linear_velocity = away * force * rng.randf_range(0.6, 1.0) + Vector2(0, rng.randf_range(-70, -10))
		f.angular_velocity = rng.randf_range(-3, 3)
	mid /= live.size()
	SignalBus.block_broken.emit(mid)
	Sfx.play("break", -1.0, rng.randf_range(0.85, 1.1))
	Fx.burst(mid, Palette.PAPER_DIM, mini(4 + live.size() * 2, 14), 240.0, 0.45)
	_track_chain(mid)
	if _alive <= 0:
		queue_free()
	else:
		queue_redraw()


## Bricks whose top the player is standing on.
func _bricks_under(p: Vector2) -> Array[Brick]:
	var out: Array[Brick] = []
	var foot := p.y + Player.RADIUS
	for b in _bricks:
		if b.alive and absf(b.rect.position.y - foot) < 8.0 \
				and p.x > b.rect.position.x - Player.RADIUS * 0.8 and p.x < b.rect.end.x + Player.RADIUS * 0.8:
			out.append(b)
	return out


static func _closest(r: Rect2, p: Vector2) -> Vector2:
	return Vector2(clampf(p.x, r.position.x, r.end.x), clampf(p.y, r.position.y, r.end.y))


static func _rect_dist(r: Rect2, p: Vector2) -> float:
	return _closest(r, p).distance_to(p)


static func _track_chain(pos: Vector2) -> void:
	var now := Time.get_ticks_msec()
	_recent_breaks.append(now)
	while not _recent_breaks.is_empty() and now - _recent_breaks[0] > 450:
		_recent_breaks.pop_front()
	if _recent_breaks.size() >= 3:
		SignalBus.chain_reaction_occurred.emit(_recent_breaks.size(), pos)


# ── Drawing ──────────────────────────────────

func _draw() -> void:
	# All shadows first so they merge into one smudge behind the wall.
	for b in _bricks:
		if b.alive:
			draw_colored_polygon(_shifted(b.outline, SHADOW), Color(Palette.INK, 0.45))
	for b in _bricks:
		if b.alive:
			draw_brick(self, b.rect, b.outline, b.tint)


## One hatched concrete brick (shared with the debris it turns into).
static func draw_brick(ci: CanvasItem, r: Rect2, outline: PackedVector2Array, fill: Color) -> void:
	ci.draw_colored_polygon(_shifted(outline, MISREG), fill)
	# Fine diamond hatch, like a screen-printed texture.
	var face := r.grow(-4.0)
	var ink := Color(fill.darkened(0.5), 0.22)
	const STEP := 7.0
	var c := face.position.x - face.end.y
	while c < face.end.x - face.position.y:
		var xa := maxf(face.position.x, face.position.y + c)
		var xb := minf(face.end.x, face.end.y + c)
		if xb > xa:
			ci.draw_line(Vector2(xa, xa - c), Vector2(xb, xb - c), ink, 1.0)
		c += STEP
	c = face.position.x + face.position.y
	while c < face.end.x + face.end.y:
		var xa := maxf(face.position.x, c - face.end.y)
		var xb := minf(face.end.x, c - face.position.y)
		if xb > xa:
			ci.draw_line(Vector2(xa, c - xa), Vector2(xb, c - xb), ink, 1.0)
		c += STEP
	ci.draw_line(r.position + Vector2(4, 4), Vector2(r.end.x - 4, r.position.y + 4), fill.lightened(0.25), 2.0)
	ci.draw_line(Vector2(r.position.x + 4, r.end.y - 3), r.end - Vector2(4, 3), fill.darkened(0.3), 2.0)
	ci.draw_polyline(outline, Palette.INK, 2.5)
