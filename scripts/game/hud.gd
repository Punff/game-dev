class_name Hud
extends CanvasLayer

## In-match overlay: altitude track, countdown, off-screen arrows and the
## optional FPS counter. Shapes are drawn in one Control; text lives in
## Labels that are only moved each frame (redrawing outlined text every
## frame from script was the HUD's main cost, especially in the browser).

var game: Node   # game.gd
var _canvas := Control.new()
var _lava_label: Label
var _tags := {}          # player_id -> Label on the altitude track
var _arrow_tags := {}    # player_id -> Label in an off-screen arrow
var _countdown: Label
var _fps: Label
var _last_count := -1
var _callout: Label
var _alive := -1


func _ready() -> void:
	layer = 5
	_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_hud)
	add_child(_canvas)
	_lava_label = _label("LAVA", 14, Palette.LAVA, HORIZONTAL_ALIGNMENT_CENTER)
	_countdown = _label("", 110, Palette.PAPER, HORIZONTAL_ALIGNMENT_CENTER)
	_countdown.add_theme_font_override("font", UiTheme.title_font())
	_countdown.visible = false
	_callout = _label("", 64, Palette.MUSTARD, HORIZONTAL_ALIGNMENT_CENTER)
	_callout.add_theme_font_override("font", UiTheme.title_font())
	_callout.visible = false
	_fps = _label("", 16, Palette.TEXT_DIM, HORIZONTAL_ALIGNMENT_RIGHT, false)


func _label(text: String, size: int, col: Color, align: HorizontalAlignment, heavy := true) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.add_theme_font_override("font", UiTheme.heavy() if heavy else UiTheme.bold())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(Palette.BG_DEEP, 0.9))
	l.add_theme_constant_override("outline_size", maxi(4, size / 5))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(l)
	return l


## Places a label so its text baseline sits where draw_string would put it.
func _place(l: Label, pos: Vector2, width: float) -> void:
	l.size = Vector2(width, 0)
	var font: Font = l.get_theme_font("font")
	var fs: int = l.get_theme_font_size("font_size")
	l.position = pos - Vector2(0, font.get_ascent(fs))


func _process(_delta: float) -> void:
	_canvas.queue_redraw()
	if game == null:
		return
	var vp := _canvas.size
	_update_track_labels(vp)
	_update_arrow_labels(vp)
	var n: int = game.countdown_value()
	_place(_countdown, Vector2(0, vp.y * 0.45), vp.x)
	if n != _last_count:
		if n > 0:
			_countdown.text = str(n)
			_countdown.add_theme_color_override("font_color", Palette.PAPER)
			_countdown.visible = true
			_countdown.modulate.a = 1.0
			UiFx.stamp(_countdown, 1.8, -6.0)
		elif _last_count > 0:
			# Countdown over: GO! slams on, then lifts away.
			_countdown.text = "GO!"
			_countdown.add_theme_color_override("font_color", Palette.MUSTARD)
			UiFx.stamp(_countdown, 2.2, 8.0)
			var tw := _countdown.create_tween()
			tw.tween_interval(0.45)
			tw.tween_property(_countdown, "modulate:a", 0.0, 0.25)
			tw.tween_callback(func(): _countdown.visible = false)
		else:
			_countdown.visible = false
	_last_count = n
	_place(_callout, Vector2(0, vp.y * 0.22), vp.x)
	_check_last_two()
	_fps.visible = Settings.get_value("show_fps")
	if _fps.visible:
		_fps.text = "%d FPS" % Engine.get_frames_per_second()
		if Net.is_client():
			_fps.text = "%d ms   %s" % [roundi(Net.lead_time * 1000.0), _fps.text]   # how far ahead of the host we run
		_place(_fps, Vector2(vp.x - 210, vp.y - 16), 200)


## Down to the last two of a bigger match: a stamped callout.
func _check_last_two() -> void:
	var alive := 0
	for p: Player in game.players:
		if not p.is_dead:
			alive += 1
	if alive == 2 and _alive > 2 and MatchManager.state == MatchManager.State.PLAYING:
		_callout.text = "Last two!"
		_callout.visible = true
		_callout.modulate.a = 1.0
		UiFx.stamp(_callout, 1.9, -6.0)
		var tw := _callout.create_tween()
		tw.tween_interval(1.1)
		tw.tween_property(_callout, "modulate:a", 0.0, 0.3)
		tw.tween_callback(func(): _callout.visible = false)
	_alive = alive


