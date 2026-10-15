class_name Hud
extends CanvasLayer

## In-match overlay drawn in one Control: player cards, altitude track,
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
	_draw_cards(vp)
	_draw_track(vp)
	_draw_offscreen(vp)
	_draw_countdown(vp)
	if Settings.get_value("show_fps"):
		_text(Vector2(vp.x - 110, vp.y - 16), "%d FPS" % Engine.get_frames_per_second(), 16, Palette.TEXT_DIM, HORIZONTAL_ALIGNMENT_RIGHT, 100, false)


func _draw_cards(vp: Vector2) -> void:
	var players: Array = game.players
	var w := 200.0
	var h := 66.0
	var gap := 12.0
	var total := players.size() * w + (players.size() - 1) * gap
	var x := (vp.x - total) * 0.5
	for p: Player in players:
		var r := Rect2(x, 14, w, h)
		var dim := 0.4 if p.is_dead else 1.0
		var bg := UiTheme.box(Color(Palette.PANEL, 0.85 * dim), Color(p.color, 0.9 * dim), 2, 12)
		_canvas.draw_style_box(bg, r)
		# Colour chip
		_canvas.draw_circle(r.position + Vector2(26, 33), 14, Palette.BG_DEEP)
		_canvas.draw_circle(r.position + Vector2(26, 33), 11, Color(p.color, dim))
		_text(r.position + Vector2(48, 30), "P%d" % p.player_id, 20, Color(p.color, dim))
		var hstr := "OUT" if p.is_dead else "%d m" % p.height_meters()
		if p.is_dead:
			hstr = "OUT  %d m" % p.info.max_height
		_text(r.position + Vector2(48, 54), hstr, 18, Color(Palette.TEXT, dim), HORIZONTAL_ALIGNMENT_LEFT, -1, false)
		if not p.is_dead:
			_ability_bar(Rect2(r.position + Vector2(132, 22), Vector2(58, 9)), p.shock_ready(), p.color, "SHOCK")
			_ability_bar(Rect2(r.position + Vector2(132, 48), Vector2(58, 9)), p.gravity_ready(), p.color, "FIELD")
		x += w + gap
	# Best height reminder
	var best: int = Settings.get_value("best_height")
	if best > 0:
		_text(Vector2(0, vp.y - 16), "BEST %d m" % best, 16, Color(Palette.TEXT_DIM, 0.8), HORIZONTAL_ALIGNMENT_CENTER, vp.x, false)


func _ability_bar(r: Rect2, ready: float, col: Color, label: String) -> void:
	_canvas.draw_string(_font, r.position + Vector2(0, -3), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(Palette.TEXT_DIM, 0.9 if ready >= 1.0 else 0.55))
	_canvas.draw_rect(r, Color(Palette.BG_DEEP, 0.9))
	var fill := Rect2(r.position, Vector2(r.size.x * ready, r.size.y))
	_canvas.draw_rect(fill, col.lightened(0.3) if ready >= 1.0 else Color(col, 0.55))
	if ready >= 1.0:
		_canvas.draw_rect(r, Color(1, 1, 1, 0.5), false, 1.0)


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
	_canvas.draw_line(Vector2(x, top_y), Vector2(x, bot_y), Color(Palette.LINE, 0.8), 4.0)
	# Lava blob at the bottom
	_canvas.draw_rect(Rect2(x - 8, bot_y - 4, 16, 10), Palette.LAVA)
	_text(Vector2(x - 40, bot_y + 26), "LAVA", 14, Palette.LAVA, HORIZONTAL_ALIGNMENT_CENTER, 80)
	for p: Player in players:
		if p.is_dead:
			continue
		var y: float = map_y.call(p.global_position.y)
		_canvas.draw_circle(Vector2(x, y), 9, Palette.BG_DEEP)
		_canvas.draw_circle(Vector2(x, y), 7, p.color)
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
		_text(Vector2(0, vp.y * 0.45), str(n), 140, Palette.ACCENT, HORIZONTAL_ALIGNMENT_CENTER, vp.x)
	elif game.show_go():
		_text(Vector2(0, vp.y * 0.45), "CLIMB!", 110, Palette.GOOD, HORIZONTAL_ALIGNMENT_CENTER, vp.x)
