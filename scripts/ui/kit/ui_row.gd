class_name UiRow
extends PanelContainer

## One settings-style line: a label on the left, its control(s) on the right.
## While any of its controls has focus (or the mouse) the whole row peels up
## into a paper sticker, and controls that draw themselves are told so with
## set_lit(). Build rows with the factories: slider(), toggle(), cycler().

## The control focus should land on (first of `controls`).
var control: Control
var controls: Array[Control] = []
var _box := HBoxContainer.new()
var _title: Label
var _extra: Array[Label] = []   # value read-outs that recolour with the row
var _lit := false


func _init(text := "") -> void:
	theme_type_variation = "UiRow"
	custom_minimum_size.y = 50
	_box.add_theme_constant_override("separation", 16)
	add_child(_box)
	_title = UiTheme.label(text, 22, Palette.TEXT)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_box.add_child(_title)
	mouse_entered.connect(_update)
	mouse_exited.connect(_update)


func _enter_tree() -> void:
	_restyle()   # theme lookups need the tree


func add(c: Control) -> UiRow:
	_box.add_child(c)
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if c.focus_mode != Control.FOCUS_NONE:
		controls.append(c)
		if control == null:
			control = c
		c.focus_entered.connect(_update)
		c.focus_exited.connect(_update)
	return self


## A read-out next to the control (e.g. "60%") that follows the row's colours.
func add_value(l: Label) -> UiRow:
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_box.add_child(l)
	_extra.append(l)
	return self


func set_text(text: String) -> void:
	_title.text = text


func _update() -> void:
	var on := controls.any(func(c): return c.has_focus())
	if on == _lit:
		return
	_lit = on
	_restyle()
	for c in controls:
		if c.has_method("set_lit"):
			c.set_lit(on)


func _restyle() -> void:
	if not is_inside_tree():
		return
	add_theme_stylebox_override("panel", get_theme_stylebox("lit" if _lit else "normal", "UiRow"))
	var col := get_theme_color("font_lit_color" if _lit else "font_color", "UiRow")
	_title.add_theme_color_override("font_color", col)
	for l in _extra:
		l.add_theme_color_override("font_color", col if _lit else Palette.TEXT_DIM)


# ── Factories ────────────────────────────────

## Slider bound to a Settings value; shows a percentage.
static func slider(text: String, key: String, lo := 0.0, hi := 1.0) -> UiRow:
	var r := UiRow.new(text)
	var s := UiSlider.new(key, lo, hi)
	r.add(s)
	var pct := UiTheme.label("", 20)
	pct.custom_minimum_size.x = 60
	pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	pct.add_theme_font_override("font", UiTheme.heavy())
	var show := func(v: float): pct.text = "%d%%" % roundi(v * 100)
	show.call(s.value)
	s.value_changed.connect(show)
	r.add_value(pct)
	return r


## On/off switch bound to a Settings value. `custom` replaces the default
## Settings.set_value(key, on).
static func toggle(text: String, key: String, custom := Callable()) -> UiRow:
	var r := UiRow.new(text)
	var t := UiToggle.new(bool(Settings.get_value(key)))
	t.changed.connect(func(on: bool):
		if custom.is_valid():
			custom.call(on)
		else:
			Settings.set_value(key, on))
	r.add(t)
	return r


## "< value >" picker. on_change(index) is called after each step.
static func cycler(text: String, options: Array, index: int, on_change: Callable, swatches: Array = []) -> UiRow:
	var r := UiRow.new(text)
	var c := UiCycler.new(options, index)
	c.swatches = swatches
	c.changed.connect(on_change)
	r.add(c)
	return r
