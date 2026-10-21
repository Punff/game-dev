class_name LeaderboardMenu
extends MenuBase

## Leaderboard overlay from the main menu: best solo climbs or online wins,
## your own rank, and your totals. Everything comes from Stats (the server).
## Only accounts are ranked; the Account button logs in or out.

const BOARDS := [["height", "Highest Climb"], ["wins", "Online Wins"]]

var _board := 0
var _tab_buttons: Array[Button] = []
var _list: VBoxContainer
var _me: Label
var _totals: Label
var _back: Button
var _account: Button
var _asked := 0   # ignore answers to requests made before the last tab switch


func _ready() -> void:
	build_overlay(0.7, 620)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	var title := UiTheme.title("leaderboard", 40)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	content.add_child(header)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 12)
	for i in BOARDS.size():
		var tb := UiTheme.button(BOARDS[i][1], 220)
		tb.toggle_mode = true
		tb.pressed.connect(_set_board.bind(i))
		tabs.add_child(tb)
		_tab_buttons.append(tb)
	content.add_child(tabs)
	content.add_child(HSeparator.new())

	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 4)
	_list.custom_minimum_size.y = 380
	content.add_child(_list)
	content.add_child(HSeparator.new())
	_me = UiTheme.label("", 20, Palette.ACCENT)
	content.add_child(_me)
	_totals = UiTheme.label("", 16, Palette.TEXT_DIM)
	_totals.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_totals)
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	_account = UiTheme.button("", 300)
	_account.pressed.connect(func(): open_sub(AccountMenu.new()))
	footer.add_child(_account)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(gap)
	_back = UiTheme.button("Back", 160)
	_back.pressed.connect(func(): closed.emit())
	footer.add_child(_back)
	content.add_child(footer)
	MenuBase.link_vertical([_tab_buttons[0], _account])
	_tab_buttons[0].focus_neighbor_right = _tab_buttons[0].get_path_to(_tab_buttons[1])
	_tab_buttons[1].focus_neighbor_left = _tab_buttons[1].get_path_to(_tab_buttons[0])
	_tab_buttons[1].focus_neighbor_top = _tab_buttons[1].get_path_to(_back)
	_tab_buttons[1].focus_neighbor_bottom = _tab_buttons[1].get_path_to(_back)
	_account.focus_neighbor_right = _account.get_path_to(_back)
	_back.focus_neighbor_left = _back.get_path_to(_account)
	_back.focus_neighbor_top = _back.get_path_to(_tab_buttons[1])
	_back.focus_neighbor_bottom = _back.get_path_to(_tab_buttons[1])

	Stats.account_changed.connect(_refresh)
	_refresh()
	_tab_buttons[0].grab_focus.call_deferred()
	UiFx.stamp(panel, 1.06, -1.5)


func _refresh() -> void:
	_account.text = "Account: " + Settings.player_name() if Settings.logged_in() else "Log in / Create account"
	_totals.text = ""
	_set_board(_board)
	_load_totals()


func _set_board(i: int) -> void:
	_board = i
	for k in _tab_buttons.size():
		_tab_buttons[k].button_pressed = k == i
	_show_message("Loading..." if Stats.enabled() else "Turn on Share Stats Online in Settings to see the leaderboard.")
	_me.text = ""
	if not Stats.enabled():
		return
	_asked += 1
	var asked := _asked
	Stats.leaderboard(BOARDS[i][0], func(ok: bool, reply: Dictionary):
		if asked == _asked and is_inside_tree():
			_fill(ok, reply))


func _fill(ok: bool, reply: Dictionary) -> void:
	if not ok:
		_show_message("Couldn't reach the leaderboard. Try again later.")
		return
	var rows: Array = reply.get("rows", [])
	if rows.is_empty():
		_show_message("Nobody on this board yet. Be the first!")
	else:
		_clear()
		for i in rows.size():
			_list.add_child(_row(i + 1, rows[i]))
	var me: Variant = reply.get("me")
	var unit := " m" if BOARDS[_board][0] == "height" else " wins"
	if not Settings.logged_in():
		_me.text = "Log in or create an account to get ranked."
	elif me is Dictionary:
		_me.text = "You (%s): #%d with %d%s" % [Settings.player_name(), me.rank, me.value, unit]
	else:
		_me.text = "You (%s): not on this board yet" % Settings.player_name()


func _row(place: int, r: Dictionary) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	var col := Palette.ACCENT if r.get("you", false) else Palette.TEXT
	var rank := UiTheme.label("#%d" % place, 22, Palette.ACCENT if place == 1 else Palette.TEXT_DIM)
	rank.custom_minimum_size.x = 56
	h.add_child(rank)
	var n := UiTheme.label(str(r.get("name", "?")), 22, col)
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(n)
	h.add_child(UiTheme.label("%d%s" % [int(r.get("value", 0)), " m" if BOARDS[_board][0] == "height" else ""], 22, col))
	return h


func _load_totals() -> void:
	if not Stats.enabled():
		return
	Stats.my_stats(func(ok: bool, reply: Dictionary):
		var p: Variant = reply.get("player")
		if not ok or not is_inside_tree() or not p is Dictionary:
			return
		_totals.text = ("" if Settings.logged_in() else "On this computer: ") + "Solo runs %d  ·  best %d m  ·  online %d played, %d won  ·  %d knock-outs  ·  %d m climbed in all" % [
			p.solo_runs, p.best_solo, p.online_matches, p.online_wins, p.kos, p.total_climb])


func _show_message(text: String) -> void:
	_clear()
	var l := UiTheme.label(text, 20, Palette.TEXT_DIM)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_list.add_child(l)


func _clear() -> void:
	for c in _list.get_children():
		c.queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if sub_open:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		Sfx.play("ui_back")
		closed.emit()
	elif event.is_action_pressed("ui_tab_next") or event.is_action_pressed("ui_tab_prev"):
		get_viewport().set_input_as_handled()
		Sfx.play("ui_move")
		_set_board(1 - _board)
