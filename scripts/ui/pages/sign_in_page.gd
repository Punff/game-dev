class_name SignInPage
extends UiPage

## Log in or create an account. Only accounts are ranked; there's no email,
## so a forgotten password is reset by hand. As the first-launch gate it also
## offers playing as a guest, and Back doesn't skip it.

signal done

var gate := false
var _user := UiField.new("Username", "3-16 letters, digits, _ or -", 16)
var _pass := UiField.new("Password", "8 or more characters", 128, true)
var _status: Label
var _login: Button
var _create: Button
var _guest: Button
var _busy := false


func _init() -> void:
	title = "Sign in"


func build() -> void:
	if gate:
		title = "Sign the sleeve"
		add_child(UiPage.notes("Make an account to get your climbs and wins on the leaderboards, on any computer. Or just play: you can sign in later from Profile.", Palette.TEXT, 19))
	add_child(_user)
	add_child(_pass)
	_user.edit.text_submitted.connect(func(_t): _pass.edit.grab_focus())
	_pass.edit.text_submitted.connect(func(_t): _go(false))
	_status = UiPage.notes("There's no email, so keep your password safe.")
	add_child(_status)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_login = UiTheme.button("Log in", 0)
	_create = UiTheme.button("Create account", 0)
	for b in [_login, _create]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(b)
	_login.pressed.connect(_go.bind(false))
	_create.pressed.connect(_go.bind(true))
	add_child(row)
	var rows: Array = [[_user.edit], [_pass.edit], [_login, _create]]
	if gate:
		_guest = UiTheme.button("Play as guest", 0)
		_guest.pressed.connect(_play_as_guest)
		add_child(_guest)
		rows.append([_guest])
	UiNav.link_grid(rows)


func hints() -> String:
	return "%s select" % UiHintBar.accept_key() if gate else super()


func handle_back() -> bool:
	if gate:
		UiFx.bump(_guest, 0.15)
		_guest.grab_focus()
		return true
	return false


func _play_as_guest() -> void:
	Settings.set_value("onboarded", true)
	done.emit()


func _go(create: bool) -> void:
	if _busy:
		return
	if _user.text.strip_edges() == "" or _pass.text == "":
		UiPage.say(_status, "Enter a username and a password.", Palette.ACCENT_2)
		return
	_busy = true
	UiPage.say(_status, "Creating account..." if create else "Logging in...")
	var finish := func(ok: bool, error: String):
		_busy = false
		if not is_inside_tree():
			return
		if ok:
			Sfx.play("ui_select")
			Settings.set_value("onboarded", true)
			done.emit()
			if not gate:
				pop()
		else:
			_pass.text = ""
			UiPage.say(_status, error, Palette.ACCENT_2)
	if create:
		Stats.register(_user.text, _pass.text, finish)
	else:
		Stats.login(_user.text, _pass.text, finish)
