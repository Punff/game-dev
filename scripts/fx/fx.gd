class_name Fx
extends Node2D

## One small, self-freeing effect node covering every short-lived visual
## (rings, bursts, cones, floating text). Everything is drawn with _draw,
## no particles or shaders, which keeps the web build fast.

enum Kind { RING, BURST, CONE, TEXT, DUST }

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


static func burst(pos: Vector2, col: Color, count := 10, speed := 260.0, dur := 0.5) -> void:
	if reduced:
		count = int(count * 0.5)
	var fx := Fx.new()
	fx.kind = Kind.BURST
	fx.color = col
	fx.duration = dur
	for i in count:
		var a := randf() * TAU
		fx._parts.append({"p": Vector2.ZERO, "v": Vector2(cos(a), sin(a)) * speed * randf_range(0.35, 1.0), "r": randf_range(3.0, 6.0)})
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
		fx._parts.append({"p": Vector2(side * 4, 0), "v": Vector2(side * randf_range(60, 170), randf_range(-60, -10)), "r": randf_range(3.0, 6.0)})
	_spawn(fx, pos)


static func cone(pos: Vector2, dir: Vector2, col: Color, r: float) -> void:
	var fx := Fx.new()
	fx.kind = Kind.CONE
	fx.color = col
	fx.radius = r
	fx.direction = dir
	fx.duration = 0.32
	_spawn(fx, pos)


static func popup(pos: Vector2, txt: String, col: Color, size := 34.0) -> void:
	var fx := Fx.new()
	fx.kind = Kind.TEXT
	fx.text = txt
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
		p.p += p.v * delta
		p.v *= 1.0 - 4.0 * delta
		if kind == Kind.DUST:
			p.v.y -= 30.0 * delta
	queue_redraw()


func _draw() -> void:
	var e := 1.0 - pow(1.0 - _t, 3.0)   # ease-out
	var a := 1.0 - _t
	match kind:
		Kind.RING:
			draw_arc(Vector2.ZERO, radius * e, 0.0, TAU, 40, Color(color, a), width * (1.0 - _t * 0.6), true)
		Kind.BURST, Kind.DUST:
			for p in _parts:
				draw_circle(p.p, p.r * (1.0 - _t * 0.7), Color(color, a))
		Kind.CONE:
			var base := direction.angle()
			var spread := PI * 0.28
			var r := radius * e
			draw_arc(Vector2.ZERO, r, base - spread, base + spread, 24, Color(color, a), 6.0 * a + 1.0, true)
			draw_arc(Vector2.ZERO, r * 0.8, base - spread * 0.85, base + spread * 0.85, 20, Color(color, a * 0.5), 3.0, true)
			draw_arc(Vector2.ZERO, r * 0.6, base - spread * 0.7, base + spread * 0.7, 16, Color(color, a * 0.25), 2.0, true)
		Kind.TEXT:
			var font := UiTheme.heavy()
			var size := int(radius * (1.0 + 0.25 * (1.0 - e)))
			var pos := Vector2(-200, -40.0 * e)
			var col := Color(color, minf(1.0, a * 2.0))
			draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, 400, size, 8, Color(Palette.BG_DEEP, col.a))
			draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, 400, size, col)
