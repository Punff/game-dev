class_name TitleCard
extends CanvasLayer

## '70s jazz title-card flash: slanted colour bars slam across the screen
## behind big condensed italic type, then wipe away. Used for the match
## start, chain reactions and eliminations.

const COLORS := [Palette.MUSTARD, Palette.RUST, Palette.BURGUNDY, Palette.PAPER, Palette.TEAL]

var _canvas := Control.new()
var _bars: Array = []
var _text := ""
var _sub := ""
var _t := 1.0
var _dur := 0.9
var _text_color := Palette.INK


func _ready() -> void:
	layer = 15
	process_mode = Node.PROCESS_MODE_ALWAYS
	_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_card)
	add_child(_canvas)


## bars: how many slanted stripes (fewer = subtler).
func show_card(text: String, sub := "", bars := 6, duration := 0.9, text_color := Palette.INK) -> void:
	_text = text.to_upper()
	_sub = sub.to_upper()
	_t = 0.0
	_dur = duration
	_text_color = text_color
	_bars.clear()
	var start := randi() % COLORS.size()
	for i in bars:
		_bars.append({"c": COLORS[(start + i) % COLORS.size()], "w": randf_range(60, 160), "delay": i * 0.03})
	if Fx.reduced:
		_bars = _bars.slice(0, 2)


func _process(delta: float) -> void:
	if _t < 1.0:
		_t = minf(_t + delta / _dur, 1.0)
		_canvas.queue_redraw()


func _draw_card() -> void:
	if _t >= 1.0:
		return
	var vp := _canvas.size
	var slant := vp.y * 0.35
	# Bars slide in from the left, hold, then exit right.
	var y := 0.0
	var total_h := 0.0
	for b in _bars:
		total_h += b.w
	y = vp.y * 0.5 - total_h * 0.5
	for b in _bars:
		var local: float = clampf((_t * _dur - b.delay) / (_dur * 0.85), 0.0, 1.0)
		var enter := 1.0 - pow(1.0 - minf(local / 0.25, 1.0), 3.0)
		var exit := pow(maxf((local - 0.7) / 0.3, 0.0), 2.0)
		var x0 := lerpf(-vp.x - slant, 0.0, enter) + exit * (vp.x + slant * 2.0)
		var h: float = b.w
		var pts := PackedVector2Array([
			Vector2(x0 + slant, y), Vector2(x0 + vp.x + slant * 2.0, y),
			Vector2(x0 + vp.x + slant * 2.0 - h * 0.6, y + h), Vector2(x0 + slant - h * 0.6, y + h)])
		_canvas.draw_colored_polygon(pts, b.c)
		_canvas.draw_line(pts[0], pts[1], Palette.INK, 4.0)
		y += h
	# Type punches in and holds while the bars are up.
	var ta := clampf(_t / 0.12, 0.0, 1.0) * (1.0 - clampf((_t - 0.8) / 0.2, 0.0, 1.0))
	var font := UiTheme.title_font()
	var size := int(minf(vp.x / maxf(_text.length(), 4) * 1.6, 150.0))
	var pos := Vector2(0, vp.y * 0.5 + size * 0.32)
	_canvas.draw_string_outline(font, pos + Vector2(6, 6), _text, HORIZONTAL_ALIGNMENT_CENTER, vp.x, size, 14, Color(Palette.INK, ta))
	_canvas.draw_string_outline(font, pos, _text, HORIZONTAL_ALIGNMENT_CENTER, vp.x, size, 14, Color(Palette.PAPER if _text_color == Palette.INK else Palette.INK, ta))
	_canvas.draw_string(font, pos, _text, HORIZONTAL_ALIGNMENT_CENTER, vp.x, size, Color(_text_color, ta))
	if _sub != "":
		_canvas.draw_string_outline(UiTheme.heavy(), pos + Vector2(0, 50), _sub, HORIZONTAL_ALIGNMENT_CENTER, vp.x, 32, 10, Color(Palette.INK, ta))
		_canvas.draw_string(UiTheme.heavy(), pos + Vector2(0, 50), _sub, HORIZONTAL_ALIGNMENT_CENTER, vp.x, 32, Color(Palette.PAPER, ta))
