class_name LobbySlot
extends PanelContainer

## One player card in the lobby.

## Someone clicked the colour arrows on this card.
signal color_step(info: PlayerInfo, dir: int)

var _info: PlayerInfo
## Online lobby: players join from other computers and ready up with the
## Ready button, so the couch join/ready hints don't apply.
var online := false
var _preview := Control.new()
var _name := UiTheme.title("", 34)
var _device := UiTheme.label("", 16)
var _colour := UiTheme.label("", 20, Palette.TEXT)
var _colour_row := HBoxContainer.new()
var _prev := _arrow("<", -1)
var _next := _arrow(">", 1)
var _state := UiTheme.label("", 22)
var _controls := VBoxContainer.new()
var _t := 0.0


func _ready() -> void:
	custom_minimum_size = Vector2(250, 360)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 8)
	add_child(v)
	_preview.custom_minimum_size = Vector2(0, 96)
	_preview.draw.connect(_draw_preview)
	v.add_child(_preview)
	_colour_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_colour_row.add_theme_constant_override("separation", 10)
	_colour_row.add_child(_prev)
	_colour_row.add_child(_colour)
	_colour_row.add_child(_next)
	_controls.add_theme_constant_override("separation", 5)
	for c: Control in [_name, _device, _colour_row, _state, _controls]:
		if c is Label:
			c.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			c.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(c)


func _arrow(text: String, dir: int) -> Button:
	var b := Button.new()
	b.text = text
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE   # keys/pad cycle colours; this is for the mouse
	b.add_theme_color_override("font_color", Palette.PAPER_DIM)
	b.add_theme_color_override("font_hover_color", Palette.MUSTARD)
	b.pressed.connect(func():
		if _info:
			color_step.emit(_info, dir))
	return b


func show_player(info: PlayerInfo) -> void:
	_info = info
	if info == null:
		add_theme_stylebox_override("panel", UiTheme.box(Color(Palette.INK, 0.6), Palette.SMOKE, 2, 0, Vector2(16, 16)))
		_name.text = "OPEN"
		_name.add_theme_color_override("font_color", Palette.TEXT_DIM)
		_device.text = ""
		_colour_row.visible = false
		_state.text = "Waiting for a player" if online else "Join with"
		_state.add_theme_color_override("font_color", Palette.TEXT_DIM)
		var lines: Array[String] = []
		if not online:
			if PlayerManager.find_by_device(Settings.DEVICE_KB_A) == null:
				lines.append(UiTheme.key("kb_a", "jump") + " or [Space]")
			if PlayerManager.find_by_device(Settings.DEVICE_KB_B) == null:
				lines.append(UiTheme.key("kb_b", "jump"))
			lines.append("[A] on a gamepad")
		_set_controls(lines)
	else:
		var border := Palette.GOOD if info.is_ready else info.color
		add_theme_stylebox_override("panel", UiTheme.box(Color(Palette.INK, 0.94), border, 4 if info.is_ready else 2, 0, Vector2(16, 16)))
		_name.text = info.display_name
		_name.add_theme_color_override("font_color", info.color)
		_device.text = info.device_label()
		_colour_row.visible = true
		_colour.text = Palette.PLAYER_COLOR_NAMES[info.color_index]
		var can_change := info.is_local() and not info.is_ready
		_prev.visible = can_change
		_next.visible = can_change
		_state.text = "READY!" if info.is_ready else ("Not ready" if online else "Press Jump to ready")
		_state.add_theme_color_override("font_color", Palette.GOOD if info.is_ready else Palette.TEXT_DIM)
		var none: Array[String] = []
		_set_controls(_control_summary(info) if info.is_local() else none)
	_preview.queue_redraw()


func _set_controls(lines: Array[String]) -> void:
	for c in _controls.get_children():
		c.queue_free()
	for line in lines:
		_controls.add_child(UiTheme.hint(line, 15))


func _control_summary(info: PlayerInfo) -> Array[String]:
	var p := Settings.profile_for_device(info.device_id)
	if info.device_id == Settings.DEVICE_ANY and Input.get_connected_joypads().is_empty():
		p = "kb_a"   # online player on any device: show the keyboard unless a pad is plugged in
	var k := func(a): return UiTheme.key(p, a)
	if p == "pad":
		return ["[L-Stick] move  %s jump" % k.call("jump"),
			"%s charge  %s field" % [k.call("charge"), k.call("gravity")],
			"%s shock  [L-Stick] aim" % k.call("shockwave")]
	return ["%s %s move  %s jump" % [k.call("left"), k.call("right"), k.call("jump")],
		"%s charge  %s field" % [k.call("charge"), k.call("gravity")],
		"%s shock  %s %s aim" % [k.call("shockwave"), k.call("up"), k.call("down")]]


func _process(delta: float) -> void:
	_t += delta
	_preview.queue_redraw()


func _draw_preview() -> void:
	var c := Vector2(_preview.size.x * 0.5, 54)
	if _info == null:
		var a := 0.4 + 0.25 * sin(_t * 3.0)
		_preview.draw_rect(Rect2(c - Vector2(30, 30), Vector2(60, 60)), Color(Palette.PAPER_DIM, a), false, 3.0)
		_preview.draw_line(c + Vector2(-14, 0), c + Vector2(14, 0), Color(Palette.PAPER_DIM, a), 5.0)
		_preview.draw_line(c + Vector2(0, -14), c + Vector2(0, 14), Color(Palette.PAPER_DIM, a), 5.0)
		return
	var bob := sin(_t * (6.0 if _info.is_ready else 2.0)) * (5.0 if _info.is_ready else 2.0)
	var p := c + Vector2(0, bob)
	_preview.draw_circle(p + Vector2(8, 8), 36, Color(Palette.INK, 0.5))
	_preview.draw_circle(p, 38, Palette.INK)
	_preview.draw_circle(p, 33, _info.color)
	_preview.draw_arc(p + Vector2(4, 4), 26, 0.2, 1.9, 12, _info.color.darkened(0.35), 6.0)
	_preview.draw_line(p + Vector2(-16, -8), p + Vector2(18, -8), Palette.INK, 12.0)
	_preview.draw_line(p + Vector2(-12, -8), p + Vector2(14, -8), Palette.PAPER, 5.0)
