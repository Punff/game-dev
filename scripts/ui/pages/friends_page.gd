class_name FriendsPage
extends UiPage

## Friends: add someone by username, answer requests, see who's online and
## where, and join a friend's room (or an invite) without typing its code.
## There's no push from the server, so the page asks again every few seconds
## and only rebuilds when something changed (focus stays put).

const POLL := 8.0
const STATUS_TEXT := {"room": "In room %s", "match": "In a match", "menu": "Online", "offline": "Offline"}

var _add := UiField.new("Add a friend", "their username", 16)
var _send_btn: Button
var _status: Label
var _list := VBoxContainer.new()
var _poll := 0.0
var _last := {}
var _logged_in := false


func _init() -> void:
	title = "Friends"


func build() -> void:
	_logged_in = Settings.logged_in()
	if not _logged_in:
		add_child(UiPage.notes("Friends need an account: log in and you can add people by their username, see when they're online and jump into their rooms.", Palette.TEXT, 19))
		var b := UiTheme.button("Log in / Create account", 0)
		b.pressed.connect(func(): push(SignInPage.new()))
		add_child(b)
		UiNav.link_vertical([b])
		return
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_add.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_add.edit.text_submitted.connect(func(_t): _send_request())
	row.add_child(_add)
	_send_btn = UiTheme.button("Send request", 200)
	_send_btn.size_flags_vertical = Control.SIZE_SHRINK_END
	_send_btn.pressed.connect(_send_request)
	row.add_child(_send_btn)
	add_child(row)
	_status = UiPage.notes("")
	add_child(_status)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	add_child(scroll)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_list)
	_list.add_child(UiPage.notes("Loading..."))
	UiNav.link_grid([[_add.edit, _send_btn]])
	_refresh()


## Back from signing in: start over with the account.
func entered() -> void:
	if Settings.logged_in() != _logged_in:
		for c in get_children():
			c.queue_free()
		_last = {}
		_list = VBoxContainer.new()
		_add = UiField.new("Add a friend", "their username", 16)
		build()
		focus_first()


func _process(delta: float) -> void:
	if not _logged_in or not visible:
		return
	_poll += delta
	if _poll >= POLL:
		_poll = 0.0
		_refresh()


func _refresh() -> void:
	Stats.friends(func(ok: bool, reply: Dictionary):
		if not ok:
			if _last.is_empty():
				_clear_list()
				_list.add_child(UiPage.notes(str(reply.get("error", "Couldn't reach the server. Try again later."))))
			return
		if reply.hash() != _last.hash():
			_last = reply
			_rebuild(reply))


# ── List ─────────────────────────────────────

func _rebuild(r: Dictionary) -> void:
	var focus := get_viewport().gui_get_focus_owner()
	var keep: String = focus.get_meta("key", "") if focus and _list.is_ancestor_of(focus) else ""
	_clear_list()
	var rows: Array = [[_add.edit, _send_btn]]
	var invites: Array = r.get("invites", [])
	if not invites.is_empty():
		_list.add_child(UiPage.heading("Invites"))
		for inv in invites:
			rows.append(_row(inv.from, "invited you to room %s" % inv.room, Palette.MUSTARD,
				[_btn("Join", "%s:join" % inv.from, _join.bind(inv.room))]))
	var incoming: Array = r.get("incoming", [])
	if not incoming.is_empty():
		_list.add_child(UiPage.heading("Requests"))
		for name in incoming:
			rows.append(_row(name, "wants to be friends", Palette.TEXT_DIM,
				[_btn("Accept", "%s:accept" % name, _act.bind("accept", name)), _btn("Decline", "%s:decline" % name, _act.bind("remove", name))]))
	var friends: Array = r.get("friends", [])
	var online := friends.filter(func(f): return f.online).size()
	_list.add_child(UiPage.heading("Friends  %d online" % online if not friends.is_empty() else "Friends"))
	if friends.is_empty():
		_list.add_child(UiPage.notes("No friends yet. Add someone by their username above; once they accept you'll see when they're online and can join their rooms."))
	for f in friends:
		var buttons: Array = []
		if f.get("room") != null and str(f.room) != "":
			buttons.append(_btn("Join", "%s:join" % f.name, _join.bind(str(f.room))))
		buttons.append(_btn("Remove", "%s:remove" % f.name, _act.bind("remove", f.name)))
		var text: String = STATUS_TEXT.get(f.status, "Online")
		if f.status == "room":
			text = text % f.room
		rows.append(_row(f.name, text, Palette.GOOD if f.online else Palette.SMOKE, buttons))
	var outgoing: Array = r.get("outgoing", [])
	if not outgoing.is_empty():
		_list.add_child(UiPage.heading("Sent"))
		for name in outgoing:
			rows.append(_row(name, "hasn't answered yet", Palette.TEXT_DIM, [_btn("Cancel", "%s:cancel" % name, _act.bind("remove", name))]))
	UiNav.link_grid(rows)
	if keep != "":
		for c in _list.find_children("*", "Button", true, false):
			if c.get_meta("key", "") == keep:
				c.grab_focus.call_deferred()
				return
	if focus == null or not is_instance_valid(focus) or not focus.is_inside_tree():
		_add.edit.grab_focus.call_deferred()


## One person: a dot and their name, what they're up to, and buttons.
## Returns the buttons (a focus row).
func _row(who: String, sub: String, dot: Color, buttons: Array) -> Array:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiTheme.box(Color(Palette.INK_SOFT, 0.8), Color.TRANSPARENT, 0, 0, Vector2(12, 6)))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	p.add_child(h)
	var d := Panel.new()
	d.add_theme_stylebox_override("panel", UiTheme.box(dot, Palette.INK, 2, 7))
	d.custom_minimum_size = Vector2(14, 14)
	d.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(d)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", -2)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	var n := UiTheme.label(who, 22, Palette.PAPER)
	n.add_theme_font_override("font", UiTheme.heavy())
	n.clip_text = true
	v.add_child(n)
	v.add_child(UiTheme.label(sub, 15, dot if dot != Palette.SMOKE else Palette.TEXT_DIM))
	for b in buttons:
		h.add_child(b)
	_list.add_child(p)
	return buttons


func _btn(text: String, key: String, callback: Callable) -> Button:
	var b := UiTheme.button(text, 104)
	b.custom_minimum_size.y = 40
	b.add_theme_font_size_override("font_size", 18)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.set_meta("key", key)
	b.pressed.connect(callback)
	return b


func _clear_list() -> void:
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()


# ── Actions ──────────────────────────────────

func _send_request() -> void:
	var who := _add.text.strip_edges()
	if who == "":
		_add.edit.grab_focus()
		return
	Stats.friend_action("request", who, func(ok: bool, reply: Dictionary):
		if not ok:
			UiPage.say(_status, str(reply.get("error", "Couldn't reach the server.")), Palette.ACCENT_2)
			return
		_add.text = ""
		UiPage.say(_status, ("You and %s are friends now." if reply.get("status") == "accepted" else "Asked %s. They'll see it next time they look.") % who, Palette.GOOD)
		_refresh())


func _act(kind: String, who: String) -> void:
	Stats.friend_action(kind, who, func(ok: bool, reply: Dictionary):
		if not ok:
			UiPage.say(_status, str(reply.get("error", "Couldn't reach the server.")), Palette.ACCENT_2)
		_refresh())


func _join(code: String) -> void:
	var problem := OnlinePage.connect_with(Net.join_room.bind(code))
	if problem != "":
		UiPage.say(_status, problem, Palette.ACCENT_2)
