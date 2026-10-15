class_name Block
extends AnimatableBody2D

## Base class for every platform. Blocks build their own collision shape and
## draw themselves in a flat ink style (no textures, no shaders), so they are
## cheap to spawn in bulk and look crisp at any zoom.
##
## Every block wears down as players land, stand and jump on it, cracks, and
## finally crumbles away: the tower falls apart behind whoever climbs first.

const HEIGHT := 60.0
const OUTLINE := 4.0
const SHADOW := Vector2(8, 8)

# Wear, in "fractions of a block's life" (scaled by toughness).
const WEAR_LAND := 0.1
const WEAR_IMPACT := 0.15     ## extra on a hard landing (scaled by fall speed)
const WEAR_STAND := 0.08      ## per second, per player standing on it
const WEAR_JUMP := 0.07
const CRUMBLE_WARNING := 0.4  ## seconds of shaking before it goes

## 0 = indestructible. Higher lasts longer.
var toughness := 1.0
var wear := 0.0
var _crumbling := false

var block_id := "static_platform"
var size := Vector2(160.0, HEIGHT)
## Blocks that animate their icon redraw every frame; static ones draw once.
var animated := false

var _shape := RectangleShape2D.new()
var _seed := 0


func _init() -> void:
	collision_layer = 1
	collision_mask = 0
	var cs := CollisionShape2D.new()
	cs.shape = _shape
	add_child(cs)
	_shape.size = size


func _ready() -> void:
	add_to_group("blocks")
	_seed = hash(Vector2i(int(global_position.x), int(global_position.y)))
	set_process(animated)


func _process(_delta: float) -> void:
	queue_redraw()


func add_wear(amount: float) -> void:
	if toughness <= 0.0 or _crumbling or not is_inside_tree():
		return
	var stage := wear_stage()
	wear += amount / toughness
	if wear_stage() != stage:
		queue_redraw()
		Fx.burst(global_position + Vector2(randf_range(-size.x, size.x) * 0.4, -size.y * 0.5), colors()[0], 3, 90.0, 0.3)
	if wear >= 1.0:
		crumble()


func wear_stage() -> int:
	return clampi(int(wear * 4.0), 0, 3)


## Starts the short shake-then-collapse.
func crumble() -> void:
	if _crumbling:
		return
	_crumbling = true
	set_process(true)   # redraw every frame while it shakes
	Sfx.play("crack", -4.0)
	get_tree().create_timer(CRUMBLE_WARNING, false).timeout.connect(
		func(): shatter(global_position + Vector2(0, -size.y), 90.0, 0.35))


## Breaks into chunks. `gravity` > 0 makes the bits fall away (crumbling);
## 0 leaves floating debris (blasted concrete).
func shatter(origin: Vector2, force := 260.0, gravity := 0.0, chunk := 80.0) -> void:
	if not is_inside_tree() or is_queued_for_deletion():
		return
	collision_layer = 0
	visible = false
	Fx.poof(global_position, Palette.PAPER_DIM, 4)
	var parent := get_parent()
	var live := get_tree().get_nodes_in_group("fragments").size()
	var cols := maxi(2, roundi(size.x / chunk))
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
			f.gravity_scale = gravity
			parent.add_child(f)
			f.global_position = global_position + center
			var away := (f.global_position - origin).normalized()
			f.linear_velocity = away * force * rng.randf_range(0.5, 1.0) + Vector2(0, rng.randf_range(-90, -20))
			f.angular_velocity = rng.randf_range(-4, 4)
	queue_free()


func set_block_size(new_size: Vector2) -> void:
	size = new_size
	_shape.size = new_size
	queue_redraw()


func get_rect_global() -> Rect2:
	return Rect2(global_position - size * 0.5, size)


# ── Gameplay hooks (override as needed) ──────

## Player touched the top of this block this frame (wasn't standing on it last frame).
func on_player_land(_player: Player) -> void: pass
## Called every physics frame the player stands on top of this block.
func on_player_stand(_player: Player, _delta: float) -> void: pass
func on_player_leave(_player: Player) -> void: pass
## Player jumped while standing on this block.
func on_player_jump(_player: Player, _strength: float) -> void: pass
func on_shockwave(_dir: Vector2, _origin: Vector2) -> void: pass


# ── Drawing ──────────────────────────────────

