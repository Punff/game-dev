class_name MenuBase
extends Control

## Shared helpers for code-built menus: dim overlay, centred panel,
## a vertical button list with wrap-around focus, and remembering focus.

signal closed

var panel: PanelContainer
var content: VBoxContainer
var _last_focus: Control
var sub_open := false   ## a nested menu (settings) currently owns input


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


## Makes up/down wrap around a list of controls.
static func link_vertical(controls: Array) -> void:
	var list := controls.filter(func(c): return c.visible)
	for i in list.size():
		var c: Control = list[i]
		c.focus_neighbor_top = c.get_path_to(list[(i - 1 + list.size()) % list.size()])
		c.focus_neighbor_bottom = c.get_path_to(list[(i + 1) % list.size()])
		c.focus_neighbor_left = c.get_path()
		c.focus_neighbor_right = c.get_path()


func focus_first() -> void:
	for c in find_children("*", "BaseButton", true, false):
		if c.visible and not c.disabled:
			c.grab_focus.call_deferred()
			return


func remember_focus() -> void:
	_last_focus = get_viewport().gui_get_focus_owner()


func restore_focus() -> void:
	if is_instance_valid(_last_focus) and _last_focus.is_visible_in_tree():
		_last_focus.grab_focus.call_deferred()
	else:
		focus_first()


## Pops a centred SettingsMenu on top of this menu and refocuses afterwards.
func open_settings() -> void:
	open_sub(SettingsMenu.new())


## Pops any overlay menu on top of this one and refocuses once it closes.
func open_sub(s: MenuBase) -> void:
	remember_focus()
	s.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(s)
	sub_open = true
	s.closed.connect(func():
		s.queue_free()
		sub_open = false
		restore_focus())
