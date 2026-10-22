class_name PauseMenu
extends CanvasLayer

## Pause: a floating sleeve over the match with Resume, Settings and the ways
## out. Anyone can pause; Start / Esc / B resumes (or backs out of Settings
## first). Online the match keeps running underneath - it's just a menu.

var page := PausePage.new()
var _float: UiSleeve.Floating


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	page.resume.connect(close)
	_float = UiSleeve.floating(page)
	_float.closed.connect(close)
	add_child(_float)
	_float.sleeve.active = false


func open(note := "") -> void:
	page.set_note(note)
	if visible:
		return
	visible = true
	_float.sleeve.to_root()
	_float.sleeve.active = true
	if not Net.is_online():
		get_tree().paused = true
	Sfx.play("ui_select")
	UiFx.stamp(_float.sleeve, 1.08, -2.0)
	page.focus_first()
	SignalBus.game_paused.emit(true)


func close() -> void:
	if not visible:
		return
	visible = false
	_float.sleeve.active = false
	Settings.save_settings()
	if not Net.is_online():
		get_tree().paused = false
	SignalBus.game_paused.emit(false)
