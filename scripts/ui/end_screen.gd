class_name EndScreen
extends CanvasLayer

## Results: winner banner, standings with heights, rematch.

var _menu := MenuBase.new()


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

	if results.solo:
		var info: PlayerInfo = standings[0]
		c.add_child(UiTheme.title("%d m" % info.max_height, 84, Palette.ACCENT))
		var sub := "NEW PERSONAL BEST!" if results.new_record else "Best: %d m" % int(Settings.get_value("best_height"))
		c.add_child(_centered(UiTheme.label(sub, 24, Palette.GOOD if results.new_record else Palette.TEXT_DIM)))
	else:
		if winner:
			c.add_child(UiTheme.title("P%d WINS!" % winner.player_id, 72, winner.color))
		else:
			c.add_child(UiTheme.title("DRAW!", 72, Palette.ACCENT))
		c.add_child(_centered(UiTheme.label("Survived %s" % _fmt_time(results.time), 20)))
		var list := VBoxContainer.new()
		list.add_theme_constant_override("separation", 6)
		var place := 1
		for info: PlayerInfo in standings:
			list.add_child(_row(place, info))
			place += 1
		c.add_child(list)
		if results.new_record:
			c.add_child(_centered(UiTheme.label("New height record: %d m!" % results.best_height, 20, Palette.GOOD)))

	var sign_off := UiTheme.label("SEE YOU SPACE COWBOY...", 26, Palette.PAPER_DIM)
	sign_off.add_theme_font_override("font", UiTheme.title_font())
	sign_off.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	c.add_child(sign_off)
	var buttons := [
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
	_menu.focus_first()


func _row(place: int, info: PlayerInfo) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	var medal := UiTheme.label("#%d" % place, 26, Palette.ACCENT if place == 1 else Palette.TEXT_DIM)
	medal.custom_minimum_size.x = 56
	h.add_child(medal)
	var dot := ColorRect.new()
	dot.color = info.color
	dot.custom_minimum_size = Vector2(26, 26)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(dot)
	var name := UiTheme.label("P%d" % info.player_id, 26, info.color)
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(name)
	h.add_child(UiTheme.label("%d m" % info.max_height, 26, Palette.TEXT))
	return h


func _centered(l: Label) -> Label:
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


static func _fmt_time(t: float) -> String:
	return "%d:%02d" % [int(t) / 60, int(t) % 60]
