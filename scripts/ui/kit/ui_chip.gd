class_name UiChip
extends PanelContainer

## A little stamped tag: a rank, NEW BEST, SOON.

var _label: Label
var _color: Color


func _init(text := "", color := Palette.MUSTARD, font_size := 16) -> void:
	theme_type_variation = "Chip"
	size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label = UiTheme.label(text.to_upper(), font_size, Palette.INK)
	_label.add_theme_font_override("font", UiTheme.heavy())
	add_child(_label)
	set_color(color)


func set_text(text: String) -> void:
	_label.text = text.to_upper()


func set_color(color: Color) -> void:
	_color = color
	_label.add_theme_color_override("font_color", Palette.INK if color.get_luminance() > 0.45 else Palette.PAPER)
	if not is_inside_tree():
		return
	var s: StyleBoxFlat = get_theme_stylebox("panel", "Chip").duplicate()
	s.bg_color = color
	add_theme_stylebox_override("panel", s)


func _enter_tree() -> void:
	set_color(_color)
