class_name Fx
extends Node2D

## One small, self-freeing effect node covering every short-lived visual
## (rings, debris bursts, shockwave cones, speed lines, floating text).
## Everything is flat ink-and-colour drawn with _draw: no particles,
## no shaders, cheap on the web build.

enum Kind { RING, BURST, CONE, TEXT, DUST, LINES }

var kind := Kind.RING
var color := Color.WHITE
var radius := 60.0
var width := 4.0
var duration := 0.35
var direction := Vector2.RIGHT
var text := ""
var _t := 0.0
var _parts: Array = []

## Where effects get spawned. Set by the game scene.
static var layer: Node2D
static var reduced := false


static func _spawn(fx: Fx, pos: Vector2) -> Fx:
	if layer == null or not is_instance_valid(layer):
		fx.free()
		return null
	layer.add_child(fx)
	fx.global_position = pos
	return fx


static func ring(pos: Vector2, col: Color, r := 60.0, w := 4.0, dur := 0.35) -> void:
	var fx := Fx.new()
	fx.kind = Kind.RING
	fx.color = col
	fx.radius = r
	fx.width = w
	fx.duration = dur
	_spawn(fx, pos)


## Square debris flecks.
static func burst(pos: Vector2, col: Color, count := 10, speed := 260.0, dur := 0.5) -> void:
	if reduced:
		count = int(count * 0.5)
	var fx := Fx.new()
	fx.kind = Kind.BURST
	fx.color = col
	fx.duration = dur
	for i in count:
		var a := randf() * TAU
		fx._parts.append({"p": Vector2.ZERO, "v": Vector2(cos(a), sin(a)) * speed * randf_range(0.35, 1.0), "r": randf_range(3.0, 7.0), "rot": randf() * TAU})
	_spawn(fx, pos)


static func dust(pos: Vector2, col: Color, count := 6) -> void:
	if reduced:
		count = int(count * 0.5)
	var fx := Fx.new()
	fx.kind = Kind.DUST
	fx.color = col
	fx.duration = 0.4
	for i in count:
		var side := -1.0 if i % 2 == 0 else 1.0
		fx._parts.append({"p": Vector2(side * 4, 0), "v": Vector2(side * randf_range(80, 220), randf_range(-70, -10)), "r": randf_range(3.0, 6.0), "rot": 0.0})
	_spawn(fx, pos)


static func cone(pos: Vector2, dir: Vector2, col: Color, r: float) -> void:
	var fx := Fx.new()
	fx.kind = Kind.CONE
	fx.color = col
	fx.radius = r
	fx.direction = dir
	fx.duration = 0.3
	_spawn(fx, pos)


## Manga-style action lines radiating opposite to a direction of travel.
static func speed_lines(pos: Vector2, dir: Vector2, col: Color) -> void:
	var fx := Fx.new()
	fx.kind = Kind.LINES
	fx.color = col
	fx.direction = dir
	fx.duration = 0.25
	for i in (4 if reduced else 8):
		fx._parts.append({"off": randf_range(-40, 40), "len": randf_range(40, 110), "start": randf_range(10, 40)})
	_spawn(fx, pos)


static func popup(pos: Vector2, txt: String, col: Color, size := 34.0) -> void:
	var fx := Fx.new()
	fx.kind = Kind.TEXT
	fx.text = txt.to_upper()
	fx.color = col
	fx.radius = size
	fx.duration = 1.0
	fx.z_index = 50
	_spawn(fx, pos)


func _ready() -> void:
	z_index = 20


func _process(delta: float) -> void:
	_t += delta / duration
	if _t >= 1.0:
		queue_free()
		return
	for p in _parts:
		if p.has("v"):
			p.p += p.v * delta
			p.v *= 1.0 - 4.0 * delta
			p.rot += delta * 6.0
			if kind == Kind.DUST:
				p.v.y -= 30.0 * delta
	queue_redraw()


func _draw() -> void:
	var e := 1.0 - pow(1.0 - _t, 3.0)   # ease-out
	var a := 1.0 - _t
	match kind:
		Kind.RING:
			var r := radius * e
			draw_arc(Vector2.ZERO, r, 0.0, TAU, 40, Color(Palette.INK, a), width * 2.2 * (1.0 - _t * 0.6))
			draw_arc(Vector2.ZERO, r, 0.0, TAU, 40, Color(color, a), width * (1.0 - _t * 0.6))
		Kind.BURST, Kind.DUST:
			for p in _parts:
				var s: float = p.r * (1.0 - _t * 0.6)
				draw_set_transform(p.p, p.rot)
				draw_rect(Rect2(-s - 1.5, -s - 1.5, s * 2 + 3, s * 2 + 3), Color(Palette.INK, a))
				draw_rect(Rect2(-s, -s, s * 2, s * 2), Color(color, a))
			draw_set_transform(Vector2.ZERO)
		Kind.CONE:
			var base := direction.angle()
			var spread := PI * 0.3
			var r := radius * e
			# Flat wedge flash, then concentric ink arcs.
			if _t < 0.35:
				var pts := PackedVector2Array([Vector2.ZERO])
				for i in 13:
					var ang := base - spread + spread * 2.0 * i / 12.0
					pts.append(Vector2(cos(ang), sin(ang)) * r)
				draw_colored_polygon(pts, Color(color, 0.55 * (1.0 - _t / 0.35)))
			for k in 3:
				var rr := r * (1.0 - k * 0.18)
				draw_arc(Vector2.ZERO, rr, base - spread, base + spread, 24, Color(Palette.INK, a), 18.0 - k * 4.0)
				draw_arc(Vector2.ZERO, rr, base - spread, base + spread, 24, Color(Palette.PAPER if k == 0 else color, a), 10.0 - k * 2.5)
			# radial gun-blast streaks
			for k in 7:
				var ang := base - spread * 0.8 + spread * 1.6 * k / 6.0
				var dv := Vector2(cos(ang), sin(ang))
				draw_line(dv * r * 0.25, dv * r * 0.25 + dv * 60.0 * (1.0 - _t), Color(Palette.PAPER, a), 4.0)
		Kind.LINES:
			var d := direction.normalized()
			var side := d.orthogonal()
			for p in _parts:
				var s: Vector2 = -d * (p.start + 60.0 * e) + side * p.off
				var l: Vector2 = s - d * p.len * (1.0 - _t)
				draw_line(s, l, Color(Palette.INK, a), 6.0)
				draw_line(s, l, Color(color.lightened(0.3), a), 2.5)
		Kind.TEXT:
			var font := UiTheme.title_font()
			var size := int(radius * (1.0 + 0.3 * (1.0 - e)))
			var pos := Vector2(-250, -46.0 * e)
			var col := Color(color, minf(1.0, a * 2.0))
			draw_string_outline(font, pos + Vector2(4, 4), text, HORIZONTAL_ALIGNMENT_CENTER, 500, size, 10, Color(Palette.INK, col.a))
			draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, 500, size, 10, Color(Palette.INK, col.a))
			draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, 500, size, col)
