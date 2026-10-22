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
	if current and not lit:
		var y := size.y * 0.5
		draw_colored_polygon(PackedVector2Array([Vector2(-14, y - 8), Vector2(-2, y), Vector2(-14, y + 8)]), Palette.MUSTARD)
