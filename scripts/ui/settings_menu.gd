class_name SettingsMenu
extends MenuBase

## Settings overlay usable from the main menu and the pause menu.
## Two tabs (General / Controls), fully navigable with keyboard or gamepad,
## with in-place key / button remapping per input profile.

const LISTEN_GRACE := 0.25
const LISTEN_TIMEOUT := 6.0

var _tab := 0
var _tab_buttons: Array[Button] = []
var _body: VBoxContainer
var _scroll: ScrollContainer
var _hint: Label
var _back: Button
var _reset: Button
var _profile_idx := 0

# Rebinding state
var _listen: Dictionary = {}
var _listen_time := 0.0


func _ready() -> void:
	build_overlay(0.7, 820)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	var title := UiTheme.title("settings", 40)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	for i in 2:
		var tb := UiTheme.button(["General", "Controls"][i], 150)
		tb.toggle_mode = true
		tb.pressed.connect(_set_tab.bind(i))
		header.add_child(tb)
		_tab_buttons.append(tb)
	content.add_child(header)
	content.add_child(HSeparator.new())

	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size = Vector2(0, 470)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	content.add_child(_scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 10)
	_scroll.add_child(_body)

	content.add_child(HSeparator.new())
	var footer := HBoxContainer.new()
	_hint = UiTheme.label("", 16)
	_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	footer.add_child(_hint)
	_reset = UiTheme.button("Reset Profile", 200)
	_reset.pressed.connect(func(): Settings.reset_bindings(_profile()))
	footer.add_child(_reset)
	_back = UiTheme.button("Back", 160)
	_back.pressed.connect(_close)
	footer.add_child(_back)
	content.add_child(footer)

	SignalBus.bindings_changed.connect(_refresh_bindings)
	_set_tab(0)


func _close() -> void:
	Settings.save_settings()
	closed.emit()


func _set_tab(i: int) -> void:
	_tab = i
	_listen = {}
	_reset.visible = i == 1
	for k in _tab_buttons.size():
		_tab_buttons[k].button_pressed = k == i
	for c in _body.get_children():
		c.queue_free()
	if i == 0:
		_build_general()
	else:
		_build_controls()
	_scroll.scroll_vertical = 0


# ── General ──────────────────────────────────

func _build_general() -> void:
	_hint.text = "LB / RB or Q / E switch tabs"
	var focusables: Array = []
	if Sfx.has_sounds():
		focusables.append(_slider_row("Master Volume", "master_volume", 0.0, 1.0))
		focusables.append(_slider_row("Sound Effects", "sfx_volume", 0.0, 1.0))
	focusables.append(_check_row("Fullscreen", "fullscreen", func(_on): Settings.toggle_fullscreen()))
	if not Settings.is_web():
		focusables.append(_check_row("VSync", "vsync"))
	focusables.append(_slider_row("Screen Shake", "screen_shake", 0.0, 1.0))
	focusables.append(_check_row("Reduced Effects (faster)", "reduced_effects"))
	focusables.append(_check_row("Show FPS", "show_fps"))
	focusables.append(_slider_row("Stick Deadzone", "deadzone", 0.1, 0.6))
	focusables.append(_check_row("Controller Rumble", "rumble"))
	_finish_focus(focusables)


