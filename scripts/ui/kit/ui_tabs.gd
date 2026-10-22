class_name UiTabs
extends VBoxContainer

## A tab strip and the page body under it. Tabs are built when shown, by a
## builder that fills the given container (and wires its own focus).
## LB/RB or Q/E step through them (the sleeve forwards those, and the footer
## shows the keys); the tab buttons themselves are for the mouse.

signal switched(index: int)

var index := -1
var body := VBoxContainer.new()
var _strip := HBoxContainer.new()
var _names: Array[String] = []
var _builders: Array[Callable] = []
var _buttons: Array[Button] = []
var _scroll := ScrollContainer.new()


func _init() -> void:
	add_theme_constant_override("separation", 14)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_strip.add_theme_constant_override("separation", 6)
	add_child(_strip)
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	add_child(_scroll)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
	_scroll.add_child(body)


## builder(body: VBoxContainer) fills the tab.
func add_tab(tab_name: String, builder: Callable) -> void:
	var i := _names.size()
	_names.append(tab_name)
	_builders.append(builder)
	var b := Button.new()
	b.theme_type_variation = "TabButton"
	b.text = tab_name.to_upper()
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(func(): show_tab(i))
	_strip.add_child(b)
	_buttons.append(b)


func show_tab(i: int, focus := true) -> void:
	i = posmod(i, _names.size())
	var changed := i != index
	index = i
	for k in _buttons.size():
		_buttons[k].button_pressed = k == i
	for c in body.get_children():
		body.remove_child(c)
		c.queue_free()
	_builders[i].call(body)
	_scroll.scroll_vertical = 0
	if changed and is_inside_tree():
		UiFx.bump(_buttons[i], 0.15)
	if focus:
		UiNav.focus_first(body)
	switched.emit(i)


func step(dir: int) -> void:
	if _names.size() < 2:
		return
	Sfx.play("ui_move")
	show_tab(index + dir)


func count() -> int:
	return _names.size()


func tab_name() -> String:
	return _names[index] if index >= 0 else ""
