class_name UiCard
extends Button

## A big tile: art on top, a title, a line of small print. Game modes and
## cosmetic slots. Focus peels it up into a paper sticker like every button.
## A locked card still takes focus (so you can see what's coming) but only
## wiggles when pressed.

var art: Control
var locked := false
var _title: Label
var _sub: Label
var _chip: UiChip


func _init(title_text := "", sub_text := "", art_control: Control = null, min_size := Vector2(190, 250)) -> void:
	theme_type_variation = "CardButton"
	custom_minimum_size = min_size
	focus_mode = Control.FOCUS_ALL
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 14
	v.offset_right = -14
	v.offset_top = 12
	v.offset_bottom = -12
	v.add_theme_constant_override("separation", 4)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(v)
	art = art_control if art_control else Control.new()
	art.size_flags_vertical = Control.SIZE_EXPAND_FILL
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(art)
	_title = UiTheme.title(title_text, 30, Palette.PAPER)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	v.add_child(_title)
	_sub = UiTheme.label(sub_text, 16, Palette.TEXT_DIM)
	_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sub.custom_minimum_size.y = 40
	v.add_child(_sub)
	pressed.connect(func(): Sfx.play("ui_select"))
	focus_entered.connect(func(): Sfx.play("ui_move"))
	for s in [focus_entered, focus_exited, mouse_entered, mouse_exited]:
		s.connect(_recolor)
	resized.connect(func(): pivot_offset = size * 0.5)
	UiFx.wire_button(self)


func set_locked(text := "soon") -> void:
	locked = true
	_chip = UiChip.new(text, Palette.SMOKE)
	_chip.position = Vector2(10, 10)
	add_child(_chip)
	modulate = Color(1, 1, 1, 0.75)
	pressed.connect(func(): UiFx.bump(_chip, 0.3))


func _recolor() -> void:
	var lit := has_focus()
	_title.add_theme_color_override("font_color", Palette.INK if lit else Palette.PAPER)
	_title.add_theme_constant_override("outline_size", 0 if lit else 4)
	_sub.add_theme_color_override("font_color", Palette.SMOKE if lit else Palette.TEXT_DIM)
