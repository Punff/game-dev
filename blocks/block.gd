class_name Block
extends AnimatableBody2D

## Base class for every platform. Blocks build their own collision shape and
## draw themselves with cached style boxes (no textures, no shaders), so they
## are cheap to spawn in bulk and look crisp at any zoom.

const HEIGHT := 36.0
const RADIUS := 9

var block_id := "static_platform"
var size := Vector2(160.0, HEIGHT)
## Blocks that animate their icon redraw every frame; static ones draw once.
var animated := false

var _shape := RectangleShape2D.new()

static var _style_cache: Dictionary = {}


func _init() -> void:
	collision_layer = 1
	collision_mask = 0
	var cs := CollisionShape2D.new()
	cs.shape = _shape
	add_child(cs)
	_shape.size = size


func _ready() -> void:
	add_to_group("blocks")
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
	var styles := _styles(c[0], c[1])
	# Drop shadow, darker "lip", face, top highlight.
	draw_style_box(styles[0], Rect2(r.position + Vector2(0, 7), r.size))
	draw_style_box(styles[1], r)
	draw_style_box(styles[2], Rect2(r.position, r.size - Vector2(0, 6)))
	draw_style_box(styles[3], Rect2(r.position + Vector2(3, 3), Vector2(r.size.x - 6, 4)))


static func _styles(body: Color, hi: Color) -> Array:
	var key := body.to_html()
	if _style_cache.has(key):
		return _style_cache[key]
	var mk := func(col: Color, radius: int) -> StyleBoxFlat:
		var s := StyleBoxFlat.new()
		s.bg_color = col
		s.set_corner_radius_all(radius)
		s.anti_aliasing = true
		return s
	var arr := [
		mk.call(Color(0, 0, 0, 0.28), RADIUS),
		mk.call(body.darkened(0.42), RADIUS),
		mk.call(body, RADIUS),
		mk.call(Color(hi, 0.55), 3),
	]
	_style_cache[key] = arr
	return arr


## Repeats an icon along the block so long platforms stay readable.
func _icon_positions(spacing := 90.0) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var n := maxi(1, int(size.x / spacing))
	var step := size.x / n
	for i in n:
		out.append(Vector2(-size.x * 0.5 + step * (i + 0.5), -3.0))
	return out


func _icon_color(a := 0.85) -> Color:
	return Color(colors()[1].lightened(0.35), a)


func _draw_icon() -> void:
	# Static platforms: two subtle rivets.
	var col := Color(colors()[1], 0.6)
	var hx := size.x * 0.5 - 12.0
	draw_circle(Vector2(-hx, -3), 3.0, col)
	draw_circle(Vector2(hx, -3), 3.0, col)
