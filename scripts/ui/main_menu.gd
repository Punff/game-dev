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
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 20
	col.add_child(spacer)

	var list: Array = []
	for entry in [["Play", _on_play], ["How to play", _on_help], ["Settings", open_settings], ["Quit", func(): get_tree().quit()]]:
		var b := UiTheme.button(entry[0], 300)
		b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(entry[1])
		col.add_child(b)
		list.append(b)
	if Settings.is_web():
		list[-1].visible = false
	MenuBase.link_vertical(list)

	var foot := UiTheme.label("v%s" % ProjectSettings.get_setting("application/config/version"), 16, Palette.SMOKE)
	foot.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	foot.position = Vector2(90, -40)
	add_child(foot)
	focus_first()


func _on_play() -> void:
	MatchManager.to_lobby()


func _on_help() -> void:
	remember_focus()
	var h := HelpScreen.new()
	add_child(h)
	sub_open = true
	h.closed.connect(func():
		h.queue_free()
		sub_open = false
		restore_focus())
