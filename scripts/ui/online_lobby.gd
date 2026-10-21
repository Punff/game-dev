extends MenuBase

## Online play: create a room or join one with its code (works between
## browsers anywhere), or connect directly by address (LAN / dedicated
## server). Then the same player cards as the couch lobby. Each computer
## brings one player, using either keyboard half or any gamepad. The match
## starts once everyone is ready.
##
## Before you're in a room this is an ordinary focus-driven menu. Inside a
## room it works like the couch lobby: your game keys or pad ready you up and
## change colour, and the buttons are there for the mouse.

enum View { CONNECT, WAITING, ROOM }

var _title: Label
var _subtitle: Label
var _connect_box := VBoxContainer.new()
var _direct_box := VBoxContainer.new()
var _waiting_box := VBoxContainer.new()
var _room_box := VBoxContainer.new()
var _address := LineEdit.new()
var _code := LineEdit.new()
var _code_panel := PanelContainer.new()
var _code_label: Label
var _host_note: Label
var _status: Label
var _room_status: Label
var _slots: Array = []
var _ready_button: Button
var _cancel: Button
var _menu_list: Array = []
var _direct_list: Array = []
var _view := -1
var _stick_latch := 0


func _ready() -> void:
	MatchManager.state = MatchManager.State.LOBBY
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := Background.new()
	bg.auto_scroll = 25.0
	add_child(bg)

	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 16)
	add_child(col)
	_title = UiTheme.title("online", 56, Palette.PAPER)
	col.add_child(_title)
	_subtitle = UiTheme.label("Play with friends anywhere: one of you creates a room and shares its code.", 19, Palette.TEXT_DIM)
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_subtitle)

	# In a room: its code to share, and a reminder for browser hosts.
	_code_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var code_box := UiTheme.box(Color(Palette.INK, 0.96), Palette.PAPER, 2, 0, Vector2(40, 8), 7)
	code_box.shadow_color = Palette.MUSTARD
	_code_panel.add_theme_stylebox_override("panel", code_box)
	col.add_child(_code_panel)
	var code_col := VBoxContainer.new()
	code_col.add_theme_constant_override("separation", -6)
	_code_panel.add_child(code_col)
	var code_caption := UiTheme.label("Friends join with this code", 16, Palette.TEXT_DIM)
	code_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	code_col.add_child(code_caption)
	_code_label = UiTheme.title("", 52, Palette.MUSTARD)
	code_col.add_child(_code_label)
	_host_note = UiTheme.label("You're hosting: keep this tab open and in front, the match runs in your browser.", 16, Palette.TEXT_DIM)
	_host_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_host_note)

	# Not connected: Create room / code + Join room / Direct connect / Back.
	_connect_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_connect_box.add_theme_constant_override("separation", 12)
	col.add_child(_connect_box)
	var create := _wide_button("Create room", _create_room)
	_connect_box.add_child(create)
	var code_row := HBoxContainer.new()
	code_row.alignment = BoxContainer.ALIGNMENT_CENTER
	code_row.add_theme_constant_override("separation", 12)
	_connect_box.add_child(code_row)
	_code.placeholder_text = "ROOM CODE"
	_code.max_length = 12
	_code.custom_minimum_size = Vector2(204, 50)
	_code.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_code.text_submitted.connect(func(_t): _join_room())
	_code.text_changed.connect(func(t: String):
		var col_pos := _code.caret_column
		_code.text = t.to_upper()
		_code.caret_column = col_pos)
	code_row.add_child(_code)
	var join_room := UiTheme.button("Join room", 204)
	join_room.pressed.connect(_join_room)
	code_row.add_child(join_room)
	var direct := _wide_button("Direct connect...", _toggle_direct)
	_connect_box.add_child(direct)

	# Direct (WebSocket): address + Join, and Host on desktop.
	_direct_box.visible = false
	_direct_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_direct_box.add_theme_constant_override("separation", 12)
	_connect_box.add_child(_direct_box)
	_address.text = Net.address
	_address.custom_minimum_size = Vector2(420, 50)
	_address.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_address.text_submitted.connect(func(_t): _join())
	_direct_box.add_child(_address)
	var direct_row := HBoxContainer.new()
	direct_row.alignment = BoxContainer.ALIGNMENT_CENTER
	direct_row.add_theme_constant_override("separation", 12)
	_direct_box.add_child(direct_row)
	var join_direct := UiTheme.button("Join address", 204)
	join_direct.pressed.connect(_join)
	direct_row.add_child(join_direct)
	var host_direct := UiTheme.button("Host (LAN)", 204)
	host_direct.pressed.connect(_host)
	host_direct.visible = Net.can_host()
	direct_row.add_child(host_direct)
	var back := _wide_button("Back", _back)
	_connect_box.add_child(back)
	_menu_list = [create, _code, join_room, direct, back]
	_direct_list = [_address, join_direct, host_direct]

	# Connecting: just a way out.
	_waiting_box.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(_waiting_box)
	_cancel = _wide_button("Cancel", _back)
	_waiting_box.add_child(_cancel)

	# Status line (connecting / errors / who we're waiting for).
	_status = UiTheme.label("", 22, Palette.TEXT)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_status)

	# In a room: player cards, key hints, Leave / Ready for the mouse.
	_room_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_room_box.add_theme_constant_override("separation", 14)
	col.add_child(_room_box)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 18)
	_room_box.add_child(row)
	for i in PlayerManager.MAX_PLAYERS:
		var slot := LobbySlot.new()
		slot.online = true
		slot.color_step.connect(func(_info, dir: int): _step_color(dir))
		row.add_child(slot)
		_slots.append(slot)
	_room_status = UiTheme.label("", 22, Palette.TEXT)
	_room_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_room_box.add_child(_room_status)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 16)
	var leave := UiTheme.button("Leave", 180)
	leave.pressed.connect(_back)
	_ready_button = UiTheme.button("Ready", 220)
	_ready_button.pressed.connect(_toggle_ready)
	for b: Button in [leave, _ready_button]:
		b.focus_mode = Control.FOCUS_NONE   # keys/pad drive the room; buttons are for the mouse
		buttons.add_child(b)
	var a := func(act): return UiTheme.key("kb_a", act)
	var hint := UiTheme.hint("%s / [Space] ready     %s %s colour     [Esc] leave     pad: [A] ready  [D-Pad] colour" % [
		a.call("jump"), a.call("left"), a.call("right")], 17)
	_room_box.add_child(hint)
	_room_box.add_child(buttons)

	Net.roster_changed.connect(_refresh)
	Net.status_changed.connect(_refresh)
	_refresh()


