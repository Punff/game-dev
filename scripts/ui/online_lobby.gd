extends Control

## Online play once you're connecting (the main menu's Online page starts
## it): the same player cards as the couch lobby. Each computer brings one
## player, using either keyboard half or any gamepad. The match starts once
## everyone is ready. If the connection is lost before a room, it goes back
## to the Online page, which shows why.
##
## Inside a room it works like the couch lobby: your game keys or pad ready
## you up and change colour, and the buttons are there for the mouse.

enum View { CONNECT, WAITING, ROOM }

var _title: Label
var _waiting_box := VBoxContainer.new()
var _room_box := VBoxContainer.new()
var _code_panel := PanelContainer.new()
var _code_label: Label
var _host_note: Label
var _status: Label
var _room_status: Label
var _slots: Array = []
var _ready_button: Button
var _cancel: Button
var _view := -1
var _stick_latch := 0
# Inviting friends into this room (logged in, in a room with a code).
var _invite_panel := PanelContainer.new()
var _invite_rows := VBoxContainer.new()
var _invite_poll := 0.0
var _invitable: Array = []      # online friends not in this room
var _invited := {}              # name -> true, for this room
const INVITE_POLL := 10.0
const INVITE_ROWS := 3


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

	_build_invites()
	Net.roster_changed.connect(_refresh)
	Net.pings_changed.connect(func():
		for s in _slots:
			s.show_ping())
	Net.status_changed.connect(_refresh)
	_refresh()


# ── Inviting friends ─────────────────────────

func _build_invites() -> void:
	_invite_panel.add_theme_stylebox_override("panel", UiTheme.box(Color(Palette.INK, 0.92), Palette.SMOKE, 2, 0, Vector2(14, 10), 5))
	_invite_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_invite_panel.offset_left = 24
	_invite_panel.offset_bottom = -24
	_invite_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_invite_panel.custom_minimum_size.x = 280
	_invite_panel.visible = false
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	_invite_panel.add_child(v)
	var head := HBoxContainer.new()
	var t := UiTheme.label("INVITE FRIENDS", 15, Palette.MUSTARD)
	t.add_theme_font_override("font", UiTheme.heavy())
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	head.add_child(UiTheme.hint("[Tab] all", 14, Palette.PAPER_DIM, false))
	v.add_child(head)
	_invite_rows.add_theme_constant_override("separation", 4)
	v.add_child(_invite_rows)
	add_child(_invite_panel)


func _process(delta: float) -> void:
	var can := _view == View.ROOM and Net.room_code != "" and Settings.logged_in() and Stats.enabled()
	if not can:
		_invite_panel.visible = false
		return
	_invite_poll -= delta
	if _invite_poll > 0.0:
		return
	_invite_poll = INVITE_POLL
	Stats.friends(func(ok: bool, reply: Dictionary):
		if ok:
			_invitable = reply.get("friends", []).filter(func(f): return f.online and str(f.get("room", "")) != Net.room_code)
			_fill_invites())


func _fill_invites() -> void:
	for c in _invite_rows.get_children():
		c.queue_free()
	_invite_panel.visible = true
	if _invitable.is_empty():
		_invite_rows.add_child(UiTheme.label("No friends online right now", 15, Palette.TEXT_DIM))
		return
	for i in mini(_invitable.size(), INVITE_ROWS):
		var who: String = _invitable[i].name
		var h := HBoxContainer.new()
		var n := UiTheme.label(who, 18, Palette.PAPER)
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		n.clip_text = true
		h.add_child(n)
		var b := UiTheme.button("Invited" if _invited.has(who) else "Invite", 96)
		b.custom_minimum_size.y = 34
		b.add_theme_font_size_override("font_size", 16)
		b.focus_mode = Control.FOCUS_NONE   # keys/pad drive the room; Tab invites everyone
		b.disabled = _invited.has(who)
		b.pressed.connect(_invite.bind(who))
		h.add_child(b)
		_invite_rows.add_child(h)
	if _invitable.size() > INVITE_ROWS:
		_invite_rows.add_child(UiTheme.label("+%d more" % (_invitable.size() - INVITE_ROWS), 14, Palette.TEXT_DIM))


func _invite(who: String) -> void:
	if _invited.has(who):
		return
	_invited[who] = true
	Stats.friend_action("invite", who, func(_ok, _r): pass, Net.room_code)
	Sfx.play("ui_select")
	_fill_invites()


func _invite_all() -> void:
	for f in _invitable:
		_invite(f.name)


func _refresh() -> void:
	var online := Net.is_online()
	var me := Net.local_info()
	var in_room := online and (me != null or Net.dedicated)
	var view := View.ROOM if in_room else (View.WAITING if online else View.CONNECT)
	if view == View.CONNECT:
		_leave_to_menu()
		return
	_waiting_box.visible = view == View.WAITING
	_room_box.visible = view == View.ROOM
	_title.visible = view != View.ROOM or Net.room_code == ""
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
	if in_room:
		var waiting := infos.filter(func(p): return not p.is_ready).size()
		text = "Waiting for %d player%s to ready up" % [waiting, "" if waiting == 1 else "s"] if waiting > 0 else "Starting..."
		if Net.room_code == "" and Net.is_server() and not Net.dedicated:
			text += "    (hosting - others join ws://<your IP>:%d)" % Net.DEFAULT_PORT
	_room_status.text = text
	_status.text = text
	_status.visible = text != "" and not in_room

	if view != _view:
		_view = view
		_focus_view()


## Whenever the screen changes, put keyboard focus somewhere that's visible -
## otherwise it stays on a hidden button and the keys do nothing.
func _focus_view() -> void:
	match _view:
		View.WAITING:
			_cancel.grab_focus.call_deferred()
		View.ROOM:
			UiFx.stamp(_code_panel, 1.5, -6.0)
			var f := get_viewport().gui_get_focus_owner()
			if f:
				f.release_focus()


func _wide_button(text: String, callback: Callable) -> Button:
	var b := UiTheme.button(text, 420)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(callback)
	return b


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
	Net.leave()
	Net.status = ""
	_leave_to_menu()


## Back to the main menu's Online page (it shows Net.status, if any).
func _leave_to_menu() -> void:
	if _view == -2:
		return
	_view = -2
	UiShell.resume = "online"
	MatchManager.to_menu()


# ── Input ────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	# Taken up front: readying up can start the match, which frees this screen
	# before we get to mark the key as used.
	var viewport := get_viewport()
	if _view == View.ROOM and _invite_panel.visible and (event.is_action_pressed("ui_tab_next") or event.is_action_pressed("ui_tab_prev")):
		viewport.set_input_as_handled()
		_invite_all()
		return
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
