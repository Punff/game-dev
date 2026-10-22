class_name LeaderboardPage
extends UiPage

## Best solo climbs or online wins, and your place. Everything comes from
## Stats (the server). Only accounts are ranked.

const BOARDS := [["height", "Highest Climb"], ["wins", "Online Wins"]]

var _asked := 0   # ignore answers to requests made before the last tab switch


func _init() -> void:
	title = "Leaderboard"


func build() -> void:
	tabs = UiTabs.new()
	for i in BOARDS.size():
		tabs.add_tab(BOARDS[i][1], _build_board.bind(i))
	add_child(tabs)
	tabs.show_tab(0, false)


func _build_board(body: VBoxContainer, board: int) -> void:
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 4)
	body.add_child(list)
	var me := UiTheme.label("", 20, Palette.ACCENT)
	body.add_child(me)
	var b: Button
	if Settings.logged_in():
		b = UiTheme.button("Refresh", 200)
		b.pressed.connect(func(): tabs.show_tab(tabs.index))
	else:
		b = UiTheme.button("Log in to get ranked", 0)
		b.pressed.connect(func(): push(SignInPage.new()))
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	body.add_child(b)
	UiNav.link_vertical([b])

	if not Stats.enabled():
		list.add_child(UiPage.notes("Turn on Share Stats Online in Settings to see the leaderboard."))
		return
	list.add_child(UiPage.notes("Loading..."))
	_asked += 1
	var asked := _asked
	Stats.leaderboard(BOARDS[board][0], func(ok: bool, reply: Dictionary):
		if asked == _asked and is_instance_valid(list):
			_fill(list, me, board, ok, reply))


func _fill(list: VBoxContainer, me: Label, board: int, ok: bool, reply: Dictionary) -> void:
	for c in list.get_children():
		c.queue_free()
	if not ok:
		list.add_child(UiPage.notes("Couldn't reach the leaderboard. Try again later."))
		return
	var unit := " m" if BOARDS[board][0] == "height" else " wins"
	var rows: Array = reply.get("rows", [])
	if rows.is_empty():
		list.add_child(UiPage.notes("Nobody on this board yet. Be the first!"))
	for i in rows.size():
		var row := _row(i + 1, rows[i], unit)
		list.add_child(row)
		UiFx.reveal(row, i * 0.02)
	var mine: Variant = reply.get("me")
	if not Settings.logged_in():
		me.text = "Log in or create an account to get ranked."
	elif mine is Dictionary:
		me.text = "You (%s): #%d with %d%s" % [Settings.player_name(), mine.rank, mine.value, unit]
	else:
		me.text = "You (%s): not on this board yet" % Settings.player_name()


func _row(place: int, r: Dictionary, unit: String) -> Control:
	var you: bool = r.get("you", false)
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
	var n := UiTheme.label(str(r.get("name", "?")), 22, ink)
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(n)
	h.add_child(UiTheme.label("%d%s" % [int(r.get("value", 0)), unit], 22, ink))
	return p
