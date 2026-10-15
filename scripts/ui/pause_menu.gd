extends BaseMenu

@onready var resume_btn = $CenterContainer/PanelContainer/VBoxContainer/ResumeButton
@onready var restart_btn = $CenterContainer/PanelContainer/VBoxContainer/RestartButton
@onready var menu_btn = $CenterContainer/PanelContainer/VBoxContainer/MenuButton

func _ready() -> void:
	super._ready()
	SignalBus.game_paused.connect(_on_paused)
	visible = false

func _on_paused(is_paused: bool) -> void:
	visible = is_paused
	if is_paused:
		get_tree().paused = true
		_grab_focus_on_first_button()
	else:
		get_tree().paused = false

func _on_resume_pressed() -> void:
	SignalBus.game_paused.emit(false)

func _on_restart_pressed() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()

func _on_menu_pressed() -> void:
	MatchManager.reset_to_menu()

func _on_back_pressed() -> void:
	SignalBus.game_paused.emit(false)
