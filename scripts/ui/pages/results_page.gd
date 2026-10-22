class_name ResultsPage
extends UiPage

## The match result in the results screen's sleeve: the height (solo) or the
## winner, the standings, and what next (rematch, lobby, menu). Online, a
## rematch starts once everyone still here has voted for one.
## There's nothing to go back to, so Back does nothing here.

var results: Dictionary
var buttons: Array = []
var _chips := HBoxContainer.new()
var _votes: Label
var _rematch: Button
var _rows: Array[Control] = []
var _place: UiStat


func _init(match_results: Dictionary = {}) -> void:
	results = match_results
	float_size = Vector2(560, 600)
	if results.get("solo", false):
		title = "%d m" % results.standings[0].max_height
	else:
		var winner: PlayerInfo = PlayerManager.players.get(results.get("winner", -1))
		title = "P%d wins" % winner.player_id if winner else "Draw"
		if winner:
			title_color = winner.color


func build() -> void:
	_chips.add_theme_constant_override("separation", 10)
	add_child(_chips)
	if results.solo:
		if results.new_record:
			_chips.add_child(UiChip.new("new best", Palette.GOOD))
		var tiles := HBoxContainer.new()
		tiles.add_theme_constant_override("separation", 10)
		add_child(tiles)
		tiles.add_child(UiStat.new("survived", _fmt_time(results.time)))
		tiles.add_child(UiStat.new("your best", "%d m" % int(Settings.get_value("best_height"))))
		_place = UiStat.new("on the board", "-")
		tiles.add_child(_place)
	else:
		_chips.add_child(UiChip.new("survived %s" % _fmt_time(results.time), Palette.SMOKE))
		if results.new_record:
			_chips.add_child(UiChip.new("height record %d m" % results.best_height, Palette.GOOD))
		_build_standings()

	var gap := Control.new()
	gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(gap)
	if Net.is_online():
		_votes = UiPage.notes("")
		add_child(_votes)
		_rematch = _button("Rematch", func(): Net.ask_rematch(not _voted()))
		_button("Lobby (everyone)", func(): Net.ask_lobby())
		_button("Leave", func():
			Net.leave()
			MatchManager.to_menu())
		Net.rematch_changed.connect(_show_votes)
		Net.roster_changed.connect(_show_votes)
		_show_votes()
	else:
		_button("Rematch", func(): MatchManager.start_match())
		_button("Change players", func(): MatchManager.to_lobby())
		_button("Main menu", func(): MatchManager.to_menu())
	UiNav.link_vertical(buttons)


func entered() -> void:
	for i in _rows.size():
		UiFx.reveal(_rows[i], 0.3 + i * 0.09)


func hints() -> String:
	return "%s select" % UiHintBar.accept_key()


func handle_back() -> bool:
	return true


## The server's answer to a solo run: place on the board.
func show_rank(reply: Dictionary) -> void:
	if reply.has("rank"):
		if _place:
			_place.set_value("#%d" % reply.rank)
	elif not Settings.logged_in():
		add_child(UiPage.notes("Log in from Profile to get ranked."))


func _build_standings() -> void:
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 6)
	add_child(list)
	var winner: PlayerInfo = PlayerManager.players.get(results.get("winner", -1))
	var place := 1
	for info: PlayerInfo in results.standings:
		var row := _row(place, info, winner != null and info == winner)
		list.add_child(row)
		_rows.append(row)
		place += 1


func _row(place: int, info: PlayerInfo, won: bool) -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiTheme.box(Color(Palette.INK_SOFT, 0.8) if won else Color.TRANSPARENT, Palette.SMOKE if won else Color.TRANSPARENT, 2, 0, Vector2(12, 2)))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	p.add_child(h)
	var rank := UiTheme.title("%d" % place, 28, Palette.MUSTARD if place == 1 else Palette.TEXT_DIM)
	rank.custom_minimum_size.x = 36
	h.add_child(rank)
	var ball := BallPortrait.new()
	ball.radius = 14.0
	ball.custom_minimum_size = Vector2(40, 44)
	ball.looks = [BallPortrait.look_for_color(info.color)]
	h.add_child(ball)
	h.add_child(UiTheme.title("P%d" % info.player_id, 28, info.color))
	if won:
		var c := Crown.new(30.0)
		c.bob = false
		c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(c)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(gap)
	h.add_child(UiTheme.label("%d m" % info.max_height, 24, Palette.TEXT))
	return p


func _button(text: String, callback: Callable) -> Button:
	var b := UiTheme.button(text, 0)
	b.pressed.connect(callback)
	add_child(b)
	buttons.append(b)
	return b


func _voted() -> bool:
	var me := Net.local_info()
	return me != null and me.player_id in Net.rematch_votes


func _show_votes() -> void:
	if not is_instance_valid(_votes):
		return
	var n := Net.rematch_votes.size()
	_votes.text = "Rematch: %d of %d" % [n, PlayerManager.players.size()] if n > 0 else "Rematch starts when everyone picks it"
	_votes.add_theme_color_override("font_color", Palette.GOOD if n > 0 else Palette.TEXT_DIM)
	_rematch.text = "Cancel rematch" if _voted() else "Rematch"
	if n > 0:
		UiFx.bump(_votes, 0.15)


static func _fmt_time(t: float) -> String:
	return "%d:%02d" % [int(t) / 60, int(t) % 60]