func _row(label_text: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	h.custom_minimum_size.y = 46
	var l := UiTheme.label(label_text, 22, Palette.TEXT)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	_body.add_child(h)
	# Highlight the label of whichever control in the row has focus.
	h.child_entered_tree.connect(func(c: Node):
		if c is Control and c != l:
			c.focus_entered.connect(func(): l.add_theme_color_override("font_color", Palette.ACCENT))
			c.focus_exited.connect(func(): l.add_theme_color_override("font_color", Palette.TEXT)))
	return h


func _slider_row(label_text: String, key: String, lo: float, hi: float) -> Control:
	var h := _row(label_text)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = 0.05
	s.value = Settings.get_value(key)
	s.custom_minimum_size = Vector2(300, 32)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.focus_mode = Control.FOCUS_ALL
	var pct := UiTheme.label("%d%%" % roundi(s.value * 100), 20, Palette.TEXT_DIM)
	pct.custom_minimum_size.x = 64
	pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	s.value_changed.connect(func(v):
		pct.text = "%d%%" % roundi(v * 100)
		Settings.set_value(key, v, false)
		if key == "sfx_volume" or key == "master_volume":
			Sfx.play("ui_move"))
	s.drag_ended.connect(func(_c): Settings.save_settings())
	s.focus_exited.connect(Settings.save_settings)
	s.focus_entered.connect(func(): Sfx.play("ui_move"))
	h.add_child(s)
	h.add_child(pct)
	return s


func _check_row(label_text: String, key: String, custom: Callable = Callable()) -> Control:
	var h := _row(label_text)
	var b := UiTheme.button("On" if Settings.get_value(key) else "Off", 140)
	b.custom_minimum_size.y = 44
	b.toggle_mode = true
	# "On" is shown in green so it can't be mistaken for keyboard focus.
	var on_style := UiTheme.box(Palette.GOOD.darkened(0.45), Palette.GOOD.darkened(0.1), 2)
	b.add_theme_stylebox_override("pressed", on_style)
	b.add_theme_stylebox_override("hover_pressed", on_style)
	b.add_theme_color_override("font_pressed_color", Palette.TEXT)
	b.add_theme_color_override("font_hover_pressed_color", Palette.TEXT)
	b.button_pressed = Settings.get_value(key)
	b.toggled.connect(func(on):
		b.text = "On" if on else "Off"
		if custom.is_valid():
			custom.call(on)
		else:
			Settings.set_value(key, on))
	h.add_child(b)
	return b


# ── Controls ─────────────────────────────────

var _bind_buttons: Dictionary = {}   # "action:slot" -> Button
var _profile_button: Button


func _profile() -> String:
	return Settings.PROFILES[_profile_idx]


func _build_controls() -> void:
	_bind_buttons.clear()
	var focusables: Array = []
	var h := _row("Input Profile")
	_profile_button = UiTheme.button("", 380)
	_profile_button.pressed.connect(func(): _cycle_profile(1))
	_profile_button.gui_input.connect(func(ev: InputEvent):
		if ev.is_action_pressed("ui_left"):
			_cycle_profile(-1)
			_profile_button.accept_event()
		elif ev.is_action_pressed("ui_right"):
			_cycle_profile(1)
			_profile_button.accept_event())
	h.add_child(_profile_button)
	focusables.append(_profile_button)

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 6)
	_body.add_child(grid)
	var rows: Array = []
	for action in Settings.ACTIONS:
		var l := UiTheme.label(Settings.ACTION_LABELS[action], 20, Palette.TEXT)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(l)
		var row: Array = []
		for slot in Settings.SLOTS:
			var b := UiTheme.button("", 200)
			b.custom_minimum_size.y = 42
			b.add_theme_font_size_override("font_size", 18)
			b.pressed.connect(_start_listen.bind(action, slot, b))
			grid.add_child(b)
			_bind_buttons["%s:%d" % [action, slot]] = b
			row.append(b)
		rows.append(row)

	var reset := _reset
	# Focus graph: profile -> grid (2 columns) -> reset -> back
	var first_row: Array = rows[0]
	var last_row: Array = rows[-1]
	_profile_button.focus_neighbor_bottom = _profile_button.get_path_to(first_row[0])
	for r in rows.size():
		for c in 2:
			var b: Button = rows[r][c]
			b.focus_neighbor_top = b.get_path_to(rows[r - 1][c] if r > 0 else _profile_button)
			b.focus_neighbor_bottom = b.get_path_to(rows[r + 1][c] if r < rows.size() - 1 else (reset if c == 0 else _back))
			b.focus_neighbor_left = b.get_path_to(rows[r][1 - c])
			b.focus_neighbor_right = b.get_path_to(rows[r][1 - c])
	reset.focus_neighbor_top = reset.get_path_to(last_row[0])
	reset.focus_neighbor_bottom = reset.get_path_to(_profile_button)
	reset.focus_neighbor_right = reset.get_path_to(_back)
	reset.focus_neighbor_left = reset.get_path_to(_back)
	_back.focus_neighbor_top = _back.get_path_to(last_row[1])
	_back.focus_neighbor_bottom = _back.get_path_to(_profile_button)
	_back.focus_neighbor_left = _back.get_path_to(reset)
	_back.focus_neighbor_right = _back.get_path_to(reset)
	_profile_button.focus_neighbor_top = _profile_button.get_path_to(reset)
	_refresh_bindings()
	_profile_button.grab_focus.call_deferred()


