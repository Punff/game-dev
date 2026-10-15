extends MenuBase

## Title screen.

var _title_box: Control
var _t := 0.0
var _balls: Array = []


func _ready() -> void:
	MatchManager.state = MatchManager.State.MENU
	var bg := Background.new()
	bg.auto_scroll = 40.0
	add_child(bg)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 10)
	add_child(col)

	_title_box = VBoxContainer.new()
	_title_box.add_theme_constant_override("separation", -26)
	_title_box.add_child(UiTheme.title("ULTIMATE", 54, Palette.TEXT_DIM))
	var t := UiTheme.title("CAKUM PAKUM", 110, Palette.ACCENT)
	t.add_theme_constant_override("outline_size", 18)
	t.add_theme_color_override("font_outline_color", Palette.BG_DEEP)
	_title_box.add_child(t)
	col.add_child(_title_box)
	var tag := UiTheme.label("Climb. Sabotage. Don't touch the lava.", 22, Palette.TEXT)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(tag)

	var spacer := Control.new()
	spacer.custom_minimum_size.y = 26
	col.add_child(spacer)

	var buttons := VBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	buttons.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(buttons)
	var list: Array = []
	for entry in [["Play", _on_play], ["How to Play", _on_help], ["Settings", open_settings], ["Quit", func(): get_tree().quit()]]:
		var b := UiTheme.button(entry[0], 340)
		b.pressed.connect(entry[1])
		buttons.add_child(b)
		list.append(b)
	if Settings.is_web():
		list[-1].visible = false
	MenuBase.link_vertical(list)

	var foot := UiTheme.label("v%s  ·  Keyboard or gamepad  ·  Up to 4 players" % ProjectSettings.get_setting("application/config/version"), 16, Color(Palette.TEXT_DIM, 0.7))
	foot.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	foot.position.y -= 34
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	foot.grow_horizontal = Control.GROW_DIRECTION_BOTH
	add_child(foot)

	# A few decorative bouncing balls in player colours.
	for i in 4:
		_balls.append({"x": randf_range(0.08, 0.92), "phase": randf() * TAU, "c": Palette.PLAYER_COLORS[i]})
	focus_first()


func _process(delta: float) -> void:
	_t += delta
	_title_box.pivot_offset = _title_box.size * 0.5
	_title_box.rotation = sin(_t * 1.3) * 0.015
	queue_redraw()


func _draw() -> void:
	var vp := size
	for b in _balls:
		var h := absf(sin(_t * 2.2 + b.phase))
		var p := Vector2(vp.x * b.x, vp.y - 40 - h * 160)
		var sq := Vector2(1.0 + (1.0 - h) * 0.25, 1.0 - (1.0 - h) * 0.25) if h < 0.15 else Vector2.ONE
		draw_set_transform(p, 0, sq)
		draw_circle(Vector2.ZERO, 16, Palette.BG_DEEP)
		draw_circle(Vector2.ZERO, 13, b.c)
		draw_rect(Rect2(-6, -5, 4, 6), Palette.BG_DEEP)
		draw_rect(Rect2(2, -5, 4, 6), Palette.BG_DEEP)
	draw_set_transform(Vector2.ZERO)


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
