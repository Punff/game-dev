extends Control

## Join screen. Each keyboard half and every gamepad can join as its own
## player, pick a colour, and ready up. When everyone is ready a short
## countdown starts the match.

const AUTO_START := 3.0

var _slots: Array = []
var _status: Label
var _countdown := -1.0
var _stick_latch: Dictionary = {}   # device -> last stick direction, for colour cycling


func _ready() -> void:
	MatchManager.state = MatchManager.State.LOBBY
	var bg := Background.new()
	bg.auto_scroll = 25.0
	add_child(bg)

	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 22)
	add_child(col)
	col.add_child(UiTheme.title("players", 56, Palette.PAPER))

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 18)
	col.add_child(row)
	for i in PlayerManager.MAX_PLAYERS:
		var slot := LobbySlot.new()
		row.add_child(slot)
		_slots.append(slot)

	_status = UiTheme.label("", 26, Palette.TEXT)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_status)

	var help := UiTheme.label("Jump: join / ready    Left / Right: colour    Down or B: back out    Enter / Start: go!    Esc: menu", 17, Palette.TEXT_DIM)
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(help)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 16)
	col.add_child(buttons)
	for entry in [["Back", _back], ["Start", _try_start]]:
		var b := UiTheme.button(entry[0], 180)
		b.focus_mode = Control.FOCUS_NONE   # mouse only: A/Enter are join keys here
		b.pressed.connect(entry[1])
		buttons.add_child(b)

	SignalBus.player_joined.connect(func(_a, _b): _refresh())
	SignalBus.player_left.connect(func(_a): _refresh())
	_refresh()


func _refresh() -> void:
	var infos := PlayerManager.sorted_players()
	for i in _slots.size():
		_slots[i].show_player(infos[i] if i < infos.size() else null)
	var all_ready := not infos.is_empty() and infos.all(func(p): return p.is_ready)
	if all_ready and _countdown < 0.0:
		_countdown = AUTO_START
	elif not all_ready:
		_countdown = -1.0
	_update_status()


func _update_status() -> void:
	var infos := PlayerManager.sorted_players()
	if infos.is_empty():
		_status.text = "Press W / Space, Up, or (A) on a gamepad to join"
		_status.add_theme_color_override("font_color", Palette.TEXT)
	elif _countdown >= 0.0:
		_status.text = "Starting in %d..." % ceili(_countdown)
		_status.add_theme_color_override("font_color", Palette.GOOD)
	else:
		var waiting := infos.filter(func(p): return not p.is_ready).size()
		_status.text = "Waiting for %d player%s to ready up" % [waiting, "" if waiting == 1 else "s"]
		_status.add_theme_color_override("font_color", Palette.TEXT)


func _process(delta: float) -> void:
	if _countdown >= 0.0:
		var before := ceili(_countdown)
		_countdown -= delta
		if ceili(_countdown) != before and _countdown > 0.0:
			Sfx.play("count", -6.0)
		_update_status()
		if _countdown <= 0.0:
			_start()


func _try_start() -> void:
	var infos := PlayerManager.sorted_players()
	if infos.is_empty():
		return
	for p in infos:
		p.is_ready = true
	_start()


func _start() -> void:
	set_process(false)
	Sfx.play("go")
	MatchManager.start_match()


func _back() -> void:
	Sfx.play("ui_back")
	PlayerManager.clear()
	MatchManager.to_menu()


# ── Input ────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		if not event.pressed or event.echo:
			return
		if event.physical_keycode == KEY_ESCAPE:
			_back()
			return
		if event.physical_keycode in [KEY_ENTER, KEY_KP_ENTER] and _all_ready():
			_try_start()
			return
		for device in [Settings.DEVICE_KB_A, Settings.DEVICE_KB_B]:
			var cmd := _kb_command(device, event)
			if cmd != "":
				_command(device, cmd)
				get_viewport().set_input_as_handled()
				return
		if event.physical_keycode in [KEY_ENTER, KEY_KP_ENTER]:
			_command(Settings.DEVICE_KB_A, "confirm")
	elif event is InputEventJoypadButton and event.pressed:
		match event.button_index:
			JOY_BUTTON_A: _command(event.device, "confirm")
			JOY_BUTTON_B: _command(event.device, "back")
			JOY_BUTTON_START:
				if _all_ready():
					_try_start()
				else:
					_command(event.device, "confirm")
			JOY_BUTTON_DPAD_LEFT: _command(event.device, "prev")
			JOY_BUTTON_DPAD_RIGHT: _command(event.device, "next")
			JOY_BUTTON_Y: _command(event.device, "next")
	elif event is InputEventJoypadMotion and event.axis == JOY_AXIS_LEFT_X:
		var dir := 0
		if event.axis_value > 0.6:
			dir = 1
		elif event.axis_value < -0.6:
			dir = -1
		if dir != _stick_latch.get(event.device, 0):
			_stick_latch[event.device] = dir
			if dir != 0:
				_command(event.device, "next" if dir > 0 else "prev")


func _all_ready() -> bool:
	var infos := PlayerManager.sorted_players()
	return not infos.is_empty() and infos.all(func(p): return p.is_ready)


## Maps a key press to a lobby command using that keyboard half's bindings.
func _kb_command(device: int, event: InputEventKey) -> String:
	var profile := Settings.profile_for_device(device)
	var map := {"jump": "confirm", "left": "prev", "right": "next", "down": "back"}
	for action in map:
		for b in Settings.bindings[profile][action]:
			var ev := Settings.binding_to_event(b)
			if ev and ev.is_match(event, false):
				return map[action]
	if device == Settings.DEVICE_KB_A and event.physical_keycode == KEY_SPACE:
		return "confirm"
	return ""


func _command(device: int, cmd: String) -> void:
	var info := PlayerManager.find_by_device(device)
	match cmd:
		"confirm":
			if info == null:
				if PlayerManager.join(device) > 0:
					Sfx.play("join")
			else:
				info.is_ready = not info.is_ready
				Sfx.play("ui_select" if info.is_ready else "ui_back")
		"back":
			if info == null:
				if device >= 0 and PlayerManager.players.is_empty():
					_back()
				return
			if info.is_ready:
				info.is_ready = false
				Sfx.play("ui_back")
			else:
				PlayerManager.leave(info.player_id)
				Sfx.play("leave")
		"prev", "next":
			if info and not info.is_ready:
				PlayerManager.cycle_color(info.player_id, -1 if cmd == "prev" else 1)
				Sfx.play("ui_move")
				PlayerManager.rumble(info.player_id, 0.2, 0.0, 0.05)
	_refresh()
