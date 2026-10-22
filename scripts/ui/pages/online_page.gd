class_name OnlinePage
extends UiPage

## Getting into a room: create one, join one by code, or connect directly by
## address (LAN / dedicated server). Once connecting, the online lobby scene
## takes over; if that fails it sends you back here with the reason.

var _code := UiField.new("Room code", "ABCDE", 12)
var _address := UiField.new("Address", "ws://127.0.0.1:7777", 128)
var _direct := VBoxContainer.new()
var _status: Label
var _create: Button
var _join: Button
var _direct_toggle: Button
var _join_direct: Button
var _host: Button


func _init() -> void:
	title = "Online"


func build() -> void:
	add_child(UiPage.notes("Play with friends anywhere: one of you creates a room and shares its code. Each computer brings one player."))
	_create = UiTheme.button("Create room", 0)
	_create.pressed.connect(func(): _connect(Net.create_room))
	add_child(_create)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_code.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_code.edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_code.edit.text_submitted.connect(func(_t): _join_room())
	_code.edit.text_changed.connect(func(t: String):
		var at := _code.edit.caret_column
		_code.edit.text = t.to_upper()
		_code.edit.caret_column = at)
	row.add_child(_code)
	_join = UiTheme.button("Join room", 200)
	_join.size_flags_vertical = Control.SIZE_SHRINK_END
	_join.pressed.connect(_join_room)
	row.add_child(_join)
	add_child(row)

	_direct_toggle = UiTheme.button("Direct connect...", 0)
	_direct_toggle.pressed.connect(_toggle_direct)
	add_child(_direct_toggle)
	_direct.visible = false
	_direct.add_theme_constant_override("separation", 10)
	_address.text = Net.address
	_address.edit.text_submitted.connect(func(_t): _join_address())
	_direct.add_child(_address)
	var drow := HBoxContainer.new()
	drow.add_theme_constant_override("separation", 12)
	_join_direct = UiTheme.button("Join address", 200)
	_join_direct.pressed.connect(_join_address)
	_host = UiTheme.button("Host (LAN)", 200)
	_host.pressed.connect(func(): _connect(Net.host))
	_host.visible = Net.can_host()
	drow.add_child(_join_direct)
	drow.add_child(_host)
	_direct.add_child(drow)
	add_child(_direct)

	_status = UiPage.notes("", Palette.ACCENT_2, 20)
	add_child(_status)
	_relink()


func entered() -> void:
	if Net.status != "":
		UiPage.say(_status, Net.status, Palette.ACCENT_2)
		Net.status = ""


func _relink() -> void:
	var rows: Array = [[_create], [_code.edit, _join], [_direct_toggle]]
	if _direct.visible:
		rows.append([_address.edit])
		rows.append([_join_direct, _host])
	UiNav.link_grid(rows)


func _toggle_direct() -> void:
	_direct.visible = not _direct.visible
	_relink()
	if _direct.visible:
		_address.edit.grab_focus.call_deferred()


func _join_room() -> void:
	var code := _code.text.strip_edges()
	if code == "":
		_code.edit.grab_focus()
		UiPage.say(_status, "Type the room code your friend sees on their screen.", Palette.ACCENT_2)
		return
	_connect(Net.join_room.bind(code))


func _join_address() -> void:
	var url := _address.text.strip_edges()
	if url == "":
		return
	if not url.contains("://"):
		url = "ws://" + url
	if url.count(":") < 2:
		url += ":%d" % Net.DEFAULT_PORT
	_connect(Net.join.bind(url))


## Start connecting; the lobby screen shows the rest. If it failed on the
## spot (bad address, no room service) say why and stay here.
func _connect(start: Callable) -> void:
	var problem := OnlinePage.connect_with(start)
	if problem != "":
		UiPage.say(_status, problem, Palette.ACCENT_2)


## Start connecting (Net.create_room, Net.join_room.bind(code)...) and head to
## the online lobby. Returns "" when it's on its way, or what went wrong.
static func connect_with(start: Callable) -> String:
	Net.status = ""
	start.call()
	if Net.is_online():
		MatchManager.state = MatchManager.State.LOBBY
		MatchManager.goto(Net.ONLINE_LOBBY)
		return ""
	return Net.status if Net.status != "" else "Couldn't connect."
