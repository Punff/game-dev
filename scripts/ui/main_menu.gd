extends MenuBase

## Title screen.


func _ready() -> void:
	MatchManager.state = MatchManager.State.MENU
	var bg := Background.new()
	bg.auto_scroll = 30.0
	add_child(bg)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 90)
	add_child(margin)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 12)
	margin.add_child(col)

	var title := UiTheme.title("ultimate cakum pakum", 72, Palette.PAPER)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	col.add_child(title)
	var tagline := UiTheme.label("Climb. Wreck the route behind you. Outlast the slag.", 22, Palette.MUSTARD)
	col.add_child(tagline)
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 24
	col.add_child(spacer)

	var list: Array = []
	for entry in [["Play", _on_play], ["Online", _on_online], ["How to play", _on_help], ["Settings", open_settings], ["Quit", func(): get_tree().quit()]]:
		var b := UiTheme.button(entry[0], 300)
		b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(entry[1])
		col.add_child(b)
		list.append(b)
	if Settings.is_web():
		list[-1].visible = false
	MenuBase.link_vertical(list)

	var a := func(act): return UiTheme.key("kb_a", act)
	var foot := UiTheme.hint("%s %s or [Up] [Down] choose     [Enter] / %s select     v%s" % [
		a.call("up"), a.call("down"), "[Space]", ProjectSettings.get_setting("application/config/version")], 16, Palette.PAPER_DIM, false)
	foot.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	foot.position = Vector2(90, -64)
	add_child(foot)
	focus_first()


func _on_play() -> void:
	MatchManager.to_lobby()


func _on_online() -> void:
	Net.status = ""
	MatchManager.state = MatchManager.State.LOBBY
	MatchManager.goto(Net.ONLINE_LOBBY)


func _on_help() -> void:
	MatchManager.goto(Sandbox.SCENE)
