class_name SettingsPage
extends UiPage

## Settings, on the main menu and from Pause (in a floating sleeve).
## Values live in Settings; this page only shows and edits them, and saves
## when you leave it.

var _profile_idx := 0
var _binds: Array[UiKeyBind] = []


func _init() -> void:
	title = "Settings"


func build() -> void:
	tabs = UiTabs.new()
	tabs.add_tab("Audio", _build_audio)
	tabs.add_tab("Display", _build_display)
	tabs.add_tab("Gameplay", _build_gameplay)
	tabs.add_tab("Controls", _build_controls)
	tabs.add_tab("Data", _build_data)
	add_child(tabs)
	tabs.show_tab(0, false)
	SignalBus.bindings_changed.connect(_redraw_binds)


func left() -> void:
	Settings.save_settings()


func hints() -> String:
	if tabs.tab_name() == "Controls":
		return "%s tabs     %s rebind     [Backspace] clear     %s back" % [UiHintBar.tab_keys(), UiHintBar.accept_key(), UiHintBar.back_key()]
	return super()


func _finish(body: VBoxContainer, rows: Array) -> void:
	var list: Array = []
	for r in rows:
		body.add_child(r)
		if r is UiRow:
			list.append(r.control)
	UiNav.link_vertical(list)


func _build_audio(body: VBoxContainer) -> void:
	var rows: Array = [UiRow.slider("Master volume", "master_volume"), UiRow.slider("Music", "music_volume")]
	if Sfx.has_sounds():
		rows.append(UiRow.slider("Sound effects", "sfx_volume"))
	_finish(body, rows)


func _build_display(body: VBoxContainer) -> void:
	var rows: Array = [UiRow.toggle("Fullscreen", "fullscreen", func(_on): Settings.toggle_fullscreen())]
	if not Settings.is_web():
		rows.append(UiRow.toggle("VSync", "vsync"))
	rows.append(UiRow.slider("Screen shake", "screen_shake"))
	rows.append(UiRow.toggle("Reduced effects (faster)", "reduced_effects"))
	rows.append(UiRow.toggle("Show FPS", "show_fps"))
	_finish(body, rows)


func _build_gameplay(body: VBoxContainer) -> void:
	_finish(body, [UiRow.slider("Stick deadzone", "deadzone", 0.1, 0.6), UiRow.toggle("Controller rumble", "rumble")])


func _build_data(body: VBoxContainer) -> void:
	_finish(body, [UiRow.toggle("Share stats online", "share_stats")])
	body.add_child(UiPage.notes("Sends your finished matches (heights, wins, knock-outs) to the leaderboard server. Off means no leaderboards and no ranking. Your password is never stored on this computer."))


# ── Controls ─────────────────────────────────

func _profile() -> String:
	return Settings.PROFILES[_profile_idx]


func _build_controls(body: VBoxContainer) -> void:
	_binds.clear()
	var labels: Array = []
	for p in Settings.PROFILES:
		labels.append(Settings.PROFILE_LABELS[p])
	var profile_row := UiRow.cycler("Input profile", labels, _profile_idx, func(i: int):
		_profile_idx = i
		_rebuild_controls())
	body.add_child(profile_row)
	var grid: Array = [[profile_row.control]]
	for action in Settings.ACTIONS:
		var row := UiRow.new(Settings.ACTION_LABELS[action])
		var cells: Array = []
		for slot in Settings.SLOTS:
			var b := UiKeyBind.new(_profile(), action, slot)
			row.add(b)
			_binds.append(b)
			cells.append(b)
		body.add_child(row)
		grid.append(cells)
	var reset := UiTheme.button("Reset %s" % ("gamepad" if _profile() == "pad" else "this keyboard half"), 0)
	reset.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	reset.pressed.connect(func(): Settings.reset_bindings(_profile()))
	body.add_child(reset)
	grid.append([reset])
	body.add_child(UiPage.notes(
		"Press a slot, then a button or push a stick/trigger. All gamepads share this profile." if _profile() == "pad"
		else "Press a slot, then the new key. Esc cancels, Backspace clears the slot."))
	UiNav.link_grid(grid)


## Swap the profile without losing focus from the profile picker.
func _rebuild_controls() -> void:
	tabs.show_tab(tabs.index, false)
	var c := UiNav.first_focusable(tabs.body)
	if c:
		c.grab_focus.call_deferred()


func _redraw_binds() -> void:
	for b in _binds:
		if is_instance_valid(b):
			b.queue_redraw()
