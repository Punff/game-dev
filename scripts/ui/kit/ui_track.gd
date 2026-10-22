class_name UiTrack
extends Button

## One entry on the tracklist: a side number (A1) and a name. `current`
## keeps a mustard marker on it while its page is open in the sleeve.

var id := ""
var number := ""
var current := false :
	set(v):
		current = v
		queue_redraw()
## A count waiting behind this track (e.g. friend invites), "" for none.
var badge := "" :
	set(v):
		if v != badge and v != "":
			UiFx.bump(self, 0.08)
		badge = v
		queue_redraw()


func _init(track_id := "", track_number := "", text_value := "") -> void:
	id = track_id
	number = track_number
	text = text_value.to_upper()
	theme_type_variation = "TrackButton"
	alignment = HORIZONTAL_ALIGNMENT_LEFT
	custom_minimum_size = Vector2(300, 50)
	size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	focus_mode = Control.FOCUS_ALL
	pressed.connect(func(): Sfx.play("ui_select"))
	focus_entered.connect(func(): Sfx.play("ui_move"))
	focus_exited.connect(queue_redraw)
	focus_entered.connect(queue_redraw)
	UiFx.wire_button(self)


func _draw() -> void:
	var font := UiTheme.title_font()
	var fs := 22
	var lit := has_focus()
	var col := Palette.INK if lit else (Palette.MUSTARD if current else Palette.PAPER_DIM)
	draw_string(font, Vector2(16, size.y * 0.5 + fs * 0.36), number, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
	if badge != "":
		var bf := UiTheme.heavy()
		var bs := 16
		var w := bf.get_string_size(badge, HORIZONTAL_ALIGNMENT_LEFT, -1, bs).x + 14
		var r := Rect2(Vector2(size.x - w - 10, size.y * 0.5 - 12), Vector2(w, 24))
		draw_rect(Rect2(r.position + Vector2(2, 2), r.size), Palette.INK)
		draw_rect(r, Palette.MUSTARD)
		draw_string(bf, Vector2(r.position.x + 7, size.y * 0.5 + bs * 0.36), badge, HORIZONTAL_ALIGNMENT_LEFT, -1, bs, Palette.INK)
	if current and not lit:
		var y := size.y * 0.5
		draw_colored_polygon(PackedVector2Array([Vector2(-14, y - 8), Vector2(-2, y), Vector2(-14, y + 8)]), Palette.MUSTARD)