func _draw_hud() -> void:
	if game == null:
		return
	var vp := _canvas.size
	_draw_track(vp)
	_draw_offscreen(vp)


# ── Altitude track ───────────────────────────

func _track(vp: Vector2) -> Dictionary:
	var lava_y: float = game.lava.surface_y
	var hi := lava_y
	for p: Player in game.players:
		if not p.is_dead:
			hi = minf(hi, p.global_position.y)
	return {"x": vp.x - 34.0, "top": 110.0, "bot": vp.y - 70.0, "lava": lava_y,
		"span": maxf(lava_y - hi, 600.0) * 1.15}


func _track_y(t: Dictionary, wy: float) -> float:
	return t.bot - (t.lava - wy) / t.span * (t.bot - t.top)


## Vertical track on the right: lava + every player's altitude.
func _draw_track(vp: Vector2) -> void:
	var t := _track(vp)
	var x: float = t.x
	_canvas.draw_line(Vector2(x, t.top), Vector2(x, t.bot), Palette.INK, 8.0)
	_canvas.draw_line(Vector2(x, t.top), Vector2(x, t.bot), Palette.PAPER_DIM, 3.0)
	# Lava block at the bottom
	_canvas.draw_rect(Rect2(x - 10, t.bot - 6, 20, 14), Palette.INK)
	_canvas.draw_rect(Rect2(x - 7, t.bot - 3, 14, 8), Palette.LAVA)
	for p: Player in game.players:
		if p.is_dead:
			continue
		var y := _track_y(t, p.global_position.y)
		_canvas.draw_rect(Rect2(x - 9, y - 9, 18, 18), Palette.INK)
		_canvas.draw_rect(Rect2(x - 6, y - 6, 12, 12), p.color)


func _update_track_labels(vp: Vector2) -> void:
	var t := _track(vp)
	_place(_lava_label, Vector2(t.x - 40, t.bot + 26), 80)
	for p: Player in game.players:
		var l: Label = _tags.get(p.player_id)
		if l == null:
			l = _label("P%d" % p.player_id, 15, p.color, HORIZONTAL_ALIGNMENT_RIGHT)
			_tags[p.player_id] = l
		l.visible = not p.is_dead
		if l.visible:
			_place(l, Vector2(t.x - 54, _track_y(t, p.global_position.y) + 6), 40)


# ── Off-screen arrows ────────────────────────

## Where the arrow for a player off screen goes, or {} if they're visible.
func _arrow(vp: Vector2, p: Player) -> Dictionary:
	var sp: Vector2 = game.get_viewport().get_canvas_transform() * p.global_position
	if p.is_dead or Rect2(Vector2.ZERO, vp).grow(-6).has_point(sp):
		return {}
	var margin := 28.0
	var c := Vector2(clampf(sp.x, margin, vp.x - margin), clampf(sp.y, margin + 80, vp.y - margin))
	var dir := (sp - c).normalized()
	if dir == Vector2.ZERO:
		dir = Vector2.DOWN
	return {"c": c, "dir": dir}


## Arrows at the screen edge for players the camera can't see.
func _draw_offscreen(vp: Vector2) -> void:
	for p: Player in game.players:
		var a := _arrow(vp, p)
		if a.is_empty():
			continue
		var c: Vector2 = a.c
		var dir: Vector2 = a.dir
		var side := dir.orthogonal()
		var tip := c + dir * 14
		_canvas.draw_colored_polygon(PackedVector2Array([tip, c - dir * 6 + side * 12, c - dir * 6 - side * 12]), p.color)
		_canvas.draw_circle(c - dir * 20, 12, Palette.BG_DEEP)


func _update_arrow_labels(vp: Vector2) -> void:
	for p: Player in game.players:
		var l: Label = _arrow_tags.get(p.player_id)
		if l == null:
			l = _label("%d" % p.player_id, 16, p.color, HORIZONTAL_ALIGNMENT_CENTER)
			_arrow_tags[p.player_id] = l
		var a := _arrow(vp, p)
		l.visible = not a.is_empty()
		if l.visible:
			_place(l, a.c - a.dir * 20 + Vector2(-20, 6), 40)
