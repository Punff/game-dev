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
		add_theme_stylebox_override("panel", UiTheme.box(Color(Palette.PANEL, 0.55), Color(Palette.LINE, 0.6), 2, 18, Vector2(16, 16)))
		_name.text = "OPEN"
		_name.add_theme_color_override("font_color", Palette.TEXT_DIM)
		_device.text = ""
		_colour.text = ""
		_state.text = "Join with"
		_state.add_theme_color_override("font_color", Palette.TEXT_DIM)
		_controls.text = "%s / Space  (WASD side)\n%s  (Arrows side)\n(A) on a gamepad" % [
			Settings.action_hint("kb_a", "jump"), Settings.action_hint("kb_b", "jump")]
	else:
		var border := Palette.GOOD if info.is_ready else info.color
		add_theme_stylebox_override("panel", UiTheme.box(Palette.PANEL, border, 4 if info.is_ready else 3, 18, Vector2(16, 16)))
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
	var h := func(a): return Settings.action_hint(p, a)
	return "Move %s %s · Jump %s\nCharge %s · Field %s\nShock %s · Aim %s %s" % [
		h.call("left"), h.call("right"), h.call("jump"), h.call("charge"),
		h.call("gravity"), h.call("shockwave"), h.call("up"), h.call("down")]


func _process(delta: float) -> void:
	_t += delta
	_preview.queue_redraw()


func _draw_preview() -> void:
	var c := Vector2(_preview.size.x * 0.5, 56)
	if _info == null:
		var a := 0.35 + 0.2 * sin(_t * 3.0)
		_preview.draw_arc(c, 30, 0, TAU, 40, Color(Palette.TEXT_DIM, a), 3.0, true)
		_preview.draw_line(c + Vector2(-12, 0), c + Vector2(12, 0), Color(Palette.TEXT_DIM, a), 4.0)
		_preview.draw_line(c + Vector2(0, -12), c + Vector2(0, 12), Color(Palette.TEXT_DIM, a), 4.0)
		return
	var bounce := absf(sin(_t * (5.0 if _info.is_ready else 2.5))) * (22.0 if _info.is_ready else 8.0)
	var p := c - Vector2(0, bounce)
	_preview.draw_circle(c + Vector2(0, 34), 26 - bounce * 0.3, Color(0, 0, 0, 0.25))
	_preview.draw_circle(p, 34, Palette.BG_DEEP)
	_preview.draw_circle(p, 30, _info.color)
	_preview.draw_circle(p + Vector2(-9, -11), 10, Color(1, 1, 1, 0.25))
	for ex in [-10.0, 10.0]:
		_preview.draw_rect(Rect2(p + Vector2(ex - 4, -8), Vector2(8, 12)), Palette.BG_DEEP)
