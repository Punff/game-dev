class_name PauseMenu
extends CanvasLayer

## Pause overlay. Anyone can pause; Start / Esc / B resumes.
## Online the match keeps running underneath - it's just a menu.

var _menu := MenuBase.new()
var _buttons: Array = []
var _note: Label


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	add_child(_menu)
	_menu.build_overlay(0.65)
	_menu.content.add_child(UiTheme.title("PAUSED", 56))
	_note = UiTheme.label("", 18, Palette.ACCENT_2)
	_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_menu.content.add_child(_note)
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 6
	_menu.content.add_child(spacer)
	if Net.is_online():
		_buttons = [
			_menu.add_button("Resume", close),
			_menu.add_button("Settings", _menu.open_settings),
			_menu.add_button("Leave Match", _leave_online),
		]
	else:
		_buttons = [
			_menu.add_button("Resume", close),
			_menu.add_button("Settings", _menu.open_settings),
			_menu.add_button("Restart", func(): MatchManager.start_match()),
			_menu.add_button("Change Players", func(): MatchManager.to_lobby()),
			_menu.add_button("Main Menu", func(): MatchManager.to_menu()),
		]
	MenuBase.link_vertical(_buttons)


func open(note := "") -> void:
	_note.text = note
	_note.visible = note != ""
	if visible:
		return
	visible = true
	if not Net.is_online():
		get_tree().paused = true
	Sfx.play("ui_select")
	_menu.focus_first()
	SignalBus.game_paused.emit(true)


func close() -> void:
	visible = false
	if not Net.is_online():
		get_tree().paused = false
	SignalBus.game_paused.emit(false)


static func _leave_online() -> void:
	Net.leave()
	MatchManager.to_menu()


func _unhandled_input(event: InputEvent) -> void:
	if not visible or _menu.sub_open:
		return
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		Sfx.play("ui_back")
		close()
