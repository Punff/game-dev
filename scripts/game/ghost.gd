class_name Ghost
extends Node2D

## Someone's run of the daily climb, played back beside you: a see-through
## ball with a name, where they were at this moment of their run. It touches
## nothing. At the end of the track (where they fell) it fades out.

const FADE := 0.8

var who := ""
var color := Palette.PAPER
var _step := Daily.STEP
var _pts := PackedVector2Array()
var _t := 0.0
var _font: Font


## `ghost`: {"step", "pts": [x, y, ...]} (see Daily).
func setup(name_text: String, ghost_color: Color, ghost: Dictionary) -> void:
	who = name_text
	color = ghost_color
	_step = maxf(float(ghost.get("step", Daily.STEP)), 0.01)
	var raw: Array = ghost.get("pts", [])
	for i in range(0, raw.size() - 1, 2):
		_pts.append(Vector2(raw[i], raw[i + 1]))
	z_index = 5
	_font = UiTheme.heavy()
	if not _pts.is_empty():
		position = _pts[0]


## Where the run is `t` s after the start (the game calls this every tick).
func seek(t: float) -> void:
	_t = t
	if _pts.is_empty():
		return
	var f := t / _step
	var i := clampi(int(f), 0, _pts.size() - 1)
	var j := mini(i + 1, _pts.size() - 1)
	position = _pts[i].lerp(_pts[j], clampf(f - i, 0.0, 1.0))
	var over := t - (_pts.size() - 1) * _step
	modulate.a = clampf(1.0 - over / FADE, 0.0, 1.0)
	visible = modulate.a > 0.0
	queue_redraw()


func _draw() -> void:
	draw_circle(Vector2.ZERO, Player.RADIUS + 1.0, Color(color, 0.32))
	draw_arc(Vector2.ZERO, Player.RADIUS + 1.0, 0.0, TAU, 24, Color(color, 0.7), 2.0)
	var w := _font.get_string_size(who, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	draw_string(_font, Vector2(-w * 0.5, -Player.RADIUS - 8.0), who, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(color, 0.75))
