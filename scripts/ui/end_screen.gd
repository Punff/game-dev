class_name EndScreen
extends CanvasLayer

## Results: winner banner, standings with heights, rematch.

var _menu := MenuBase.new()
var _votes: Label        # online: rematch tally
var _rematch: Button
var _rank: Label         # solo: leaderboard place, once the server answers


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	SignalBus.match_ended.connect(_show)


func _show(results: Dictionary) -> void:
	add_child(_menu)
	_menu.build_overlay(0.55, 520)
	var c := _menu.content
	var standings: Array = results.standings
	var winner: PlayerInfo = PlayerManager.players.get(results.winner)

	var headline: Label
	var crown: Crown = null
	var rows: Array[Control] = []
	if results.solo:
		var info: PlayerInfo = standings[0]
		headline = UiTheme.title("%d m" % info.max_height, 72, Palette.PAPER)
		c.add_child(headline)
		var sub := "New best" if results.new_record else "Best: %d m" % int(Settings.get_value("best_height"))
		c.add_child(_centered(UiTheme.label(sub, 24, Palette.GOOD if results.new_record else Palette.TEXT_DIM)))
		if Stats.enabled():
			_show_rank(c)
	else:
		if winner:
			crown = Crown.new(64.0)
			crown.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			c.add_child(crown)
		headline = UiTheme.title("P%d wins" % winner.player_id if winner else "draw", 60, winner.color if winner else Palette.PAPER)
		c.add_child(headline)
		c.add_child(_centered(UiTheme.label("Survived %s" % _fmt_time(results.time), 20)))
		var list := VBoxContainer.new()
		list.add_theme_constant_override("separation", 6)
		var place := 1
		for info: PlayerInfo in standings:
			var row := _row(place, info, winner != null and info == winner)
			list.add_child(row)
			rows.append(row)
			place += 1
		c.add_child(list)
		if results.new_record:
			c.add_child(_centered(UiTheme.label("New height record: %d m!" % results.best_height, 20, Palette.GOOD)))

	var spacer := Control.new()
	spacer.custom_minimum_size.y = 6
	c.add_child(spacer)
	var buttons: Array
	if Net.is_online():
		# A rematch starts once everyone still here has voted for one.
		_votes = _centered(UiTheme.label("", 20, Palette.TEXT_DIM))
		c.add_child(_votes)
		_rematch = _menu.add_button("Rematch", func(): Net.ask_rematch(not _voted()))
		buttons = [
			_rematch,
			_menu.add_button("Lobby (everyone)", func(): Net.ask_lobby()),
			_menu.add_button("Leave", func():
				Net.leave()
				MatchManager.to_menu()),
		]
		Net.rematch_changed.connect(_show_votes)
		Net.roster_changed.connect(_show_votes)
		_show_votes()
	else:
		buttons = [
			_menu.add_button("Rematch", func(): MatchManager.start_match()),
			_menu.add_button("Change Players", func(): MatchManager.to_lobby()),
			_menu.add_button("Main Menu", func(): MatchManager.to_menu()),
		]
	MenuBase.link_vertical(buttons)
	visible = true
	get_tree().paused = true
	_menu.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(_menu, "modulate:a", 1.0, 0.25)
	# The winner is stamped on, then the standings unfold top to bottom.
	UiFx.stamp.call_deferred(headline, 1.7, -7.0, 0.1)
	if crown:
		UiFx.stamp.call_deferred(crown, 2.4, 14.0, 0.3)
	for i in rows.size():
		UiFx.reveal.call_deferred(rows[i], 0.3 + i * 0.09)
	# Players are usually still mashing jump (= Space / A = accept) when the
	# match ends: hold the buttons a moment so nobody skips the results.
	for b: Button in buttons:
		b.disabled = true
	await get_tree().create_timer(0.6).timeout
	for b: Button in buttons:
		b.disabled = false
	_menu.focus_first()


## Fills in once the server has the run (Telemetry uploads it at match end).
func _show_rank(c: Control) -> void:
	_rank = _centered(UiTheme.label("", 20, Palette.ACCENT))
	c.add_child(_rank)
	Stats.match_submitted.connect(_on_rank, CONNECT_ONE_SHOT)


func _on_rank(reply: Dictionary) -> void:
	if is_instance_valid(_rank) and reply.has("rank"):
		_rank.text = "#%d on the leaderboard (best %d m)" % [reply.rank, reply.best]
		UiFx.bump(_rank, 0.15)


func _voted() -> bool:
	var me := Net.local_info()
	return me != null and me.player_id in Net.rematch_votes


func _show_votes() -> void:
	if _votes == null or not is_instance_valid(_votes):
		return
	var total := PlayerManager.players.size()
	var n := Net.rematch_votes.size()
	_votes.text = "Rematch: %d of %d" % [n, total] if n > 0 else "Rematch starts when everyone picks it"
	_votes.add_theme_color_override("font_color", Palette.GOOD if n > 0 else Palette.TEXT_DIM)
	_rematch.text = "Cancel rematch" if _voted() else "Rematch"
	if n > 0:
		UiFx.bump(_votes, 0.15)


func _row(place: int, info: PlayerInfo, won := false) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	var medal := UiTheme.label("#%d" % place, 26, Palette.ACCENT if place == 1 else Palette.TEXT_DIM)
	medal.custom_minimum_size.x = 56
	h.add_child(medal)
	var dot := Panel.new()   # a little ball, like the one they played
	dot.add_theme_stylebox_override("panel", UiTheme.box(info.color, Palette.INK, 3, 13))
	dot.custom_minimum_size = Vector2(26, 26)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(dot)
	var name := UiTheme.label("P%d" % info.player_id, 26, info.color)
	h.add_child(name)
	if won:
		var c := Crown.new(30.0)
		c.bob = false
		c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(c)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(gap)
	h.add_child(UiTheme.label("%d m" % info.max_height, 26, Palette.TEXT))
	return h


func _centered(l: Label) -> Label:
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


static func _fmt_time(t: float) -> String:
	return "%d:%02d" % [int(t) / 60, int(t) % 60]