func _refresh() -> void:
	var online := Net.is_online()
	var me := Net.local_info()
	var in_room := online and (me != null or Net.dedicated)
	var view := View.ROOM if in_room else (View.WAITING if online else View.CONNECT)
	_connect_box.visible = view == View.CONNECT
	_waiting_box.visible = view == View.WAITING
	_room_box.visible = view == View.ROOM
	_title.visible = view != View.ROOM or Net.room_code == ""
	_subtitle.visible = view == View.CONNECT
	_code_panel.visible = view == View.ROOM and Net.room_code != ""
	_code_label.text = Net.room_code
	_host_note.visible = _code_panel.visible and Net.is_server() and Settings.is_web()
	_ready_button.visible = me != null

	var infos := PlayerManager.sorted_players()
	for i in _slots.size():
		_slots[i].show_player(infos[i] if i < infos.size() else null)
	if me:
		_ready_button.text = "Not ready" if me.is_ready else "Ready"

	var text := Net.status
	var color := Palette.ACCENT_2 if view == View.CONNECT and text != "" else Palette.TEXT
	if in_room:
		var waiting := infos.filter(func(p): return not p.is_ready).size()
		text = "Waiting for %d player%s to ready up" % [waiting, "" if waiting == 1 else "s"] if waiting > 0 else "Starting..."
		if Net.room_code == "" and Net.is_server() and not Net.dedicated:
			text += "    (hosting - others join ws://<your IP>:%d)" % Net.DEFAULT_PORT
	_room_status.text = text
	_status.text = text
	_status.add_theme_color_override("font_color", color)
	_status.visible = text != "" and not in_room

	if view != _view:
		_view = view
		_focus_view()


