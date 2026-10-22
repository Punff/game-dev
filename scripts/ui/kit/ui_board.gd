class_name UiBoard
extends VBoxContainer

## A leaderboard from the server: rows with places, yours highlighted, and a
## line about where you stand. `around` centres it on your place (Results);
## otherwise it's the top of the board (Leaderboard page).
## Call refresh() to (re)load it.

const UNITS := {"height": " m", "wins": " wins"}

var board := "height"
var around := false
var limit := 15
var _list := VBoxContainer.new()
var _me: Label
var _asked := 0   # ignore answers to requests made before the last refresh


func _init(board_id := "height", around_me := false, rows := 15) -> void:
	board = board_id
	around = around_me
	limit = rows
	add_theme_constant_override("separation", 10)
	_list.add_theme_constant_override("separation", 4)
	add_child(_list)
	_me = UiTheme.label("", 20, Palette.ACCENT)
	_me.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_me)


func refresh() -> void:
	_me.text = ""
	if not Stats.enabled():
		show_message("Turn on Share Stats Online in Settings to see the leaderboard.")
		return
	show_message("Loading...")
	_asked += 1
	var asked := _asked
	Stats.leaderboard(board, func(ok: bool, reply: Dictionary):
		if asked == _asked:
			_fill(ok, reply), around, limit)


func _fill(ok: bool, reply: Dictionary) -> void:
	if not ok:
		show_message("Couldn't reach the leaderboard. Try again later.")
		return
	_clear()
	var unit: String = UNITS[board]
	var rows: Array = reply.get("rows", [])
	if rows.is_empty():
		show_message("Nobody on this board yet. Be the first!")
	for i in rows.size():
		var r: Dictionary = rows[i]
		var row := UiBoard.row(int(r.get("rank", i + 1)), str(r.get("name", "?")), "%d%s" % [int(r.get("value", 0)), unit], r.get("you", false))
		_list.add_child(row)
		UiFx.reveal(row, i * 0.03)
	var me: Variant = reply.get("me")
	if not Settings.logged_in():
		_me.text = "Log in or create an account to get ranked."
		_me.add_theme_color_override("font_color", Palette.TEXT_DIM)
	elif me is Dictionary:
		_me.text = "You (%s): #%d with %d%s" % [Settings.player_name(), me.rank, me.value, unit]
	else:
		_me.text = "You (%s): not on this board yet" % Settings.player_name()


## One line of a board: place, name, value. Yours is a mustard strip.
static func row(place: int, who: String, value: String, you := false) -> Control:
	var p := PanelContainer.new()
	var bg := Color(Palette.MUSTARD, 0.9) if you else (Color(Palette.INK_SOFT, 0.8) if place % 2 == 1 else Color.TRANSPARENT)
	p.add_theme_stylebox_override("panel", UiTheme.box(bg, Color.TRANSPARENT, 0, 0, Vector2(12, 2)))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	p.add_child(h)
	var ink := Palette.INK if you else Palette.TEXT
	var rank := UiTheme.title("%d" % place, 24, Palette.MUSTARD if place <= 3 and not you else ink)
	rank.custom_minimum_size.x = 44
	rank.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(rank)
	var n := UiTheme.label(who, 22, ink)
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	n.clip_text = true
	h.add_child(n)
	h.add_child(UiTheme.label(value, 22, ink))
	return p


## A line in place of the rows (loading, errors).
func show_message(text: String) -> void:
	_clear()
	_list.add_child(UiPage.notes(text))


func _clear() -> void:
	for c in _list.get_children():
		c.queue_free()
