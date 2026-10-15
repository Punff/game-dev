class_name LobbySlot
extends PanelContainer

## One player card in the lobby.

var _info: PlayerInfo
var _preview := Control.new()
var _name := UiTheme.title("", 34)
var _device := UiTheme.label("", 16)
var _colour := UiTheme.label("", 20, Palette.TEXT)
var _state := UiTheme.label("", 22)
var _controls := UiTheme.label("", 15)
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
	for l: Label in [_name, _device, _colour, _state, _controls]:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(l)


func show_player(info: PlayerInfo) -> void:
	_info = info
	if info == null:
		add_theme_stylebox_override("panel", UiTheme.box(Color(Palette.INK, 0.6), Color(Palette.PAPER_DIM, 0.5), 2, 0, Vector2(16, 16), 6))
		_name.text = "OPEN"
		_name.add_theme_color_override("font_color", Palette.TEXT_DIM)
		_device.text = ""
		_colour.text = ""
		_state.text = "Join with"
		_state.add_theme_color_override("font_color", Palette.TEXT_DIM)
		var lines: Array[String] = []
		if PlayerManager.find_by_device(Settings.DEVICE_KB_A) == null:
			lines.append("%s / Space  (WASD side)" % Settings.action_hint("kb_a", "jump"))
		if PlayerManager.find_by_device(Settings.DEVICE_KB_B) == null:
			lines.append("%s  (Arrows side)" % Settings.action_hint("kb_b", "jump"))
		lines.append("(A) on a gamepad")
		_controls.text = "\n".join(lines)
	else:
		var border := Palette.GOOD if info.is_ready else info.color
		var sb := UiTheme.box(Color(Palette.INK, 0.94), border, 5 if info.is_ready else 3, 0, Vector2(16, 16), 10)
		sb.border_width_top = 14
		add_theme_stylebox_override("panel", sb)
		_name.text = info.display_name
		_name.add_theme_color_override("font_color", info.color)
		_device.text = info.device_label()
		_colour.text = Palette.PLAYER_COLOR_NAMES[info.color_index] if info.is_ready else "<  %s  >" % Palette.PLAYER_COLOR_NAMES[info.color_index]
		_state.text = "READY!" if info.is_ready else "Press Jump to ready"
		_state.add_theme_color_override("font_color", Palette.GOOD if info.is_ready else Palette.TEXT_DIM)
		_controls.text = _control_summary(info)
	_preview.queue_redraw()


func _control_summary(info: PlayerInfo) -> String:
	var p := Settings.profile_for_device(info.device_id)
	var h := func(a): return Settings.action_hint(p, a).replace("L-Stick ", "").replace("D-Pad ", "")
	if p == "pad":
		return "Move L-Stick · Jump %s\nCharge %s · Field %s\nShock %s · Aim L-Stick" % [
			h.call("jump"), h.call("charge"), h.call("gravity"), h.call("shockwave")]
	return "Move %s %s · Jump %s\nCharge %s · Field %s\nShock %s · Aim %s %s" % [
		h.call("left"), h.call("right"), h.call("jump"), h.call("charge"),
		h.call("gravity"), h.call("shockwave"), h.call("up"), h.call("down")]


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
