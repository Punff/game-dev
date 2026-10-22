class_name BallPortrait
extends Control

## The player ball as menu art: one or a few balls bobbing in a row.
## `draw_ball()` is the one place the menu ball is drawn, so the lobby cards,
## the vinyl stage and the mode cards all agree. A look is a dictionary:
## {"color": Color} today; skin / trail / tag slot in later.

## Looks to draw, left to right (they overlap a little).
var looks: Array = [] :
	set(v):
		looks = v
		queue_redraw()
var radius := 34.0
## Draw radio waves around the group (online).
var waves := false
var _t := randf() * TAU


static func look_for_color(c: Color) -> Dictionary:
	return {"color": c}


## The player's own look, from Settings (Profile > Customise).
static func my_look() -> Dictionary:
	var idx := clampi(int(Settings.get_value("ball_color")), 0, Palette.PLAYER_COLORS.size() - 1)
	return look_for_color(Palette.PLAYER_COLORS[idx])


## A ball at `p` with radius `r` (fill radius; the ink rim is outside it).
## `squash` stretches it (x, y) for hops and landings.
static func draw_ball(ci: CanvasItem, p: Vector2, r: float, look: Dictionary, squash := Vector2.ONE, shadow := true) -> void:
	var color: Color = look.get("color", Palette.PAPER)
	var k := r / 33.0
	if shadow:
		ci.draw_set_transform(p + Vector2(8, 8) * k, 0.0, squash)
		ci.draw_circle(Vector2.ZERO, 36 * k, Color(Palette.INK, 0.5))
	ci.draw_set_transform(p, 0.0, squash)
	ci.draw_circle(Vector2.ZERO, 38 * k, Palette.INK)
	ci.draw_circle(Vector2.ZERO, 33 * k, color)
	ci.draw_arc(Vector2(4, 4) * k, 26 * k, 0.2, 1.9, 12, color.darkened(0.35), 6.0 * k)
	ci.draw_line(Vector2(-16, -8) * k, Vector2(18, -8) * k, Palette.INK, 12.0 * k)
	ci.draw_line(Vector2(-12, -8) * k, Vector2(14, -8) * k, Palette.PAPER, 5.0 * k)
	ci.draw_set_transform(Vector2.ZERO)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if custom_minimum_size == Vector2.ZERO:
		custom_minimum_size = Vector2(0, radius * 2.8)


func _process(delta: float) -> void:
	if UiFx.enabled():
		_t += delta
		queue_redraw()


func _draw() -> void:
	var n := looks.size()
	if n == 0:
		return
	var step := radius * 1.6
	var x0 := size.x * 0.5 - step * (n - 1) * 0.5
	var y := size.y * 0.5
	if waves:
		for i in 3:
			var a := fmod(_t * 0.8 + i / 3.0, 1.0)
			var rr := radius * (1.3 + a * 0.8) + step * (n - 1) * 0.5
			draw_arc(Vector2(size.x * 0.5, y), rr, -2.4, -0.7, 16, Color(Palette.MUSTARD, 0.6 * (1.0 - a)), 4.0)
	for i in n:
		var bob := sin(_t * 2.4 + i * 1.3) * radius * 0.08
		draw_ball(self, Vector2(x0 + step * i, y + bob), radius, looks[i])
