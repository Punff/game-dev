class_name Hud
extends CanvasLayer

## In-match overlay drawn in one Control: altitude track,
## countdown, off-screen arrows and the optional FPS counter.

var game: Node   # game.gd
var _canvas := Control.new()
var _font_heavy: Font
var _font: Font


func _ready() -> void:
	layer = 5
	_font_heavy = UiTheme.heavy()
	_font = UiTheme.bold()
	_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_hud)
	add_child(_canvas)


func _process(_delta: float) -> void:
	_canvas.queue_redraw()


func _text(pos: Vector2, s: String, size: int, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0, heavy := true) -> void:
	var f := _font_heavy if heavy else _font
	_canvas.draw_string_outline(f, pos, s, align, width, size, maxi(4, size / 5), Color(Palette.BG_DEEP, col.a * 0.9))
	_canvas.draw_string(f, pos, s, align, width, size, col)


func _draw_hud() -> void:
	if game == null:
		return
	var vp := _canvas.size
	_draw_track(vp)
	_draw_offscreen(vp)
	_draw_countdown(vp)
	if Settings.get_value("show_fps"):
		_text(Vector2(vp.x - 110, vp.y - 16), "%d FPS" % Engine.get_frames_per_second(), 16, Palette.TEXT_DIM, HORIZONTAL_ALIGNMENT_RIGHT, 100, false)


## Vertical track on the right: lava + every player's altitude.
func _draw_track(vp: Vector2) -> void:
	var players: Array = game.players
	var x := vp.x - 34.0
	var top_y := 110.0
	var bot_y := vp.y - 70.0
	var lava_y: float = game.lava.surface_y
	var hi := lava_y
	for p: Player in players:
		if not p.is_dead:
			hi = minf(hi, p.global_position.y)
	var span := maxf(lava_y - hi, 600.0) * 1.15
	var map_y := func(wy: float) -> float:
		return bot_y - (lava_y - wy) / span * (bot_y - top_y)
	_canvas.draw_line(Vector2(x, top_y), Vector2(x, bot_y), Palette.INK, 8.0)
	_canvas.draw_line(Vector2(x, top_y), Vector2(x, bot_y), Palette.PAPER_DIM, 3.0)
	# Lava block at the bottom
	_canvas.draw_rect(Rect2(x - 10, bot_y - 6, 20, 14), Palette.INK)
	_canvas.draw_rect(Rect2(x - 7, bot_y - 3, 14, 8), Palette.LAVA)
	_text(Vector2(x - 40, bot_y + 26), "LAVA", 14, Palette.LAVA, HORIZONTAL_ALIGNMENT_CENTER, 80)
	for p: Player in players:
		if p.is_dead:
			continue
		var y: float = map_y.call(p.global_position.y)
		_canvas.draw_rect(Rect2(x - 9, y - 9, 18, 18), Palette.INK)
		_canvas.draw_rect(Rect2(x - 6, y - 6, 12, 12), p.color)
		_text(Vector2(x - 54, y + 6), "P%d" % p.player_id, 15, p.color, HORIZONTAL_ALIGNMENT_RIGHT, 40)


## Arrows at the screen edge for players the camera can't see.
func _draw_offscreen(vp: Vector2) -> void:
	var xf := game.get_viewport().get_canvas_transform()
	var margin := 28.0
	for p: Player in game.players:
		if p.is_dead:
			continue
		var sp: Vector2 = xf * p.global_position
		if Rect2(Vector2.ZERO, vp).grow(-6).has_point(sp):
			continue
		var c := Vector2(clampf(sp.x, margin, vp.x - margin), clampf(sp.y, margin + 80, vp.y - margin))
		var dir := (sp - c).normalized()
		if dir == Vector2.ZERO:
			dir = Vector2.DOWN
		var side := dir.orthogonal()
		var tip := c + dir * 14
		_canvas.draw_colored_polygon(PackedVector2Array([tip, c - dir * 6 + side * 12, c - dir * 6 - side * 12]), p.color)
		_canvas.draw_circle(c - dir * 20, 12, Palette.BG_DEEP)
		_text(c - dir * 20 + Vector2(-20, 6), "%d" % p.player_id, 16, p.color, HORIZONTAL_ALIGNMENT_CENTER, 40)


func _draw_countdown(vp: Vector2) -> void:
	var n: int = game.countdown_value()
	if n > 0:
		_text(Vector2(0, vp.y * 0.45), str(n), 110, Palette.PAPER, HORIZONTAL_ALIGNMENT_CENTER, vp.x)
