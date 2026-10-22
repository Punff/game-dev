class_name MenuBase
extends Control

## Shared helpers for the in-game menus (Pause, Results): dim overlay,
## centred panel, a vertical button list with wrap-around focus, and
## remembering focus. The main menu is UiShell (scripts/ui/kit).

signal closed

var panel: PanelContainer
var content: VBoxContainer
var _last_focus: Control
var sub_open := false   ## Settings is open on top and owns input


func build_overlay(dim := 0.6, min_width := 420.0) -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Color(Palette.BG_DEEP, dim)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	panel = PanelContainer.new()
	panel.custom_minimum_size.x = min_width
	center.add_child(panel)
	content = VBoxContainer.new()
	content.add_theme_constant_override("separation", 14)
	panel.add_child(content)


func add_button(text: String, callback: Callable) -> Button:
	var b := UiTheme.button(text)
	b.pressed.connect(callback)
	content.add_child(b)
	return b


func focus_first() -> void:
	UiNav.focus_first(self)


func remember_focus() -> void:
	_last_focus = get_viewport().gui_get_focus_owner()


func restore_focus() -> void:
	if is_instance_valid(_last_focus) and _last_focus.is_visible_in_tree():
		_last_focus.grab_focus.call_deferred()
	else:
		focus_first()


## Settings in a floating sleeve over this menu; refocuses once it closes.
func open_settings() -> void:
	remember_focus()
	var f := UiSleeve.floating(SettingsPage.new())
	add_child(f)
	sub_open = true
	f.closed.connect(func():
		f.queue_free()
		sub_open = false
		restore_focus())
