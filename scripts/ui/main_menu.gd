extends Control

func _ready():
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	await get_tree().process_frame
	$CenterContainer/PanelContainer/VBoxContainer/PlayBtn.grab_focus()

func _on_play_pressed():
	get_tree().change_scene_to_file("res://scenes/ui/lobby.tscn")

func _on_settings_pressed():
	get_tree().change_scene_to_file("res://scenes/ui/settings.tscn")

func _on_quit_pressed():
	get_tree().quit()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_tree().quit()
