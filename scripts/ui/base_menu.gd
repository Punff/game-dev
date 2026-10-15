extends Control
class_name BaseMenu

func _ready() -> void:
	_grab_focus_on_first_button()

func _grab_focus_on_first_button() -> void:
	var buttons = find_children("*", "Button")
	if buttons.size() > 0:
		buttons[0].grab_focus()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if not is_root_menu():
			_on_back_pressed()

func is_root_menu() -> bool:
	return false

func _on_back_pressed() -> void:
	pass
