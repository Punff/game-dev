class_name AccountMenu
extends MenuBase

## Log in / create an account, or log out. Only accounts are ranked on the
## leaderboards; there's no email, so a forgotten password is reset by hand.

var _user := LineEdit.new()
var _pass := LineEdit.new()
var _status: Label
var _buttons: Array[Button] = []
var _busy := false


func _ready() -> void:
	build_overlay(0.75, 520)
	var title := UiTheme.title("account", 40)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	content.add_child(title)
	content.add_child(HSeparator.new())
	_status = UiTheme.label("", 18, Palette.TEXT_DIM)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size.x = 460
	if Settings.logged_in():
		_build_logged_in()
	else:
		_build_logged_out()
	UiFx.stamp(panel, 1.06, -1.5)


func _build_logged_in() -> void:
	content.add_child(UiTheme.label("Logged in as", 20, Palette.TEXT_DIM))
	content.add_child(UiTheme.title(Settings.player_name(), 36, Palette.ACCENT))
	content.add_child(_status)
	_status.text = "Your solo climbs and online wins count for this account on any computer you log in on."
	var out := add_button("Log out", func():
		Stats.logout()
		closed.emit())
	var back := add_button("Back", func(): closed.emit())
	_buttons = [out, back]
	MenuBase.link_vertical(_buttons)
	back.grab_focus.call_deferred()   # so a stray press doesn't log out


func _build_logged_out() -> void:
	for pair in [[_user, "Username"], [_pass, "Password"]]:
		var e: LineEdit = pair[0]
		e.placeholder_text = pair[1]
		e.custom_minimum_size = Vector2(460, 48)
		e.max_length = 16 if e == _user else 128
		content.add_child(e)
	_pass.secret = true
	_user.text_submitted.connect(func(_t): _pass.grab_focus())
	_pass.text_submitted.connect(func(_t): _go(false))
	_status.text = "3-16 letters, digits, _ or -. Passwords: 8+ characters. There's no email, so keep your password safe."
	content.add_child(_status)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var login := UiTheme.button("Log in", 220)
	login.pressed.connect(_go.bind(false))
	var create := UiTheme.button("Create account", 220)
	create.pressed.connect(_go.bind(true))
	row.add_child(login)
	row.add_child(create)
	content.add_child(row)
	var back := add_button("Back", func(): closed.emit())
	_buttons = [login, create, back]
	MenuBase.link_vertical([_user, _pass, login, back])
	login.focus_neighbor_right = login.get_path_to(create)
	create.focus_neighbor_left = create.get_path_to(login)
	create.focus_neighbor_top = create.get_path_to(_pass)
	create.focus_neighbor_bottom = create.get_path_to(back)
	_user.grab_focus.call_deferred()


func _go(create: bool) -> void:
	if _busy:
		return
	if _user.text.strip_edges() == "" or _pass.text == "":
		_say("Enter a username and a password.", Palette.ACCENT_2)
		return
	_busy = true
	_say("Creating account..." if create else "Logging in...", Palette.TEXT_DIM)
	var done := func(ok: bool, error: String):
		_busy = false
		if not is_inside_tree():
			return
		if ok:
			Sfx.play("ui_select")
			closed.emit()
		else:
			_pass.text = ""
			_say(error, Palette.ACCENT_2)
	if create:
		Stats.register(_user.text, _pass.text, done)
	else:
		Stats.login(_user.text, _pass.text, done)


func _say(text: String, color: Color) -> void:
	_status.text = text
	_status.add_theme_color_override("font_color", color)
	UiFx.bump(_status, 0.1)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		Sfx.play("ui_back")
		closed.emit()
