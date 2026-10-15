extends MenuBase

## Title screen, laid out like a '70s jazz title card: slanted colour bars,
## big condensed italic type, menu down the left.

var _t := 0.0


func _ready() -> void:
	MatchManager.state = MatchManager.State.MENU
	var bg := Background.new()
	bg.auto_scroll = 30.0
	add_child(bg)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 90)
	margin.add_theme_constant_override("margin_top", 60)
	margin.add_theme_constant_override("margin_bottom", 60)
	add_child(margin)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 10)
	margin.add_child(col)

	var pre := UiTheme.title("ultimate", 40, Palette.PAPER)
	pre.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	col.add_child(pre)
	var title := UiTheme.title("cakum pakum", 128, Palette.MUSTARD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.add_theme_constant_override("outline_size", 22)
	title.add_theme_constant_override("line_spacing", -30)
	col.add_child(title)
	var tag := UiTheme.label("CLIMB.  SABOTAGE.  DON'T TOUCH THE SLAG.", 24, Palette.PAPER)
	tag.add_theme_font_override("font", UiTheme.heavy())
	tag.add_theme_constant_override("outline_size", 8)
	col.add_child(tag)

	var spacer := Control.new()
	spacer.custom_minimum_size.y = 30
	col.add_child(spacer)

	var list: Array = []
	for entry in [["Play", _on_play], ["How to Play", _on_help], ["Settings", open_settings], ["Quit", func(): get_tree().quit()]]:
		var b := UiTheme.button(entry[0], 360)
		b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(entry[1])
		col.add_child(b)
		list.append(b)
	if Settings.is_web():
		list[-1].visible = false
	MenuBase.link_vertical(list)

	var foot := UiTheme.label("v%s   //   KEYBOARD OR GAMEPAD   //   1-4 PLAYERS" % ProjectSettings.get_setting("application/config/version"), 16, Palette.PAPER_DIM)
	foot.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	foot.position = Vector2(90, -40)
	foot.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(foot)
	focus_first()


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	# Slanted bars sweeping behind the title, drifting slowly.
	var vp := size
	var bars := [[Palette.RUST, 0.20, 70.0], [Palette.MUSTARD, 0.30, 22.0], [Palette.BURGUNDY, 0.335, 110.0], [Palette.TEAL, 0.50, 16.0]]
	for i in bars.size():
		var b: Array = bars[i]
		var y: float = vp.y * b[1]
		var h: float = b[2]
		var drift := sin(_t * 0.4 + i) * 30.0
		var slant := 260.0
		var x0 := vp.x * 0.42 + drift
		var pts := PackedVector2Array([Vector2(x0, y), Vector2(vp.x + 50, y), Vector2(vp.x + 50 - h * 0.6, y + h), Vector2(x0 - h * 0.6, y + h)])
		pts[0].x -= slant * (1.0 - float(i) / bars.size())
		draw_colored_polygon(pts, b[0])
		draw_line(pts[0], pts[1], Palette.INK, 3.0)
	# Big ink ball with a visor, like the player, watching from the right.
	var c := Vector2(vp.x * 0.78, vp.y * 0.66 + sin(_t * 1.5) * 6.0)
	draw_circle(c + Vector2(14, 14), 92, Color(Palette.INK, 0.5))
	draw_circle(c, 96, Palette.INK)
	draw_circle(c, 86, Palette.PLAYER_COLORS[0])
	draw_arc(c + Vector2(10, 10), 70, 0.2, 1.9, 20, Palette.PLAYER_COLORS[0].darkened(0.35), 14.0)
	draw_line(c + Vector2(-36, -18), c + Vector2(40, -18), Palette.INK, 26.0)
	draw_line(c + Vector2(-28, -18), c + Vector2(32, -18), Palette.PAPER, 10.0)


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