## Whenever the screen changes, put keyboard focus somewhere that's visible -
## otherwise it stays on a hidden button and the keys do nothing.
func _focus_view() -> void:
	match _view:
		View.CONNECT:
			_relink()
			_menu_list[0].grab_focus.call_deferred()
		View.WAITING:
			_cancel.grab_focus.call_deferred()
		View.ROOM:
			UiFx.stamp(_code_panel, 1.5, -6.0)
			var f := get_viewport().gui_get_focus_owner()
			if f:
				f.release_focus()


func _relink() -> void:
	var list: Array = _menu_list.slice(0, 4)
	if _direct_box.visible:
		list.append_array(_direct_list)
	list.append(_menu_list[4])
	MenuBase.link_vertical(list)


func _toggle_direct() -> void:
	_direct_box.visible = not _direct_box.visible
	_relink()
	if _direct_box.visible:
		_address.grab_focus.call_deferred()


func _wide_button(text: String, callback: Callable) -> Button:
	var b := UiTheme.button(text, 420)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(callback)
	return b


func _create_room() -> void:
	Net.create_room()
	_refresh()


func _join_room() -> void:
	var code := _code.text.strip_edges()
	if code == "":
		_code.grab_focus()
		return
	Net.join_room(code)
	_refresh()


func _join() -> void:
	var url := _address.text.strip_edges()
	if url == "":
		return
	if not url.contains("://"):
		url = "ws://" + url
	if url.count(":") < 2:
		url += ":%d" % Net.DEFAULT_PORT
	Net.join(url)
	_refresh()


func _host() -> void:
	Net.host()
	_refresh()


func _toggle_ready() -> void:
	var me := Net.local_info()
	if me:
		Net.ask_ready(not me.is_ready)


func _step_color(dir: int) -> void:
	var me := Net.local_info()
	if me and not me.is_ready:
		Net.ask_color(dir)
		Sfx.play("ui_move")


func _back() -> void:
	Sfx.play("ui_back")
	if Net.is_online():
		Net.leave()
		Net.status = ""
		_refresh()
	else:
		MatchManager.to_menu()


# ── Input ────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	# Taken up front: readying up can start the match, which frees this screen
	# before we get to mark the key as used.
	var viewport := get_viewport()
	if _view == View.ROOM and Net.local_info() and _room_input(event):
		viewport.set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel"):
		viewport.set_input_as_handled()
		_back()


## Couch-lobby style controls inside a room. Returns true if it used the event.
func _room_input(event: InputEvent) -> bool:
	var me := Net.local_info()
	var cmd := ""
	if event is InputEventKey:
		if not event.pressed or event.echo:
			return false
		if event.physical_keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]:
			cmd = "ready"
		elif event.physical_keycode == KEY_ESCAPE:
			cmd = "back"
		else:
			cmd = _kb_command(event)
	elif event is InputEventJoypadButton and event.pressed:
		match event.button_index:
			JOY_BUTTON_A, JOY_BUTTON_START: cmd = "ready"
			JOY_BUTTON_B: cmd = "back"
			JOY_BUTTON_DPAD_LEFT: cmd = "prev"
			JOY_BUTTON_DPAD_RIGHT, JOY_BUTTON_Y: cmd = "next"
	elif event is InputEventJoypadMotion and event.axis == JOY_AXIS_LEFT_X:
		var dir := 0
		if event.axis_value > 0.6:
			dir = 1
		elif event.axis_value < -0.6:
			dir = -1
		if dir != _stick_latch:
			_stick_latch = dir
			if dir != 0:
				cmd = "next" if dir > 0 else "prev"
	match cmd:
		"ready":
			_toggle_ready()
		"back":
			if me.is_ready:
				Net.ask_ready(false)   # first back out of ready, then out of the room
			else:
				_back()
		"unready":
			if me.is_ready:
				Net.ask_ready(false)
		"prev", "next":
			_step_color(-1 if cmd == "prev" else 1)
		_:
			return false
	return true


## Either keyboard half's jump / left / right / down, as bound in Settings.
func _kb_command(event: InputEventKey) -> String:
	var map := {"jump": "ready", "left": "prev", "right": "next", "down": "unready"}
	for profile in ["kb_a", "kb_b"]:
		for action in map:
			for b in Settings.bindings[profile][action]:
				var ev := Settings.binding_to_event(b)
				if ev and ev.is_match(event, false):
					return map[action]
	return ""