func colors() -> Array:
	return Palette.BLOCKS.get(block_id, Palette.BLOCKS["static_platform"])


func _draw() -> void:
	if _crumbling:
		draw_set_transform(Vector2(randf_range(-3, 3), randf_range(-2, 2)))
	_draw_body()
	_draw_icon()
	_draw_wear()
	draw_set_transform(Vector2.ZERO)


## Cracks spreading across the face as the block wears out.
func _draw_wear() -> void:
	var stage := wear_stage()
	if stage == 0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed + 101
	var ink := Color(Palette.INK, 0.8)
	var hh := size.y * 0.5 - OUTLINE
	for k in stage * 2:
		var x := rng.randf_range(-size.x * 0.45, size.x * 0.45)
		var y := -hh if rng.randf() < 0.5 else hh
		var pts := PackedVector2Array([Vector2(x, y)])
		for i in 3 + stage:
			x += rng.randf_range(-14, 14)
			y += signf(-y) * rng.randf_range(6, 12) if absf(y) > 2.0 else rng.randf_range(-8, 8)
			pts.append(Vector2(x, clampf(y, -hh, hh)))
		draw_polyline(pts, ink, 1.5 + stage * 0.5)
	if stage >= 3:
		# missing corner chunk
		var cx := size.x * 0.5 - OUTLINE
		draw_colored_polygon(PackedVector2Array([Vector2(cx - 18, -hh), Vector2(cx, -hh), Vector2(cx, -hh + 14)]), Palette.INK)


func _draw_body() -> void:
	var c: Array = colors()
	var r := Rect2(-size * 0.5, size)
	# Hard ink shadow, ink outline, flat face.
	draw_rect(Rect2(r.position + SHADOW, r.size), Color(Palette.INK, 0.55))
	draw_rect(r, Palette.INK)
	var face := r.grow(-OUTLINE)
	draw_rect(face, c[0])
	# Light catching the top edge, darker underside.
	draw_rect(Rect2(face.position, Vector2(face.size.x, 4)), c[0].lightened(0.22))
	draw_rect(Rect2(face.position + Vector2(0, face.size.y - 6), Vector2(face.size.x, 6)), c[0].darkened(0.3))
	_draw_grit(face, c[0])


## Cross-hatching and chips so surfaces look used, not plastic.
func _draw_grit(face: Rect2, base: Color) -> void:
	var ink := Color(base.darkened(0.55), 0.55)
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed
	# A hatched corner
	var corner_right := rng.randf() < 0.5
	var hx := face.end.x if corner_right else face.position.x
	var dir := -1.0 if corner_right else 1.0
	for i in 4:
		var o := 7.0 + i * 7.0
		draw_line(Vector2(hx + dir * o, face.end.y - 6), Vector2(hx + dir * (o - 10.0), face.position.y + face.size.y * 0.45), ink, 1.5)
	# Chips / pits
	var chips := int(face.size.x / 70.0) + 1
	for i in chips:
		var p := Vector2(rng.randf_range(face.position.x + 10, face.end.x - 10), rng.randf_range(face.position.y + 10, face.end.y - 12))
		draw_rect(Rect2(p, Vector2(rng.randf_range(2, 5), 2)), ink)


## Repeats an icon along the block so long platforms stay readable.
func _icon_positions(spacing := 90.0) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var n := maxi(1, int(size.x / spacing))
	var step := size.x / n
	for i in n:
		out.append(Vector2(-size.x * 0.5 + step * (i + 0.5), -2.0))
	return out


func _icon_color(a := 1.0) -> Color:
	return Color(colors()[1], a)


## Polyline with an ink outline underneath: bold comic-style symbol strokes.
func _ink_line(pts: PackedVector2Array, col: Color, w := 5.0) -> void:
	draw_polyline(pts, Palette.INK, w + 4.0)
	draw_polyline(pts, col, w)


func _draw_icon() -> void:
	# Static platforms: riveted steel plates.
	var col := Color(colors()[1], 0.9)
	var hx := size.x * 0.5 - 16.0
	var x := -hx
	while x <= hx + 1.0:
		draw_circle(Vector2(x, -size.y * 0.5 + 14), 3.0, Palette.INK)
		draw_circle(Vector2(x, -size.y * 0.5 + 13), 2.0, col)
		x += maxf(60.0, (hx * 2.0) / maxf(1.0, floorf(hx * 2.0 / 60.0)))
