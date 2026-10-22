class_name VinylStage
extends Control

## The player's corner of the main menu: their ball riding a spinning record,
## a tonearm, and a name tag with their rank. The shell moves it with
## `center` / `radius`; pages preview looks on it (Profile > Customise).
## Hops when you pick something, wobbles when you back out.

const LABEL_TEXT := "ULTIMATE CAKUM PAKUM  •  SIDE A  •  33 1/3 RPM  •  "

var center := Vector2(640, 360)
var radius := 180.0
var look: Dictionary = BallPortrait.my_look()
var player_name := ""
var rank_text := ""

var _spin := 0.0
var _hop := 1.0       # 0 -> 1 over a hop
var _shake := 0.0
var _t := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func set_look(l: Dictionary) -> void:
	look = l
	hop()


func hop() -> void:
	if UiFx.enabled():
		_hop = 0.0


func wobble() -> void:
	if UiFx.enabled():
		_shake = 1.0


func _process(delta: float) -> void:
	_t += delta
	if UiFx.enabled():
		_spin += delta * 0.9
	_hop = minf(_hop + delta * 2.6, 1.0)
	_shake = move_toward(_shake, 0.0, delta * 3.0)
	queue_redraw()


func _draw() -> void:
	var c := center + Vector2(sin(_t * 40.0) * _shake * 6.0, 0)
	var r := radius
	var col: Color = look.get("color", Palette.PAPER)

	# The record.
	draw_circle(c + Vector2(14, 16), r, Color(Palette.INK, 0.55))
	draw_circle(c, r, Palette.INK)
	var groove := Color(Palette.PAPER, 0.06)
	var rr := r * 0.5
	while rr < r * 0.96:
		draw_arc(c, rr, 0, TAU, 64, groove, 1.5)
		rr += r * 0.045
	# Light catching the grooves (doesn't turn - the light stays put).
	for k in 6:
		var band := r * (0.55 + k * 0.07)
		draw_arc(c, band, -2.5, -1.9, 16, Color(Palette.PAPER, 0.07), r * 0.035)
		draw_arc(c, band, 0.64, 1.24, 16, Color(Palette.PAPER, 0.05), r * 0.035)
	draw_arc(c, r - 1.5, 0, TAU, 96, Palette.SMOKE, 3.0)

	# The label, in the player's colour, with its text going round.
	var lr := r * 0.42
	draw_circle(c, lr, Palette.PAPER_DIM)
	draw_arc(c, lr * 0.66, 0, TAU, 48, col, lr * 0.1)
	draw_arc(c, lr, 0, TAU, 64, Palette.INK, 4.0)
	var font := UiTheme.heavy()
	var fs := maxi(9, int(r * 0.065))
	var n := LABEL_TEXT.length()
	for i in n:
		var a := _spin + TAU * i / n
		draw_set_transform(c + Vector2.from_angle(a) * lr * 0.8, a + PI * 0.5)
		draw_char(font, Vector2(-fs * 0.3, fs * 0.35), LABEL_TEXT[i], fs, Color(Palette.INK, 0.8))
	draw_set_transform(Vector2.ZERO)
	draw_circle(c, 5.0, Palette.PAPER_DIM)

	# Tonearm resting on the outer grooves.
	var pivot := c + Vector2(r * 0.98, -r * 0.92)
	var head := c + Vector2(r * 0.62, -r * 0.42)
	draw_circle(pivot, r * 0.09, Palette.INK)
	draw_circle(pivot, r * 0.06, Palette.SMOKE)
	draw_line(pivot, head, Palette.INK, r * 0.06)
	draw_line(pivot, head, Palette.PAPER_DIM, r * 0.025)
	draw_set_transform(head, (head - pivot).angle())
	draw_rect(Rect2(Vector2(-r * 0.04, -r * 0.05), Vector2(r * 0.12, r * 0.1)), Palette.PAPER_DIM)
	draw_rect(Rect2(Vector2(-r * 0.04, -r * 0.05), Vector2(r * 0.12, r * 0.1)), Palette.INK, false, 2.0)
	draw_set_transform(Vector2.ZERO)

	# The ball, riding the label.
	var br := r * 0.27
	var up := sin(_hop * PI) * r * 0.32
	var squash := Vector2.ONE
	if _hop < 0.15:
		squash = Vector2(1.12, 0.88)
	elif _hop < 1.0:
		squash = Vector2(0.94, 1.08)
	var bob := sin(_t * 2.2) * br * 0.05
	BallPortrait.draw_ball(self, c - Vector2(0, br * 0.12 + up + bob), br, look, squash)

	# Name tag sticker + rank chip under the record.
	if player_name == "":
		return
	var tag_fs := clampi(int(r * 0.15), 18, 30)
	var w := font.get_string_size(player_name, HORIZONTAL_ALIGNMENT_LEFT, -1, tag_fs).x + 28
	var h := tag_fs + 14.0
	var tag_pos := c + Vector2(-w * 0.5, r + 22)
	draw_set_transform(tag_pos, deg_to_rad(-3.0))
	draw_rect(Rect2(Vector2(5, 5), Vector2(w, h)), Palette.MUSTARD)
	draw_rect(Rect2(Vector2.ZERO, Vector2(w, h)), Palette.PAPER)
	draw_rect(Rect2(Vector2.ZERO, Vector2(w, h)), Palette.INK, false, 2.0)
	draw_string(font, Vector2(14, h * 0.5 + tag_fs * 0.36), player_name, HORIZONTAL_ALIGNMENT_LEFT, -1, tag_fs, Palette.INK)
	if rank_text != "":
		var cfs := maxi(14, tag_fs - 8)
		var cw := font.get_string_size(rank_text, HORIZONTAL_ALIGNMENT_LEFT, -1, cfs).x + 16
		var cp := Vector2(w - cw * 0.4, -cfs * 0.9)
		draw_set_transform(tag_pos + cp, deg_to_rad(6.0))
		draw_rect(Rect2(Vector2(3, 3), Vector2(cw, cfs + 8)), Palette.INK)
		draw_rect(Rect2(Vector2.ZERO, Vector2(cw, cfs + 8)), Palette.MUSTARD)
		draw_string(font, Vector2(8, (cfs + 8) * 0.5 + cfs * 0.36), rank_text, HORIZONTAL_ALIGNMENT_LEFT, -1, cfs, Palette.INK)
	draw_set_transform(Vector2.ZERO)
