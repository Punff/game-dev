class_name Block
extends AnimatableBody2D

## Base class for every platform. Blocks build their own collision shape and
## draw themselves in a flat ink style (no textures, no shaders), so they are
## cheap to spawn in bulk and look crisp at any zoom.

const HEIGHT := 60.0
const OUTLINE := 4.0
const SHADOW := Vector2(8, 8)

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
	_draw_body()
	_draw_icon()


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
