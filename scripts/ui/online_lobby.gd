extends MenuBase

## Online play: create a room or join one with its code (works between
## browsers anywhere), or connect directly by address (LAN / dedicated
## server). Then the same player cards as the couch lobby. Each computer
## brings one player, using either keyboard half or any gamepad. The match
## starts once everyone is ready.

var _connect_box := VBoxContainer.new()
var _direct_box := VBoxContainer.new()
var _waiting_box := VBoxContainer.new()
var _room_box := VBoxContainer.new()
var _address := LineEdit.new()
var _code := LineEdit.new()
var _code_label: Label
var _host_note: Label
var _status: Label
var _slots: Array = []
var _ready_button: Button
var _color_row := HBoxContainer.new()


func _ready() -> void:
	MatchManager.state = MatchManager.State.LOBBY
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := Background.new()
	bg.auto_scroll = 25.0
	add_child(bg)

	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 22)
	add_child(col)
	col.add_child(UiTheme.title("online", 56, Palette.PAPER))

	# In a room: its code to share, and a reminder for browser hosts.
	_code_label = UiTheme.title("", 44, Palette.PAPER)
	col.add_child(_code_label)
	_host_note = UiTheme.label("You're hosting: keep this tab open and in front, the match runs in your browser.", 18, Palette.TEXT_DIM)
	_host_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_host_note)

	_status = UiTheme.label("", 22, Palette.ACCENT_2)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_status)

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
	_code.custom_minimum_size = Vector2(200, 50)
	_code.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_code.text_submitted.connect(func(_t): _join_room())
	_code.text_changed.connect(func(t: String):
		var col_pos := _code.caret_column
		_code.text = t.to_upper()
		_code.caret_column = col_pos)
	code_row.add_child(_code)
	var join_room := UiTheme.button("Join room", 208)
	join_room.pressed.connect(_join_room)
	code_row.add_child(join_room)
	var direct := _wide_button("Direct connect...", func(): _direct_box.visible = not _direct_box.visible)
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
	MenuBase.link_vertical([create, _code, direct, back])

	# Connecting: just a way out.
	_waiting_box.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(_waiting_box)
	_waiting_box.add_child(_wide_button("Cancel", _back))

	# Connected: player cards + Ready / colour / Leave.
	_room_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_room_box.add_theme_constant_override("separation", 18)
	col.add_child(_room_box)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 18)
	_room_box.add_child(row)
	for i in PlayerManager.MAX_PLAYERS:
		var slot := LobbySlot.new()
		slot.online = true
		row.add_child(slot)
		_slots.append(slot)
	_color_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_color_row.add_theme_constant_override("separation", 16)
	_room_box.add_child(_color_row)
	var prev := UiTheme.button("< Colour", 180)
	prev.pressed.connect(func(): Net.ask_color(-1))
	var next := UiTheme.button("Colour >", 180)
	next.pressed.connect(func(): Net.ask_color(1))
	_ready_button = UiTheme.button("Ready", 220)
	_ready_button.pressed.connect(_toggle_ready)
	var leave := UiTheme.button("Leave", 180)
	leave.pressed.connect(_back)
	for b in [prev, _ready_button, next, leave]:
		_color_row.add_child(b)

	Net.roster_changed.connect(_refresh)
	Net.status_changed.connect(_refresh)
	_refresh()
	if Net.dedicated:
		return
	if Net.is_online():
		_ready_button.grab_focus.call_deferred()
	else:
		focus_first()


func _refresh() -> void:
	var online := Net.is_online()
	var me := Net.local_info()
	var in_room := online and (me != null or Net.dedicated)
	_connect_box.visible = not online
	_waiting_box.visible = online and not in_room
	_room_box.visible = in_room
	_color_row.visible = me != null
	_code_label.visible = in_room and Net.room_code != ""
	_code_label.text = "Room  %s" % Net.room_code
	_host_note.visible = _code_label.visible and Net.is_server() and Settings.is_web()

	var infos := PlayerManager.sorted_players()
	for i in _slots.size():
		_slots[i].show_player(infos[i] if i < infos.size() else null)
	if me:
		_ready_button.text = "Not ready" if me.is_ready else "Ready"

	var text := Net.status
	if in_room:
		var waiting := infos.filter(func(p): return not p.is_ready).size()
		text = "Waiting for %d player%s to ready up" % [waiting, "" if waiting == 1 else "s"] if waiting > 0 else "Starting..."
		if Net.room_code != "":
			text += "    (friends join with this code)" if Net.is_server() else ""
		elif Net.is_server() and not Net.dedicated:
			text += "    (hosting - others join ws://<your IP>:%d)" % Net.DEFAULT_PORT
	_status.text = text


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
	if Net.host() == OK:
		_ready_button.grab_focus.call_deferred()
	_refresh()


func _toggle_ready() -> void:
	var me := Net.local_info()
	if me:
		Net.ask_ready(not me.is_ready)


func _back() -> void:
	Sfx.play("ui_back")
	if Net.is_online():
		Net.leave()
		Net.status = ""
		_refresh()
		focus_first()
	else:
		MatchManager.to_menu()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_back()
