class_name PausePage
extends UiPage

## The pause menu's page. Back (or Start) on it resumes; Settings opens on
## top of it in the same sleeve.

signal resume

var _note: Label


func _init() -> void:
	title = "Paused"
	float_size = Vector2(440, 420)


func build() -> void:
	_note = UiPage.notes("", Palette.ACCENT_2, 18)
	_note.visible = false
	add_child(_note)
	var buttons: Array = [_button("Resume", func(): resume.emit()), _button("Settings", func(): push(SettingsPage.new()))]
	if Net.is_online():
		buttons.append(_button("Leave match", func():
			Net.leave()
			MatchManager.to_menu()))
	else:
		buttons.append(_button("Restart", func(): MatchManager.start_match()))
		buttons.append(_button("Change players", func(): MatchManager.to_lobby()))
		buttons.append(_button("Main menu", func(): MatchManager.to_menu()))
	UiNav.link_vertical(buttons)


func hints() -> String:
	return "%s select     %s resume" % [UiHintBar.accept_key(), UiHintBar.back_key()]


## A line above the buttons, e.g. "Controller 2 disconnected".
func set_note(text: String) -> void:
	_note.text = text
	_note.visible = text != ""
	if _note.visible:
		UiFx.bump(_note, 0.1)


func _button(text: String, callback: Callable) -> Button:
	var b := UiTheme.button(text, 0)
	b.pressed.connect(callback)
	add_child(b)
	return b