func _cycle_profile(step: int) -> void:
	_profile_idx = posmod(_profile_idx + step, Settings.PROFILES.size())
	Sfx.play("ui_move")
	_refresh_bindings()


func _refresh_bindings() -> void:
	if _tab != 1 or not is_instance_valid(_profile_button):
		return
	_profile_button.text = "<  %s  >" % Settings.PROFILE_LABELS[_profile()]
	for action in Settings.ACTIONS:
		for slot in Settings.SLOTS:
			var b: Button = _bind_buttons["%s:%d" % [action, slot]]
			b.text = Settings.binding_label(Settings.bindings[_profile()][action][slot])
	_hint.text = _controls_hint()


func _controls_hint() -> String:
	if _profile() == "pad":
		return "Select a slot, then press a button or push a stick/trigger. Esc / wait to cancel. All gamepads share this profile."
	return "Select a slot, then press a key. Esc cancels, Backspace clears the slot."


func _start_listen(action: String, slot: int, b: Button) -> void:
	_listen = {"action": action, "slot": slot, "button": b}
	_listen_time = 0.0
	b.text = "Press..."
	_hint.text = "Waiting for input for \"%s\"..." % Settings.ACTION_LABELS[action]


func _stop_listen() -> void:
	var b: Button = _listen.get("button")
	_listen = {}
	_refresh_bindings()
	if is_instance_valid(b):
		b.grab_focus()


func _process(delta: float) -> void:
	if _listen.is_empty():
		return
	_listen_time += delta
	if _listen_time > LISTEN_TIMEOUT:
		_stop_listen()
	else:
		var b: Button = _listen.button
		b.text = "Press... %d" % ceili(LISTEN_TIMEOUT - _listen_time)


func _input(event: InputEvent) -> void:
	if _listen.is_empty():
		return
	# Swallow everything while listening so menus don't react.
	get_viewport().set_input_as_handled()
	if _listen_time < LISTEN_GRACE:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_ESCAPE:
			Sfx.play("ui_back")
			_stop_listen()
			return
		if event.physical_keycode in [KEY_BACKSPACE, KEY_DELETE] and _profile() != "pad":
			Settings.set_binding(_profile(), _listen.action, _listen.slot, {})
			_stop_listen()
			return
	var binding := Settings.event_to_binding(event, _profile() == "pad")
	if binding.is_empty():
		return
	Settings.set_binding(_profile(), _listen.action, _listen.slot, binding)
	Sfx.play("ui_select")
	_stop_listen()


func _unhandled_input(event: InputEvent) -> void:
	if not _listen.is_empty():
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		Sfx.play("ui_back")
		_close()
	elif event.is_action_pressed("ui_tab_next") or event.is_action_pressed("ui_tab_prev"):
		get_viewport().set_input_as_handled()
		Sfx.play("ui_move")
		_set_tab(1 - _tab)
		if _tab == 0:
			focus_first_in_body.call_deferred()


func focus_first_in_body() -> void:
	for c in _body.find_children("*", "Control", true, false):
		if c.focus_mode == Control.FOCUS_ALL and c.is_visible_in_tree():
			c.grab_focus()
			return


func _finish_focus(focusables: Array) -> void:
	focusables.append(_back)
	MenuBase.link_vertical(focusables)
	focusables[0].grab_focus.call_deferred()
