class_name UiStat
extends PanelContainer

## A number with a caption under it (Profile totals, a run's results).
## set_value() bumps it, for numbers that arrive from the server.

var _value: Label


func _init(caption := "", value := "-") -> void:
	add_theme_stylebox_override("panel", UiTheme.box(Palette.INK_SOFT, Palette.SMOKE, 2, 0, Vector2(14, 8), 4))
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", -4)
	add_child(v)
	_value = UiTheme.title(value, 32, Palette.MUSTARD)
	_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	v.add_child(_value)
	v.add_child(UiTheme.label(caption.to_upper(), 14, Palette.PAPER_DIM))


func set_value(text: String) -> void:
	_value.text = text
	UiFx.bump(_value, 0.1)
