extends BaseMenu

@onready var result_label = $CenterContainer/PanelContainer/VBoxContainer/ResultLabel

func _ready() -> void:
	super._ready()
	SignalBus.match_ended.connect(_on_match_ended)
	visible = false

func _on_match_ended(results: Dictionary) -> void:
	visible = true
	var winner = results.get("winner", -1)
	result_label.text = "PLAYER %d WINS" % winner if winner != -1 else "DRAW"
	_grab_focus_on_first_button()
	get_tree().paused = true

func _on_restart_pressed() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()

func _on_menu_pressed() -> void:
	MatchManager.reset_to_menu()
